#!/usr/bin/env bash
# ==============================================================================================
# build.sh - build wasm-opt for osx-arm64 and/or osx-x64, from this repository only
# ==============================================================================================
#
#   NEVER YET RUN. Written on Linux on 2026-11-18, which has no Apple SDK. Expect to fix
#   something on the first real run; fix it IN THE SCRIPT and record it in
#   ../BUILD-PROVENANCE.txt, then rewrite this header and README.txt's status block with what
#   the run established.
#
#   ./build.sh                both slices (the default; meant for an Apple Silicon Mac)
#   ./build.sh all            the same
#   ./build.sh arm64          osx-arm64 only
#   ./build.sh x64            osx-x64 only
#
# Options (environment variables):
#   DEPLOYMENT_TARGET_ARM64=11.0   minimum macOS of the arm64 slice (default 11.0 - the first
#                                  macOS on Apple Silicon)
#   DEPLOYMENT_TARGET_X64=10.15    minimum macOS of the x86_64 slice (default 10.15 - binaryen's
#                                  own CMakeLists default, "needed for C++17 std::path")
#   Those two are exactly what upstream's own macOS release binaries get (create_release.yml
#   leaves binaryen's 10.15 default in place, and clang raises it to 11.0 for arm64).
#
# WHAT IT DOES
#   For each slice: copies ../binaryen (vendored, unmodified) to scratch, configures it with
#   Apple clang through CMake's Ninja generator (as upstream's macOS release job does) with the
#   platform-neutral options from ../linux/pins.env and CMAKE_OSX_ARCHITECTURES=<slice>, builds
#   the wasm-opt target ONLY, strips it, signs it ad hoc, gates it, and writes
#   ../output/osx-<arch>/. The C++ runtime is the SYSTEM libc++ (/usr/lib/libc++.1.dylib),
#   which every macOS has; nothing is linked statically but binaryen itself.
#
#   Both slices build on either kind of Mac (cross-compiling with CMAKE_OSX_ARCHITECTURES). The
#   functional gate RUNS a slice where the Mac can execute it: natively, or osx-x64 under
#   Rosetta 2 on Apple Silicon (`softwareupdate --install-rosetta` if you want that run). A
#   slice the Mac cannot run is built and statically checked, and the script says so.
#
# It installs nothing; anything missing is named, with the command that installs it, and the
# script stops. Modelled on CodeBrix.LibGit2's libgit2-native-tools/macos/build.sh.
# ==============================================================================================

set -euo pipefail

trap 'rc=$?; echo "ERROR: build.sh failed (exit $rc) at line $LINENO: $BASH_COMMAND" >&2' ERR

