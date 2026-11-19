#!/usr/bin/env bash
# ==============================================================================================
# container-build.sh - builds AND verifies wasm-opt INSIDE the build container
# ==============================================================================================
#
# Do not run this on your workstation. build.sh runs it inside the derived image
# (codebrix-binaryen-build-<arch>) for the requested architecture, WITH THE NETWORK DISABLED:
#
#     podman run --network none ... codebrix-binaryen-build-<arch> bash /work/linux/container-build.sh
#
# That is not decoration. It is the mechanical proof of the rule this folder exists for: if any
# step ever tried to fetch a source file or a dependency, it would fail here instead of quietly
# working on the machine that happened to have a network. Step 0 below prints the proof into
# the build log.
#
# It expects:
#   /work            tools/binaryen-native-tools/, mounted read-write (only output/ is written)
#   $TARGET_RID      linux-x64 | linux-arm64
#   $GLIBC_MAX       the glibc floor allowed for that RID (build.sh takes it from pins.env)
#   $DERIVED_IMAGE, $BASE_IMAGE_REF   recorded only
# Every other pin is read from /work/linux/pins.env, the same file build.sh sources, so the two
# can never disagree.
#
# Everything it compiles is already in the repository: /work/binaryen is the vendored upstream
# snapshot, and the gate's fixture is /work/linux/gate-fixture.wat. There is nothing to
# download. Modelled on CodeBrix.LibGit2's libgit2-native-tools/linux/container-build.sh.
# ==============================================================================================

set -euo pipefail

trap 'rc=$?; echo "ERROR: container-build.sh failed (exit $rc) at line $LINENO: $BASH_COMMAND" >&2' ERR

# first_line: the first line of stdin WITHOUT the `head -1` pitfall. `cmd | head -1` inside $(...)
# under `set -o pipefail` can end the script silently: head exits early, the writer gets SIGPIPE,
# the pipeline reports 141. `sed -n 1p` reads its input to the end.
first_line() { sed -n '1p'; }
strip_ansi() { sed 's/\x1b\[[0-9;]*[mK]//g'; }

WORK=/work
# shellcheck source=pins.env
. "$WORK/linux/pins.env"

SRC="$WORK/$BINARYEN_DIR"
SCRATCH=/tmp/codebrix-binaryen-src
BUILD=/tmp/codebrix-binaryen-build
OUT="$WORK/output/$TARGET_RID"
STARTED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
START_SECONDS="$SECONDS"
CONTAINER_OS="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | first_line | cut -d= -f2- | tr -d '"')"

echo "=============================================================================="
echo " binaryen $BINARYEN_VERSION ($BINARYEN_TAG, $BINARYEN_COMMIT) - wasm-opt for $TARGET_RID"
echo "=============================================================================="
echo " started   : $STARTED_AT"
echo " container : $CONTAINER_OS"
echo " image     : ${DERIVED_IMAGE:-unknown}"
echo " base      : ${BASE_IMAGE_REF:-unknown}"
echo " arch      : $(uname -m)"
echo

# ----------------------------------------------------------------------------------------------
# 0. Prove there is no network. With --network none the container has only the loopback
#    interface, so this is a fact about the sandbox, not a promise about the script.
# ----------------------------------------------------------------------------------------------
IFACES="$(ls /sys/class/net 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
echo "--- network ---"
echo "  interfaces: ${IFACES:-none}"
if [ "$IFACES" = "lo" ] || [ -z "$IFACES" ]; then
    echo "  [ok] no external network interface - this build cannot reach outside the repository"
else
    echo "  [warn] this container HAS a network interface ($IFACES)."
    echo "         The build still fetches nothing, but the proof is weaker. build.sh normally"
    echo "         passes --network none; something overrode it."
fi
echo

