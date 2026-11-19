#!/usr/bin/env bash
# ==============================================================================================
# functional-gate.sh - RUN a wasm-opt executable against gate-fixture.wat and check the results
# ==============================================================================================
#
#   functional-gate.sh <path to wasm-opt> <empty scratch folder for the outputs>
#
# The functional half of the gate, shared by every platform that has bash: container-build.sh
# runs it inside the build container (network off) on the freshly stripped executable, build.sh
# runs it once more on the HOST for a RID the host can execute, and ../macos/build.sh runs it on
# the Mac. (The Windows script performs the same checks in PowerShell.) Every flag set and every
# expected value comes from pins.env beside this file, so the platforms cannot drift apart.
#
# Written for bash 3.2 as well (macOS's /bin/bash): no associative arrays, no mapfile.
#
# Checks, each printed as [ok] or [FAIL]:
#    1. `wasm-opt --version` is exactly "wasm-opt version <BINARYEN_VERSION>"
#    2. -O0 and -Oz both produce a module that starts with the wasm magic and version
#       (00 61 73 6d 01 00 00 00)
#    3. the -Oz output is no larger than the -O0 output
#    4. the consumer's release set   (CONSUMER_FEATURES + CONSUMER_RELEASE_FLAGS) is accepted,
#       with --fuzz-exec: every export of the fixture runs in wasm-opt's interpreter before and
#       after optimising, the results must match each other and EXPECTED_RESULTS
#    5. the consumer's debug set     (CONSUMER_FEATURES + CONSUMER_DEBUG_FLAGS), likewise
#    6. the consumer's packing set   (CONSUMER_FEATURES + CONSUMER_PACKING_FLAGS), likewise
#    7. the --debuginfo output is larger than the --strip-debug output (it kept the name
#       section; the strip really stripped)
#    8. each of the three outputs, READ BACK by wasm-opt and executed again with --fuzz-exec,
#       still gives EXPECTED_RESULTS - the bytes written are a working module
#
# Exit status: 0 when every check passed, 1 otherwise. Nothing is downloaded or installed.
# ==============================================================================================

set -uo pipefail

WASM_OPT="${1:-}"
OUTDIR="${2:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$HERE/gate-fixture.wat"

[ -n "$WASM_OPT" ] && [ -n "$OUTDIR" ] || { echo "usage: $0 <wasm-opt> <output folder>" >&2; exit 2; }
[ -x "$WASM_OPT" ] || { echo "ERROR: $WASM_OPT is not an executable file" >&2; exit 2; }
[ -f "$FIXTURE" ] || { echo "ERROR: $FIXTURE is missing; it is part of the repository" >&2; exit 2; }
# shellcheck source=pins.env
. "$HERE/pins.env"
mkdir -p "$OUTDIR"

FAILED=0
fail() { echo "  [FAIL] $1"; FAILED=1; }
pass() { echo "  [ok] $1"; }
size_of() { wc -c < "$1" | tr -d ' '; }
magic_of() { od -An -tx1 -N8 "$1" | tr -d ' \n'; }
WASM_MAGIC=0061736d01000000

# Every expected "export => value" line must appear in the given --fuzz-exec log.
check_results() {
    local log="$1" missing="" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -F -x -- "[fuzz-exec] note result: $line" "$log" > /dev/null || missing="$missing
           $line"
    done <<< "$EXPECTED_RESULTS"
    if grep -F -- "[fuzz-exec] optimization passes changed results" "$log" > /dev/null; then
        missing="$missing
           (wasm-opt reported: optimization passes changed results)"
    fi
    printf '%s' "$missing"
}
EXPECTED_COUNT="$(printf '%s\n' "$EXPECTED_RESULTS" | grep -c .)"

# --- 1. version ------------------------------------------------------------------------------
VERSION_LINE="$("$WASM_OPT" --version 2>&1 | sed -n 1p)"
if [ "$VERSION_LINE" = "wasm-opt version $BINARYEN_VERSION" ]; then
    pass "--version: $VERSION_LINE"
else
    fail "--version said '$VERSION_LINE', expected 'wasm-opt version $BINARYEN_VERSION'"
fi

