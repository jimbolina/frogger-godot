#!/usr/bin/env bash
# Runs every test headless with GUT and prints a PASS/FAIL/SKIP summary.
#
#   GODOT=/path/to/godot tools/run_tests.sh [extra GUT options, e.g. -gselect=test_pp20]
#
# GODOT defaults to "godot" on the PATH. Tests that need the retail game files
# read FROGGER_DATA_DIR; without it they are reported as SKIPPED by name.
#
# Exit codes:
#   0  every test ran and passed
#   1  a test failed, or a script failed to load / had a script error
#   2  setup problem (Godot not found)
#   3  nothing failed, but some tests were skipped (a skip is never a pass)
set -u
cd "$(dirname "$0")/.." || exit 2
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "run_tests: Godot not found; set GODOT=/path/to/godot" >&2
    exit 2
fi

log="$(mktemp "${TMPDIR:-/tmp}/frogger_tests.XXXXXX")"
trap 'rm -f "$log"' EXIT

# Refresh the class cache so new class_name types resolve (quick when nothing changed).
"$GODOT" --headless --path . --import >/dev/null 2>&1

# Compile every script first: tests only compile what they reach.
"$GODOT" --headless --path . -s res://tools/check_scripts.gd >"$log" 2>&1
check_rc=$?
grep -E "SCRIPT ERROR|at: GDScript|CHECK FAILED|check_scripts:" "$log"

"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd "$@" >"$log" 2>&1
rc=$?
cat "$log"
if [ "$check_rc" -ne 0 ]; then
    echo "run_tests: some scripts do not compile (see check_scripts above)" >&2
    rc=1
fi

# GUT keeps going when a script cannot be loaded; treat that as a failure.
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Could not load" "$log" >/dev/null; then
    echo "run_tests: script errors found (see above)" >&2
    [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] && rc=1
fi
if ! grep -q "^SUMMARY: " "$log"; then
    echo "run_tests: no summary line; the run did not finish" >&2
    [ "$rc" -eq 0 ] && rc=1
fi
exit "$rc"