# ----------------------------------------------------------------------------------------------
# 1. Toolchain. Everything here was installed by Containerfile.<arch> when the derived image was
#    built - the one documented, network-using step. Nothing is installed now.
# ----------------------------------------------------------------------------------------------
echo "--- toolchain ---"
for t in cc c++ cmake ninja file nm objdump readelf strip strings gzip od sha256sum; do
    command -v "$t" > /dev/null 2>&1 || { echo "ERROR: $t is missing from this image. Rebuild it: FORCE_IMAGE_REBUILD=1 ./build.sh" >&2; exit 1; }
done
CXX_VERSION="$(c++ --version | first_line)"
CXX_MAJOR="$(c++ -dumpversion | cut -d. -f1)"
LD_VERSION="$(ld --version | first_line)"
CMAKE_ACTUAL="$(cmake --version | first_line)"
NINJA_ACTUAL="$(ninja --version)"
GLIBC_ACTUAL="$(ldd --version | first_line)"
echo "  c++     : $CXX_VERSION"
echo "  ld      : $LD_VERSION"
echo "  cmake   : $CMAKE_ACTUAL (pinned $CMAKE_VERSION)"
echo "  ninja   : $NINJA_ACTUAL (pinned $NINJA_VERSION)"
echo "  glibc   : $GLIBC_ACTUAL"
if [ "$CXX_MAJOR" -lt "$MIN_GCC_MAJOR" ]; then
    echo "ERROR: GCC $CXX_MAJOR is too old for binaryen's C++20 (pins.env MIN_GCC_MAJOR=$MIN_GCC_MAJOR)" >&2; exit 1
fi
echo "  [ok] GCC $CXX_MAJOR >= $MIN_GCC_MAJOR (C++20)"
echo

# ----------------------------------------------------------------------------------------------
# 2. Source. The vendored tree is copied to scratch and built THERE, so /work/binaryen is never
#    written to and stays a verifiable, unmodified upstream snapshot. There is no patch step.
#    The scratch copy has no .git, so binaryen's CMake reports its plain project version (133)
#    without running `git describe` - which is also what the upstream tarball gives.
# ----------------------------------------------------------------------------------------------
echo "--- source ---"
[ -f "$SRC/CMakeLists.txt" ] && [ -f "$SRC/src/tools/wasm-opt.cpp" ] \
    || { echo "ERROR: no vendored binaryen source at $SRC" >&2; exit 1; }
CMAKE_PROJECT_VERSION="$(sed -n 's/^project(binaryen LANGUAGES C CXX VERSION \([0-9]*\)).*/\1/p' "$SRC/CMakeLists.txt")"
[ "$CMAKE_PROJECT_VERSION" = "$BINARYEN_VERSION" ] \
    || { echo "ERROR: CMakeLists.txt says version '$CMAKE_PROJECT_VERSION', pins.env says '$BINARYEN_VERSION'" >&2; exit 1; }
rm -rf "$SCRATCH" "$BUILD"
cp -a "$SRC" "$SCRATCH"
echo "  copied $SRC -> $SCRATCH (project version $CMAKE_PROJECT_VERSION)"
echo