first_line() { sed -n '1p'; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$TOOLS_DIR/output"
SCRATCH_ROOT="${TMPDIR:-/tmp}/codebrix-binaryen-build-macos"
SCRATCH_ROOT="${SCRATCH_ROOT%/}"

# shellcheck source=../linux/pins.env
. "$TOOLS_DIR/linux/pins.env"

# Load commands the executable may link: the system only.
ALLOWED_DYLIBS="/usr/lib/libc++.1.dylib
/usr/lib/libSystem.B.dylib"

# ----------------------------------------------------------------------------------------------
# Prerequisites - checked, never installed
# ----------------------------------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || { echo "ERROR: this script runs on macOS (it needs Xcode's SDK)." >&2; exit 1; }
for tool in cmake ninja xcrun clang++ otool lipo codesign strip shasum gzip od; do
    command -v "$tool" > /dev/null 2>&1 || {
        cat >&2 <<EOF
ERROR: $tool is not on PATH. This script installs nothing. Install:
    xcode-select --install          # clang, the SDK, otool, lipo, codesign, strip
    brew install cmake ninja        # or CMake.app from cmake.org with its CLI on PATH
EOF
        exit 1; }
done
[ -f "$TOOLS_DIR/$BINARYEN_DIR/src/tools/wasm-opt.cpp" ] || {
    echo "ERROR: the vendored binaryen source is missing from $TOOLS_DIR/$BINARYEN_DIR - restore it from git." >&2; exit 1; }
PROJECT_VERSION="$(sed -n 's/^project(binaryen LANGUAGES C CXX VERSION \([0-9]*\)).*/\1/p' "$TOOLS_DIR/$BINARYEN_DIR/CMakeLists.txt")"
[ "$PROJECT_VERSION" = "$BINARYEN_VERSION" ] || { echo "ERROR: CMakeLists.txt says $PROJECT_VERSION, pins.env says $BINARYEN_VERSION" >&2; exit 1; }
[ -f "$TOOLS_DIR/linux/functional-gate.sh" ] && [ -f "$TOOLS_DIR/linux/gate-fixture.wat" ] || {
    echo "ERROR: ../linux/functional-gate.sh or ../linux/gate-fixture.wat is missing; both are part of the repository." >&2; exit 1; }

build_slice() {
    local arch="$1" rid osxarch target scratch build out started
    case "$arch" in
        arm64) rid=osx-arm64; osxarch=arm64;  target="${DEPLOYMENT_TARGET_ARM64:-11.0}" ;;
        x64)   rid=osx-x64;   osxarch=x86_64; target="${DEPLOYMENT_TARGET_X64:-10.15}" ;;
    esac
    scratch="$SCRATCH_ROOT/$rid/binaryen"
    build="$SCRATCH_ROOT/$rid/build"
    out="$OUTPUT_DIR/$rid"
    started="$SECONDS"

    echo
    echo "=============================================================================="
    echo " BUILD $rid  (binaryen $BINARYEN_VERSION, $BINARYEN_TAG, commit $BINARYEN_COMMIT)"
    echo "=============================================================================="
    rm -rf "$SCRATCH_ROOT/$rid"
    mkdir -p "$SCRATCH_ROOT/$rid"
    cp -a "$TOOLS_DIR/$BINARYEN_DIR" "$scratch"

    # -ffile-prefix-map: binaryen keeps assert() on, which embeds __FILE__; this keeps the
    # scratch path (and with it the user name in $TMPDIR) out of the executable.
    local flags="-ffile-prefix-map=$scratch=binaryen -ffile-prefix-map=$build=build -ffile-prefix-map=$TOOLS_DIR=binaryen-native-tools"
    # shellcheck disable=SC2206
    local -a opts=(-G Ninja $BINARYEN_CMAKE_OPTIONS
                   "-DCMAKE_OSX_ARCHITECTURES=$osxarch" "-DCMAKE_OSX_DEPLOYMENT_TARGET=$target"
                   "-DCMAKE_C_FLAGS=$flags" "-DCMAKE_CXX_FLAGS=$flags")
    echo "  cmake ${opts[*]}"
    cmake -S "$scratch" -B "$build" "${opts[@]}" > "$SCRATCH_ROOT/$rid/configure.log" 2>&1 \
        || { tail -60 "$SCRATCH_ROOT/$rid/configure.log" >&2; echo "ERROR: cmake configure failed" >&2; exit 1; }
    local summary
    summary="$(grep -E '^-- (Building|Linking)' "$SCRATCH_ROOT/$rid/configure.log" | sed 's/^-- //' || true)"
    printf '%s\n' "$summary" | sed 's/^/    /'
    cmake --build "$build" --target "$BUILD_TARGET" -j "$(sysctl -n hw.ncpu)" > "$SCRATCH_ROOT/$rid/build.log" 2>&1 \
        || { grep -E -B2 -A8 'error:' "$SCRATCH_ROOT/$rid/build.log" | head -80 >&2; echo "ERROR: build failed" >&2; exit 1; }
    local warnings; warnings="$(grep -c 'warning:' "$SCRATCH_ROOT/$rid/build.log" || true)"

    rm -rf "$out"; mkdir -p "$out"
    local exe="$out/$EXE_NAME"
    cp "$build/bin/$EXE_NAME" "$exe"
    local size_linked; size_linked="$(wc -c < "$exe" | tr -d ' ')"
    # Strip every symbol the executable does not need, then sign ad hoc: stripping invalidates
    # the linker's ad-hoc signature on arm64, and arm64 macOS refuses to run unsigned code.
    strip "$exe"
    codesign --force --sign - "$exe"
    local entry name from
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        name="${entry%%:*}"; from="${entry#*:}"
        cp "$TOOLS_DIR/$from" "$out/$name"
    done <<< "$LICENCE_FILES"

    # ---- THE GATE --------------------------------------------------------------------------
    echo "--- verifying ---"
    local failed=0 gate="$out/GATE.txt"
    : > "$gate"
    fail() { echo "  [FAIL] $1" | tee -a "$gate"; failed=1; }
    pass() { echo "  [ok] $1" | tee -a "$gate"; }

    local archs; archs="$(lipo -archs "$exe")"
    [ "$archs" = "$osxarch" ] && pass "thin $osxarch Mach-O executable" || fail "lipo -archs says '$archs', expected '$osxarch'"

    local deps unexpected="" d
    deps="$(otool -L "$exe" | sed -n '2,$p' | awk '{print $1}')"
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        printf '%s\n' "$ALLOWED_DYLIBS" | grep -F -x -- "$d" > /dev/null || unexpected="$unexpected $d"
    done <<< "$deps"
    [ -z "$unexpected" ] && pass "links the system only: $(printf '%s ' $deps)" || fail "unexpected dylibs:$unexpected"
    if otool -l "$exe" | grep -q LC_RPATH; then fail "LC_RPATH present"; else pass "no LC_RPATH"; fi

    local minos; minos="$(otool -l "$exe" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
    [ "$minos" = "$target" ] && pass "minimum macOS (LC_BUILD_VERSION minos): $minos" || fail "minos is '${minos:-unknown}', expected $target"

    if codesign --verify --strict "$exe" 2> /dev/null; then pass "codesign --verify: ad-hoc signature valid"
    else fail "codesign --verify failed"; fi

    local hits; hits="$(strings -a "$exe" | grep -F -e "$scratch" -e "$build" -e "$TOOLS_DIR" -e "$HOME" || true)"
    [ -z "$hits" ] && pass "no build paths in the binary" || fail "build paths in the binary: $(printf '%s\n' "$hits" | first_line)"

    local want
    for want in "Building libbinaryen as statically linked library." "Building with -DBUILD_LLVM_DWARF" "Building with -UNDEBUG"; do
        printf '%s\n' "$summary" | grep -F -x -- "$want" > /dev/null && pass "configure: $want" || fail "configure did not print: $want"
    done

    local functional="(not run - this Mac cannot execute $osxarch)"
    if arch "-$osxarch" /usr/bin/true 2> /dev/null; then
        echo "  --- functional gate (../linux/functional-gate.sh) ---"
        # functional-gate.sh runs the executable directly; under Rosetta the x86_64 slice is
        # chosen automatically because the file is thin.
        if bash "$TOOLS_DIR/linux/functional-gate.sh" "$exe" "$out/gate-run" 2>&1 | tee -a "$gate"; then
            pass "functional gate: every check passed"; functional="PASSED"
        else
            fail "functional gate failed"; functional="FAILED"
        fi
    else
        echo "  [skip] functional gate: this Mac cannot run $osxarch" | tee -a "$gate"
    fi

    [ "$failed" -eq 0 ] || { echo "VERIFICATION FAILED for $rid - output/$rid must not be adopted." >&2; exit 1; }

    # ---- RECORD ----------------------------------------------------------------------------
    local sha size gzsize
    sha="$(shasum -a 256 "$exe" | cut -d' ' -f1)"
    size="$(wc -c < "$exe" | tr -d ' ')"
    gzsize="$(gzip -9 -n -c "$exe" | wc -c | tr -d ' ')"
    cat > "$out/BUILD-INFO.txt" <<EOF
