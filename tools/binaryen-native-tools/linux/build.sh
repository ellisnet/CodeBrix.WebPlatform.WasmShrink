#!/usr/bin/env bash
# ==============================================================================================
# build.sh - build wasm-opt for linux-x64 and linux-arm64, from this repository only
# ==============================================================================================
#
#   ./build.sh                build both (linux-x64, then linux-arm64)
#   ./build.sh all            the same
#   ./build.sh x64            build linux-x64 only
#   ./build.sh arm64          build linux-arm64 only
#
# Options (environment variables):
#   CONTAINER_ENGINE=podman|docker   force an engine (default: podman, then docker)
#   FORCE_IMAGE_REBUILD=1            rebuild the derived build image even if it exists
#   SKIP_HOST_CHECK=1                do not run the finished binary on this host (see below)
#
# WHAT THIS DOES, IN ONE PARAGRAPH
#   For each architecture it makes sure a derived build image exists (base manylinux image +
#   cmake + ninja + `file` - see Containerfile.<arch>; building it is the one step that uses
#   the network), then runs container-build.sh inside it WITH THE NETWORK DISABLED, mounting
#   tools/binaryen-native-tools/ as /work. Everything compiled comes from this repository: the
#   vendored binaryen snapshot in ../binaryen. container-build.sh builds the wasm-opt target
#   only, strips it and gates it - including RUNNING it on gate-fixture.wat. Then, for a RID
#   this host can execute natively, build.sh runs functional-gate.sh once more ON THE HOST, to
#   prove the binary starts outside the image it was built in.
#
# WHY A CONTAINER, EVEN FOR X64, EVEN ON NATIVE HARDWARE
#   glibc symbol versioning is forward-only: a binary built against the glibc on a current
#   desktop distro refuses to start on anything older, so building on the workstation would
#   quietly restrict the package to the newest distributions - and the failure would only show
#   up on a user's machine. The manylinux_2_28 images fix the floor at glibc 2.28. On a native
#   arm64 machine the same script builds linux-arm64 at full speed; on an x86_64 host it runs
#   under qemu-user emulation, which works but is slow (binaryen is a large C++20 code base -
#   see ../BUILD-PROVENANCE.txt for the measured times).
#
# THIS SCRIPT NEVER INSTALLS ANYTHING ON YOUR MACHINE. If a prerequisite is missing it names it,
# prints the command that installs it, and stops. See README.txt for the full list.
#
# Modelled on CodeBrix.LibGit2's libgit2-native-tools/linux/build.sh.
# ==============================================================================================

set -euo pipefail

trap 'rc=$?; echo "ERROR: build.sh failed (exit $rc) at line $LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"           # tools/binaryen-native-tools/
OUTPUT_DIR="$TOOLS_DIR/output"

# shellcheck source=pins.env
. "$SCRIPT_DIR/pins.env"

# ----------------------------------------------------------------------------------------------
# Prerequisites - checked, never installed
# ----------------------------------------------------------------------------------------------
pick_engine() {
    if [ -n "${CONTAINER_ENGINE:-}" ]; then
        command -v "$CONTAINER_ENGINE" > /dev/null 2>&1 || {
            echo "ERROR: CONTAINER_ENGINE=$CONTAINER_ENGINE is not on PATH." >&2; exit 1; }
        echo "$CONTAINER_ENGINE"
        return
    fi
    if command -v podman > /dev/null 2>&1; then echo podman; return; fi
    if command -v docker > /dev/null 2>&1; then echo docker; return; fi
    cat >&2 <<'EOF'
ERROR: neither podman nor docker is installed.

  This script does not install anything. Install a container engine yourself:

    sudo apt install podman

  Then re-run. See README.txt (PREREQUISITES) for the complete list, and
  "THE BARE-HOST ROUTE" there for building with no container at all.
EOF
    exit 1
}

ENGINE="$(pick_engine)"

[ -f "$TOOLS_DIR/$BINARYEN_DIR/CMakeLists.txt" ] && [ -f "$TOOLS_DIR/$BINARYEN_DIR/src/tools/wasm-opt.cpp" ] || {
    echo "ERROR: the vendored binaryen source is missing from $TOOLS_DIR/$BINARYEN_DIR." >&2
    echo "       Nothing can be built without it, and it is not downloaded - it is part of this" >&2
    echo "       repository. Restore it from git." >&2
    exit 1; }