# ----------------------------------------------------------------------------------------------
# 3. Configure. The options come from pins.env. The flags added here:
#      -ffile-prefix-map=...      rewrite the scratch paths, so no build path lands in the binary
#                                 (binaryen keeps assertions on, and assert() embeds __FILE__)
#                                 and repeat builds are byte-identical
#      -static-libstdc++ -static-libgcc
#                                 the C++ runtime is linked in; glibc stays dynamic
#      -Wl,-z,stack-size=8388608  the 8 MB main-thread stack upstream's Linux release links with
#                                 (create_release.yml; binaryen issue 8594). glibc's thread stacks
#                                 follow RLIMIT_STACK, which this does not change
#      -Wl,--build-id=sha1        an identity for the file; recorded
#      -Wl,-Map=<build>/wasm-opt.map
#                                 the linker's map: the EVIDENCE of which object files - and so
#                                 which third-party pieces - end up inside wasm-opt. Never shipped.
#    No -g: there is no debug information to strip or to keep.
# ----------------------------------------------------------------------------------------------
COMPILE_FLAGS="-ffile-prefix-map=$SCRATCH=binaryen -ffile-prefix-map=$BUILD=build -ffile-prefix-map=$WORK=binaryen-native-tools"
LINK_FLAGS="-static-libstdc++ -static-libgcc -Wl,-z,stack-size=8388608 -Wl,--build-id=sha1 -Wl,-Map=$BUILD/wasm-opt.map"
echo "--- configuring ---"
echo "  cmake -S $SCRATCH -B $BUILD -G Ninja"
echo "        $BINARYEN_CMAKE_OPTIONS"
echo "        -DCMAKE_C_FLAGS=\"$COMPILE_FLAGS\" -DCMAKE_CXX_FLAGS=\"$COMPILE_FLAGS\""
echo "        -DCMAKE_EXE_LINKER_FLAGS=\"$LINK_FLAGS\""
mkdir -p "$BUILD"
# shellcheck disable=SC2086
cmake -S "$SCRATCH" -B "$BUILD" -G Ninja \
    $BINARYEN_CMAKE_OPTIONS \
    -DCMAKE_C_FLAGS="$COMPILE_FLAGS" \
    -DCMAKE_CXX_FLAGS="$COMPILE_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$LINK_FLAGS" > "$BUILD/configure.log" 2>&1 \
    || { echo "ERROR: cmake configure failed:" >&2; tail -60 "$BUILD/configure.log" >&2; exit 1; }

RELEASE_FLAGS="$(sed -n 's/^CMAKE_CXX_FLAGS_RELEASE:[A-Z]*=//p' "$BUILD/CMakeCache.txt" | first_line)"
echo "  CMAKE_CXX_FLAGS_RELEASE (CMake's cache value; binaryen appends -UNDEBUG): $RELEASE_FLAGS"
# binaryen's own configure messages ("Building with ...", "Linking with ...", the library kind).
CONFIG_SUMMARY="$(grep -E '^-- (Building|Linking|No build type)' "$BUILD/configure.log" | sed 's/^-- //' || true)"
echo "  binaryen's configure summary:"
printf '%s\n' "$CONFIG_SUMMARY" | sed 's/^/    /'
CMAKE_WARNINGS="$(grep -c 'CMake Warning' "$BUILD/configure.log" || true)"
echo "  CMake warnings: $CMAKE_WARNINGS"

echo
echo "--- building target $BUILD_TARGET only ($(nproc) jobs) ---"
cmake --build "$BUILD" --target "$BUILD_TARGET" -j "$(nproc)" > "$BUILD/build.log" 2>&1 \
    || { echo "ERROR: build failed:" >&2; strip_ansi < "$BUILD/build.log" | grep -E -B2 -A8 'error:|FAILED:' | head -80 >&2; exit 1; }
strip_ansi < "$BUILD/build.log" > "$BUILD/build.clean.log"
echo "  $(tail -1 "$BUILD/build.clean.log")"
WARNINGS="$(grep -c 'warning:' "$BUILD/build.clean.log" || true)"
EDGES="$(grep -c '^\[[0-9]*/[0-9]*\]' "$BUILD/build.clean.log" || true)"
echo "  build steps: $EDGES; compiler warnings: $WARNINGS"
echo