# --- 2./3. -O0 and -Oz -----------------------------------------------------------------------
# shellcheck disable=SC2086
"$WASM_OPT" "$FIXTURE" $CONSUMER_FEATURES -O0 -o "$OUTDIR/fixture-O0.wasm" > "$OUTDIR/O0.log" 2>&1
RC_O0=$?
# shellcheck disable=SC2086
"$WASM_OPT" "$FIXTURE" $CONSUMER_FEATURES -Oz -o "$OUTDIR/fixture-Oz.wasm" > "$OUTDIR/Oz.log" 2>&1
RC_OZ=$?
for v in O0 Oz; do
    f="$OUTDIR/fixture-$v.wasm"
    if [ -f "$f" ] && [ "$(magic_of "$f")" = "$WASM_MAGIC" ]; then
        pass "-$v: wasm magic + version 1 ($(size_of "$f") bytes)"
    else
        fail "-$v: no valid wasm output (exit $( [ $v = O0 ] && echo $RC_O0 || echo $RC_OZ ); see $v.log)"
        sed 's/^/           /' "$OUTDIR/$v.log"
    fi
done
if [ -f "$OUTDIR/fixture-O0.wasm" ] && [ -f "$OUTDIR/fixture-Oz.wasm" ]; then
    S0="$(size_of "$OUTDIR/fixture-O0.wasm")"; SZ="$(size_of "$OUTDIR/fixture-Oz.wasm")"
    if [ "$SZ" -le "$S0" ]; then pass "-Oz output ($SZ bytes) is no larger than -O0 output ($S0 bytes)"
    else fail "-Oz output ($SZ bytes) is LARGER than -O0 output ($S0 bytes)"; fi
fi

# --- 4./5./6. the consumer's three flag sets, with --fuzz-exec ----------------------------------
run_set() {
    local name="$1" flags="$2" out="$OUTDIR/fixture-$1.wasm" log="$OUTDIR/$1.log" rc missing
    # shellcheck disable=SC2086
    "$WASM_OPT" "$FIXTURE" $CONSUMER_FEATURES $flags --fuzz-exec -o "$out" > "$log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ] || [ ! -f "$out" ] || [ "$(magic_of "$out")" != "$WASM_MAGIC" ]; then
        fail "$name set rejected or produced no valid wasm (exit $rc): $CONSUMER_FEATURES $flags"
        sed 's/^/           /' "$log"
        return
    fi
    missing="$(check_results "$log")"
    if [ -n "$missing" ]; then
        fail "$name set: --fuzz-exec results wrong or missing:$missing"
    else
        pass "$name set accepted ($(size_of "$out") bytes), --fuzz-exec $EXPECTED_COUNT/$EXPECTED_COUNT results before = after = expected: $flags"
    fi
}
run_set release "$CONSUMER_RELEASE_FLAGS"
run_set debug   "$CONSUMER_DEBUG_FLAGS"
run_set packing "$CONSUMER_PACKING_FLAGS"

# --- 7. --debuginfo kept names, --strip-debug dropped them ----------------------------------------
if [ -f "$OUTDIR/fixture-release.wasm" ] && [ -f "$OUTDIR/fixture-debug.wasm" ]; then
    SR="$(size_of "$OUTDIR/fixture-release.wasm")"; SD="$(size_of "$OUTDIR/fixture-debug.wasm")"
    if [ "$SD" -gt "$SR" ]; then pass "--debuginfo output ($SD bytes) is larger than --strip-debug output ($SR bytes): name section kept / stripped"
    else fail "--debuginfo output ($SD bytes) is not larger than --strip-debug output ($SR bytes)"; fi
fi

# --- 8. read the outputs back and run them again ---------------------------------------------------
for name in release debug packing; do
    f="$OUTDIR/fixture-$name.wasm"
    [ -f "$f" ] || continue
    # shellcheck disable=SC2086
    "$WASM_OPT" "$f" $CONSUMER_FEATURES --fuzz-exec -o "$OUTDIR/readback-$name.wasm" > "$OUTDIR/readback-$name.log" 2>&1
    rc=$?
    missing="$(check_results "$OUTDIR/readback-$name.log")"
    if [ "$rc" -eq 0 ] && [ -z "$missing" ]; then
        pass "fixture-$name.wasm read back and re-run: $EXPECTED_COUNT/$EXPECTED_COUNT expected results"
    else
        fail "fixture-$name.wasm read back (exit $rc):$missing"
        sed 's/^/           /' "$OUTDIR/readback-$name.log"
    fi
done

exit "$FAILED"