for f in container-build.sh functional-gate.sh gate-fixture.wat; do
    [ -f "$SCRIPT_DIR/$f" ] || { echo "ERROR: $SCRIPT_DIR/$f is missing; it is part of the repository." >&2; exit 1; }
done

host_machine="$(uname -m)"

arch_rid()      { case "$1" in x64) echo linux-x64;; arm64) echo linux-arm64;; esac; }
arch_platform() { case "$1" in x64) echo linux/amd64;; arm64) echo linux/arm64;; esac; }
arch_native()   { case "$1" in x64) echo x86_64;; arm64) echo aarch64;; esac; }
arch_image()    {
    case "$1" in
        x64)   echo "${IMAGE_X64%%:*}@$IMAGE_X64_DIGEST" ;;
        arm64) echo "${IMAGE_ARM64%%:*}@$IMAGE_ARM64_DIGEST" ;;
    esac
}
arch_tag()       { case "$1" in x64) echo "$IMAGE_X64";; arm64) echo "$IMAGE_ARM64";; esac; }
arch_glibc_max() { case "$1" in x64) echo "$GLIBC_MAX_X64";; arm64) echo "$GLIBC_MAX_ARM64";; esac; }

check_emulation() {
    local arch="$1" want
    want="$(arch_native "$arch")"
    [ "$want" = "$host_machine" ] && { echo "  emulation : none needed - native $want host"; return 0; }

    # Non-native architecture: the kernel needs a binfmt_misc handler registered for it,
    # otherwise the container starts and every command inside it dies with "exec format error".
    # grep WITHOUT -q on purpose: -q exits at the first match, `ls` then dies of SIGPIPE, and
    # under `set -o pipefail` that reads as "no handler registered".
    if [ -d /proc/sys/fs/binfmt_misc ] && ls /proc/sys/fs/binfmt_misc 2>/dev/null | grep -i "qemu-$want" > /dev/null; then
        echo "  emulation : qemu-$want binfmt handler registered (expect a SLOW build)"
        return 0
    fi
    cat >&2 <<EOF

ERROR: building $arch on a $host_machine host needs qemu user-mode emulation, and no
       binfmt handler for qemu-$want is registered.

  The simplest route is to run this script on a native $want machine. If you must build
  here instead, set up emulation yourself (it is not done for you):

       sudo apt install qemu-user-static binfmt-support

  Verify with:  ls /proc/sys/fs/binfmt_misc | grep qemu

EOF
    exit 1
}

ensure_image() {
    local arch="$1" narch derived base platform
    narch="$(arch_native "$arch")"
    derived="$DERIVED_IMAGE_PREFIX-$narch"
    base="$(arch_image "$arch")"
    platform="$(arch_platform "$arch")"

    if [ "${FORCE_IMAGE_REBUILD:-0}" != "1" ] && "$ENGINE" image exists "$derived" 2>/dev/null; then
        echo "  image     : $derived (already built - reusing)"
        return 0
    fi

    echo "  image     : $derived - building it now."
    echo "              THIS IS THE ONE STEP THAT USES THE NETWORK: it installs cmake"
    echo "              ${CMAKE_VERSION}, ninja ${NINJA_VERSION} and \`file\` into the"
    echo "              digest-pinned base image. The wasm-opt build afterwards runs with"
    echo "              --network none."
    "$ENGINE" build \
        --platform "$platform" \
        -f "$SCRIPT_DIR/Containerfile.$narch" \
        -t "$derived" \
        --build-arg BASE_IMAGE="$base" \
        --build-arg CMAKE_VERSION="$CMAKE_VERSION" \
        --build-arg NINJA_VERSION="$NINJA_VERSION" \
        --build-arg PYTHON_IN_IMAGE="$PYTHON_IN_IMAGE" \
        "$SCRIPT_DIR"
}