# ----------------------------------------------------------------------------------------------
# 4. Evidence of what is compiled in. From the linker map: every archive member linked into
#    wasm-opt, per archive. From ninja's dependency log: every object that included an FP16
#    header (FP16 is header-only, so it shows up as includes, not as an archive).
# ----------------------------------------------------------------------------------------------
BUILT="$BUILD/bin/$EXE_NAME"
[ -f "$BUILT" ] || { echo "ERROR: the build did not produce $BUILT" >&2; ls -la "$BUILD/bin" >&2 || true; exit 1; }
EVIDENCE="$BUILD/third-party-evidence.txt"
{
    echo "Archive members linked into $EXE_NAME (from the GNU ld map file, section"
    echo "\"Archive member included to satisfy reference by file (symbol)\")"
    echo "=============================================================================="
    # Every "<archive path>(<member>)" in the map's archive-member section, as "<archive> <member>".
    ALL_MEMBERS="$(sed -n '/^Archive member included/,/^Discarded input sections/p' "$BUILD/wasm-opt.map" \
        | grep -oE '[^ ()]+\.a\([^)]+\)' \
        | awk -F'(' '{n=split($1, p, "/"); m=$2; sub(/\)$/, "", m); print p[n], m}' | sort -u || true)"
    echo
    echo "--- every archive that contributed members (count, archive):"
    printf '%s\n' "$ALL_MEMBERS" | awk '{print $1}' | sort | uniq -c | sed 's/^/  /'
    BINARYEN_MEMBERS="$(printf '%s\n' "$ALL_MEMBERS" | awk '$1 == "libbinaryen.a" {print $2}')"

    # third_party/llvm-project is a CMake OBJECT library (llvm_dwarf) linked PRIVATE into
    # binaryen, so its objects are members of libbinaryen.a, not an archive of their own. Each
    # llvm_dwarf object is matched by file name against the libbinaryen.a members the linker
    # pulled in (names compared exactly; a name that also exists elsewhere in the build is
    # flagged, so a match can never be ambiguous without saying so).
    ALL_OBJ_NAMES="$(cd "$BUILD" && find . -name '*.o' | sed 's|.*/||' | sort)"
    echo
    echo "--- third_party/llvm-project (CMake object library llvm_dwarf), per object:"
    for o in $(cd "$BUILD/third_party/llvm-project/CMakeFiles/llvm_dwarf.dir" && find . -name '*.o' | sed 's|.*/||' | LC_ALL=C sort); do
        dup=""
        [ "$(printf '%s\n' "$ALL_OBJ_NAMES" | grep -c -x -F -- "$o")" -gt 1 ] && dup="   (NAME ALSO USED ELSEWHERE IN THE BUILD)"
        if printf '%s\n' "$BINARYEN_MEMBERS" | grep -x -F -- "$o" > /dev/null; then echo "  LINKED      $o$dup"
        else echo "  not linked  $o$dup"; fi
    done
    echo
    echo "--- binaryen sources derived from LLVM (Apache-2.0 WITH LLVM-exception headers):"
    for o in suffix_tree.cpp.o suffix_tree_node.cpp.o; do
        if printf '%s\n' "$BINARYEN_MEMBERS" | grep -x -F -- "$o" > /dev/null; then echo "  LINKED      src/support/$o"
        else echo "  not linked  src/support/$o"; fi
    done
    for lib in libbinaryen.a libstdc++.a libgcc_eh.a libgcc.a libc_nonshared.a; do
        members="$(printf '%s\n' "$ALL_MEMBERS" | awk -v a="$lib" '$1 == a {print $2}')"
        echo
        echo "--- $lib: $(printf '%s\n' "$members" | grep -c . || true) members"
        printf '%s\n' "$members" | sed 's/^/  /'
    done
    echo
    echo "Objects whose compile included a third_party/FP16 header (ninja -t deps)"
    echo "=============================================================================="
    ( cd "$BUILD" && ninja -t deps ) | awk '/^[^ ].*: #deps/{obj=$1} /third_party\/FP16\//{print obj}' | sed 's/:$//' | sort -u | sed 's/^/  /'
    echo
    echo "Objects whose compile included a third_party/wabt header (expected: none)"
    echo "=============================================================================="
    ( cd "$BUILD" && ninja -t deps ) | awk '/^[^ ].*: #deps/{obj=$1} /third_party\/wabt\//{print obj}' | sed 's/:$//' | sort -u | sed 's/^/  /'
} > "$EVIDENCE"
LLVM_SECTION="$(sed -n '/^--- third_party\/llvm-project/,/^$/p' "$EVIDENCE")"
LLVM_LINKED="$(printf '%s\n' "$LLVM_SECTION" | grep -c '^  LINKED ' || true)"
LLVM_TOTAL="$(printf '%s\n' "$LLVM_SECTION" | grep -c -E '^  (LINKED|not linked) ' || true)"
LLVM_MEMBERS="$LLVM_LINKED of $LLVM_TOTAL"
FP16_USERS="$(sed -n '/FP16 header/,/^$/p' "$EVIDENCE" | grep -c '^  ' || true)"
echo "--- third-party evidence ---"
echo "  third_party/llvm-project objects linked into wasm-opt: $LLVM_MEMBERS"
for m in ConvertUTF.cpp.o MD5.cpp.o Path.cpp.o; do
    grep -E "^  (LINKED|not linked) +$m" "$EVIDENCE" | sed 's/^/  /' || echo "    $m: not built"