wasm-opt (binaryen) - build information
==============================================================================
RID              : $rid
Built            : $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Build duration   : $(( SECONDS - started ))s
Built by         : tools/binaryen-native-tools/macos/build.sh
Build host       : $(sw_vers -productName) $(sw_vers -productVersion), $(uname -m)
Xcode            : $(xcodebuild -version 2>/dev/null | tr '\n' ' ')
SDK              : $(xcrun --show-sdk-version)
Compiler         : $(clang++ --version | first_line)
cmake / ninja    : $(cmake --version | first_line) / $(ninja --version)

binaryen         : $BINARYEN_VERSION, tag $BINARYEN_TAG, commit $BINARYEN_COMMIT
Source           : tools/binaryen-native-tools/binaryen/ (vendored, unmodified; copied to scratch)
cmake options    : ${opts[*]}
target           : $BUILD_TARGET only
Compiler warnings: $warnings
binaryen's configure summary:
$(printf '%s\n' "$summary" | sed 's/^/  /')

Result
------------------------------------------------------------------------------
File             : $EXE_NAME (strip, then codesign --force --sign -)
Size (as linked) : $size_linked bytes (not kept)
Size (stripped)  : $size bytes
Size (gzip -9 -n): $gzsize bytes
SHA256           : $sha
Architecture     : $archs
Minimum macOS    : ${minos:-unknown}
Links            : $(printf '%s ' $deps)
Functional gate  : $functional

Gate
------------------------------------------------------------------------------
$(cat "$gate")
EOF
    ( cd "$out" && shasum -a 256 "$EXE_NAME" $(printf '%s\n' "$LICENCE_FILES" | cut -d: -f1) > SHA256SUMS.txt )
    echo "  $exe"
    echo "  sha256 $sha"
}

case "${1:-all}" in
    arm64|x64) build_slice "$1" ;;
    all)       build_slice arm64; build_slice x64 ;;
    *) echo "usage: $0 [all|arm64|x64]" >&2; exit 2 ;;
esac
echo "Done. Adopt with ADOPTING A BUILT BINARY in README.txt."