# Run the finished binary on THIS machine, outside any container, when the host can execute it
# natively. Proves it starts on a real distribution (the host's glibc, no image libraries).
host_check() {
    local arch="$1" rid exe log
    rid="$(arch_rid "$arch")"
    exe="$OUTPUT_DIR/$rid/$EXE_NAME"
    log="$OUTPUT_DIR/$rid/HOST-CHECK.txt"
    if [ "${SKIP_HOST_CHECK:-0}" = "1" ]; then echo "  host check: skipped (SKIP_HOST_CHECK=1)"; return 0; fi
    if [ "$(arch_native "$arch")" != "$host_machine" ]; then
        echo "  host check: not possible - this $host_machine host cannot run $rid natively"
        return 0
    fi
    rm -rf "$OUTPUT_DIR/$rid/host-run"
    {
        echo "wasm-opt $rid - run on the build HOST, outside the container"
        echo "=============================================================================="
        echo "Run at   : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "Host     : $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}"), $(uname -srm)"
        echo "glibc    : $(ldd --version 2>&1 | sed -n 1p)"
        echo "ldd      :"
        ldd "$exe" 2>&1 | sed 's/^/  /'
        echo
    } > "$log"
    echo "  --- host check: functional-gate.sh on this machine ---"
    if bash "$SCRIPT_DIR/functional-gate.sh" "$exe" "$OUTPUT_DIR/$rid/host-run" 2>&1 | tee -a "$log"; then
        echo "  [ok] host check passed ($log)"
    else
        echo "  [FAIL] host check failed - see $log" >&2
        exit 1
    fi
}

build_arch() {
    local arch="$1" rid narch derived base platform started elapsed
    rid="$(arch_rid "$arch")"
    narch="$(arch_native "$arch")"
    derived="$DERIVED_IMAGE_PREFIX-$narch"
    base="$(arch_image "$arch")"
    platform="$(arch_platform "$arch")"
    started="$SECONDS"

    echo
    echo "=============================================================================="
    echo " BUILD $rid"
    echo "=============================================================================="
    echo "  base tag  : $(arch_tag "$arch")"
    echo "  base pin  : $base"
    echo "  platform  : $platform"
    echo "  host      : $host_machine"
    check_emulation "$arch"
    ensure_image "$arch"
    echo "  network   : DISABLED for the build itself (--network none)"
    echo

    "$ENGINE" run --rm \
        --network none \
        --platform "$platform" \
        -v "$TOOLS_DIR":/work:Z \
        -e TARGET_RID="$rid" \
        -e DERIVED_IMAGE="$derived" \
        -e BASE_IMAGE_REF="$base" \
        -e GLIBC_MAX="$(arch_glibc_max "$arch")" \
        "$derived" \
        bash /work/linux/container-build.sh

    host_check "$arch"

    elapsed=$(( SECONDS - started ))
    echo "  $rid finished in ${elapsed}s (end to end, including any image build)"
}

write_sha256sums() {
    # One checksum file covering every built RID, including any built on other machines and
    # copied in. Paths are relative to output/.
    [ -d "$OUTPUT_DIR" ] || return 0
    ( cd "$OUTPUT_DIR" && \
      find . -mindepth 2 -maxdepth 2 -type f \( -name "$EXE_NAME" -o -name "$EXE_NAME.exe" \) -print \
        | sed 's|^\./||' | sort | xargs -r sha256sum > SHA256SUMS )
    echo
    echo "  output/SHA256SUMS:"
    sed 's/^/    /' "$OUTPUT_DIR/SHA256SUMS"
}

# ----------------------------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------------------------
TARGET="${1:-all}"

echo "container engine : $ENGINE"
echo "tools folder     : $TOOLS_DIR"
echo "binaryen         : $BINARYEN_VERSION ($BINARYEN_TAG), commit $BINARYEN_COMMIT"
echo "cmake / ninja    : $CMAKE_VERSION / $NINJA_VERSION (pinned, inside the images)"

case "$TARGET" in
    x64|arm64) build_arch "$TARGET" ;;
    all)       for a in x64 arm64; do build_arch "$a"; done ;;
    *) echo "usage: $0 [all|x64|arm64]" >&2; exit 2 ;;
esac

write_sha256sums

echo
echo "=============================================================================="
echo " Outputs are in tools/binaryen-native-tools/output/<rid>/"
echo "   $EXE_NAME                 stripped - the file the package ships"
echo "   LICENSE-*.txt            the licences of everything compiled into it"
echo "   BUILD-INFO.txt           toolchain, pins, sizes, sha256, glibc floor, the gate"
echo "   third-party-evidence.txt what the linker actually put in (from its map file)"
echo "   HOST-CHECK.txt           the run on this host (linux-x64 on an x86_64 host)"
echo " To adopt them into the package, follow ADOPTING A BUILT BINARY in README.txt."
echo "=============================================================================="