done
grep -E "^  (LINKED|not linked) +src/support/" "$EVIDENCE" | sed 's/^/  /' || true
if grep -q 'NAME ALSO USED ELSEWHERE' "$EVIDENCE"; then echo "  NOTE: some llvm_dwarf object names are not unique in the build - see third-party-evidence.txt"; fi
echo "  objects including FP16 headers: $FP16_USERS"
echo

# ----------------------------------------------------------------------------------------------
# 5. Collect + strip. The shipped file is the stripped executable; nothing else is kept of the
#    unstripped one but its size.
# ----------------------------------------------------------------------------------------------
echo "--- collecting ---"
rm -rf "$OUT"
mkdir -p "$OUT"
SIZE_UNSTRIPPED="$(stat -c %s "$BUILT")"
cp "$BUILT" "$OUT/$EXE_NAME"
strip --strip-all "$OUT/$EXE_NAME"
chmod 0755 "$OUT/$EXE_NAME"
EXE="$OUT/$EXE_NAME"
SIZE_STRIPPED="$(stat -c %s "$EXE")"
SIZE_GZIP="$(gzip -9 -n -c "$EXE" | wc -c)"
build_id_of() { { readelf -n "$1" 2>/dev/null || true; } | awk '/Build ID/{print $3}' | first_line; }
BUILD_ID="$(build_id_of "$EXE")"
echo "  as linked: $SIZE_UNSTRIPPED bytes -> stripped: $SIZE_STRIPPED bytes (gzip -9: $SIZE_GZIP bytes)"
echo "  build-id : ${BUILD_ID:-none}"
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name="${entry%%:*}"; from="${entry#*:}"
    [ -f "$WORK/$from" ] || { echo "ERROR: licence source $from is missing" >&2; exit 1; }
    cp "$WORK/$from" "$OUT/$name"
    echo "  $name <- $from"
done <<< "$LICENCE_FILES"
cp "$EVIDENCE" "$OUT/third-party-evidence.txt"
cp "$BUILD/configure.log" "$OUT/cmake-configure.log"
echo

# ----------------------------------------------------------------------------------------------
# 6. THE GATE. A build that fails any check is reported as failed and this script exits
#    non-zero; output/<rid> is left for inspection but must not be adopted.
# ----------------------------------------------------------------------------------------------
echo "--- verifying ---"
FAILED=0
fail() { echo "  [FAIL] $1"; FAILED=1; }
pass() { echo "  [ok] $1"; }
GATE_LOG="$OUT/GATE.txt"
{
# 6a. ELF class and machine.
FILE_OUT="$(file -b "$EXE")"
ELF_CLASS="$(readelf -h "$EXE" | awk -F: '/Class:/{gsub(/^ +/,"",$2); print $2}')"
ELF_MACHINE="$(readelf -h "$EXE" | awk -F: '/Machine:/{gsub(/^ +/,"",$2); print $2}')"
ELF_TYPE="$(readelf -h "$EXE" | awk -F: '/Type:/{gsub(/^ +/,"",$2); print $2}')"
case "$TARGET_RID" in
    linux-x64)   WANT_MACHINE="Advanced Micro Devices X86-64" ;;
    linux-arm64) WANT_MACHINE="AArch64" ;;
    *)           WANT_MACHINE="?" ;;
esac
if [ "$ELF_CLASS" = "ELF64" ] && [ "$ELF_MACHINE" = "$WANT_MACHINE" ]; then
    pass "ELF class/machine: $ELF_CLASS / $ELF_MACHINE, type $ELF_TYPE ($FILE_OUT)"
else
    fail "ELF class/machine: got '$ELF_CLASS' / '$ELF_MACHINE', expected ELF64 / '$WANT_MACHINE'"
fi

# 6b. Stripped: no symbol table, no debug sections.
SECTIONS="$(readelf -S -W "$EXE" | awk '/^ *\[ *[0-9]+\]/{sub(/^ *\[ *[0-9]+\] */,""); print $1}')"
LEFTOVER="$(printf '%s\n' "$SECTIONS" | grep -E '^\.(symtab|strtab|debug_)' | tr '\n' ' ' || true)"
if [ -z "$LEFTOVER" ]; then pass "stripped: no .symtab / .strtab / .debug_* sections"
else fail "not stripped: $LEFTOVER"; fi

# 6c. No RPATH / RUNPATH, no TEXTREL.
RPATHS="$(readelf -d "$EXE" | grep -E '\((RPATH|RUNPATH)\)' || true)"
if [ -z "$RPATHS" ]; then pass "no RPATH / RUNPATH"; else fail "RPATH/RUNPATH present: $RPATHS"; fi
if readelf -d "$EXE" | grep -q TEXTREL; then fail "TEXTREL present"; else pass "no TEXTREL"; fi

# 6d. Dependencies: glibc only. libstdc++ / libgcc_s must be absent (static).
DEPS="$(readelf -d "$EXE" | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p')"
DEPS_SORTED="$(printf '%s\n' $DEPS | sort | tr '\n' ' ' | sed 's/ *$//')"
UNEXPECTED=""
for d in $DEPS; do
    case " $ALLOWED_DEPS " in *" $d "*) ;; *) UNEXPECTED="$UNEXPECTED $d" ;; esac
done
FORBIDDEN="$(printf '%s\n' $DEPS | grep -E "$FORBIDDEN_DEP_PATTERN" | tr '\n' ' ' || true)"
[ -z "$FORBIDDEN" ] || fail "FORBIDDEN dependencies: $FORBIDDEN(libstdc++ / libgcc must be static)"
if [ -n "$UNEXPECTED" ]; then
    fail "unexpected dynamic dependencies:$UNEXPECTED (allowed: $ALLOWED_DEPS)"
else
    pass "NEEDED is glibc-only, in file order: $(printf '%s ' $DEPS)(no libstdc++.so, no libgcc_s.so)"
fi
CXX_VERSIONS="$(objdump -T "$EXE" | grep -oE '(GLIBCXX|CXXABI|GCC)_[0-9.]+' | sort -u | tr '\n' ' ' || true)"
if [ -z "$CXX_VERSIONS" ]; then pass "no GLIBCXX_ / CXXABI_ / GCC_ symbol versions referenced (C++ runtime is static)"
else fail "C++ runtime symbol versions referenced: $CXX_VERSIONS"; fi

LDD_OUT="$(ldd "$EXE" 2>&1 || true)"
if printf '%s\n' "$LDD_OUT" | grep -q 'not found'; then fail "ldd: unresolved libraries"; printf '%s\n' "$LDD_OUT" | sed 's/^/         /'
else pass "ldd: every NEEDED library resolves in the image"; fi

# 6e. glibc floor - CHECKED, not merely reported.
GLIBC_VERSIONS="$(objdump -T "$EXE" | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/GLIBC_//' | sort -V -u | tr '\n' ' ' | sed 's/ *$//')"
GLIBC_FLOOR="$(printf '%s\n' $GLIBC_VERSIONS | tail -1)"
GLIBC_FLOOR="${GLIBC_FLOOR:-none}"
if [ "$GLIBC_FLOOR" = "none" ]; then
    pass "glibc floor: none referenced"
elif printf '%s\n%s\n' "$GLIBC_FLOOR" "$GLIBC_MAX" | sort -V -C; then
    pass "glibc floor: $GLIBC_FLOOR (allowed <= $GLIBC_MAX); versions referenced: $GLIBC_VERSIONS"
else
    fail "glibc floor $GLIBC_FLOOR is NEWER than the allowed $GLIBC_MAX"
fi

# 6f. No build paths in the binary.
PATH_HITS="$(strings -a "$EXE" | grep -E -e "$SCRATCH" -e "$BUILD" -e '^/work/|[^a-z]/work/' -e '/home/' || true)"
if [ -z "$PATH_HITS" ]; then
    pass "no build paths ($SCRATCH, $BUILD, /work, /home) in the binary"
else
    fail "build paths found in the binary:"; printf '%s\n' "$PATH_HITS" | first_line | sed 's/^/         /'
fi
OTHER_PATHS="$(strings -a "$EXE" | grep -E '^/(builddir|opt/rh)/' | sort -u | tr '\n' ' ' || true)"

# 6g. binaryen's configure lines.
while IFS= read -r want; do
    [ -n "$want" ] || continue
    if printf '%s\n' "$CONFIG_SUMMARY" | grep -F -x -- "$want" > /dev/null; then pass "configure: $want"
    else fail "configure did not print: $want"; fi
done <<< "$REQUIRED_CONFIGURE_LINES"
while IFS= read -r bad; do
    [ -n "$bad" ] || continue
    if printf '%s\n' "$CONFIG_SUMMARY" | grep -F -x -- "$bad" > /dev/null; then fail "configure printed: $bad"; fi
done <<< "$FORBIDDEN_CONFIGURE_LINES"
pass "configure printed none of: $(printf '%s' "$FORBIDDEN_CONFIGURE_LINES" | tr '\n' ';' | sed 's/;/; /g')"

# 6h. Functional: the stripped executable, run against the fixture (network still off).
echo "  --- functional gate (linux/functional-gate.sh, against the stripped file) ---"
if bash "$WORK/linux/functional-gate.sh" "$EXE" "$BUILD/gate-run"; then
    pass "functional gate: every check passed"
else
    fail "functional gate failed (logs: $BUILD/gate-run, copied to output/$TARGET_RID/gate-run)"
fi
} 2>&1 | tee "$GATE_LOG"
# The block above ran in a pipeline subshell; its result is read back from the log.
if grep -q '^  \[FAIL\]' "$GATE_LOG"; then FAILED=1; fi
mkdir -p "$OUT/gate-run"
cp "$BUILD"/gate-run/* "$OUT/gate-run/" 2>/dev/null || true

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "VERIFICATION FAILED for $TARGET_RID. output/$TARGET_RID is left in place for inspection,"
    echo "but this build must not be adopted into the package."
    exit 1
fi
echo

# Values the gate block computed in its subshell, recomputed for the record.
ELF_MACHINE="$(readelf -h "$EXE" | awk -F: '/Machine:/{gsub(/^ +/,"",$2); print $2}')"
ELF_TYPE="$(readelf -h "$EXE" | awk -F: '/Type:/{gsub(/^ +/,"",$2); print $2}')"
DEPS="$(readelf -d "$EXE" | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p' | tr '\n' ' ' | sed 's/ *$//')"
GLIBC_VERSIONS="$(objdump -T "$EXE" | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/GLIBC_//' | sort -V -u | tr '\n' ' ' | sed 's/ *$//')"
GLIBC_FLOOR="$(printf '%s\n' $GLIBC_VERSIONS | tail -1)"
OTHER_PATHS="$(strings -a "$EXE" | grep -E '^/(builddir|opt/rh)/' | sort -u | tr '\n' ' ' || true)"
VERSION_LINE="$("$EXE" --version | first_line)"

# ----------------------------------------------------------------------------------------------
# 7. Record.
# ----------------------------------------------------------------------------------------------
SHA="$(sha256sum "$EXE" | cut -d' ' -f1)"
ELAPSED=$(( SECONDS - START_SECONDS ))
LICENCE_NAMES="$(printf '%s\n' "$LICENCE_FILES" | cut -d: -f1 | tr '\n' ' ' | sed 's/ *$//')"
# shellcheck disable=SC2086
( cd "$OUT" && sha256sum "$EXE_NAME" $LICENCE_NAMES > SHA256SUMS.txt )

cat > "$OUT/BUILD-INFO.txt" <<EOF
wasm-opt (binaryen) - build information
==============================================================================
RID              : $TARGET_RID
Built            : $STARTED_AT
Build duration   : ${ELAPSED}s (wall clock inside the container)
Built by         : tools/binaryen-native-tools/linux/build.sh -> container-build.sh
Network          : DISABLED during this build (interfaces: ${IFACES:-none})

Build machine
------------------------------------------------------------------------------
Derived image    : ${DERIVED_IMAGE:-unknown}
Base image       : ${BASE_IMAGE_REF:-unknown}
Container OS     : $CONTAINER_OS
Machine          : $(uname -m)
Compiler         : $CXX_VERSION
Linker           : $LD_VERSION
cmake            : $CMAKE_ACTUAL (pinned $CMAKE_VERSION)
ninja            : $NINJA_ACTUAL (pinned $NINJA_VERSION)
Container glibc  : $GLIBC_ACTUAL

Source (vendored in-repo; nothing fetched at build time)
------------------------------------------------------------------------------
binaryen         : $BINARYEN_VERSION, tag $BINARYEN_TAG, commit $BINARYEN_COMMIT
Vendored at      : tools/binaryen-native-tools/binaryen/ (see ../UPSTREAM.txt)
Patches applied  : none (there is no patch step)

Configuration
------------------------------------------------------------------------------
cmake options    : -G Ninja $BINARYEN_CMAKE_OPTIONS
target           : $BUILD_TARGET only ($EDGES build steps)
C / CXX flags    : $COMPILE_FLAGS
Release flags    : $RELEASE_FLAGS (CMake's), plus binaryen's own additions
Linker flags     : $LINK_FLAGS
Compiler warnings: $WARNINGS
CMake warnings   : $CMAKE_WARNINGS
binaryen's configure summary:
$(printf '%s\n' "$CONFIG_SUMMARY" | sed 's/^/  /')

Result
------------------------------------------------------------------------------
File             : $EXE_NAME
Version          : $VERSION_LINE
Size (as linked) : $SIZE_UNSTRIPPED bytes (not kept)
Size (stripped)  : $SIZE_STRIPPED bytes  <- the shipped file
Size (gzip -9 -n): $SIZE_GZIP bytes
SHA256           : $SHA
Build-id (sha1)  : ${BUILD_ID:-none}
ELF              : ELF64, $ELF_MACHINE, $ELF_TYPE
NEEDED           : $DEPS
glibc floor      : ${GLIBC_FLOOR:-none} (allowed <= ${GLIBC_MAX:-n/a})
GLIBC versions   : $GLIBC_VERSIONS
Toolchain paths  : ${OTHER_PATHS:-none} (strings from the static libstdc++, not ours)
Licences beside it: $LICENCE_NAMES
Compiled-in third-party evidence: third-party-evidence.txt (llvm-project objects
                   linked: $LLVM_MEMBERS; objects including FP16 headers: $FP16_USERS)

Gate (GATE.txt; functional logs and outputs in gate-run/)
------------------------------------------------------------------------------
$(cat "$GATE_LOG")
EOF

echo "--- done ---"
echo "  $EXE"
echo "  sha256 $SHA"
echo "  $SIZE_STRIPPED bytes stripped, $SIZE_GZIP bytes gzip -9"
echo "  ${ELAPSED}s"
