#!/usr/bin/env bash
# Runs every test headless with GUT in an isolated temporary Godot profile.
#
#   GODOT=/path/to/godot tools/run_tests.sh [extra GUT options, e.g. -gselect=test_pp20]
#
# GODOT defaults to "godot" on the PATH. Set FROGGER_DATA_DIR to run retail-file
# tests. Without it they skip by name. Logs remain in the printed temp folder.
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

run_directory="$(mktemp -d "${TMPDIR:-/tmp}/frogger-tests.XXXXXX")" || exit 2
mkdir -p "$run_directory/appdata" "$run_directory/data" "$run_directory/config" "$run_directory/temp" || exit 2
export APPDATA="$run_directory/appdata"
export XDG_DATA_HOME="$run_directory/data"
export XDG_CONFIG_HOME="$run_directory/config"
export TMPDIR="$run_directory/temp"
export TEMP="$run_directory/temp"
export TMP="$run_directory/temp"
# Windows Godot needs native environment paths when launched through Git Bash.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        if command -v cygpath >/dev/null 2>&1; then
            export APPDATA="$(cygpath -w "$APPDATA")"
            export TEMP="$(cygpath -w "$TEMP")"
            export TMP="$TEMP"
        fi
        ;;
esac
echo "run_tests: logs and isolated profile: $run_directory"
script_errors='SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Could not load|CHECK FAILED'

run_stage() {
    local stage="$1"
    shift
    "$GODOT" --headless --disable-crash-handler --path . --log-file "$run_directory/$stage.log" "$@" >"$run_directory/$stage.console.log" 2>&1
}

# Refresh the class cache so new class_name types resolve (quick when nothing changed).
run_stage import --import
import_rc=$?
if [ "$import_rc" -ne 0 ] || [ ! -s "$run_directory/import.log" ] || grep -Eq "$script_errors" "$run_directory/import.log"; then
    cat "$run_directory/import.log" "$run_directory/import.console.log" 2>/dev/null
    echo "run_tests: import failed; see $run_directory/import.log" >&2
    exit 1
fi

# Compile every script first: tests only compile what they reach.
run_stage check -s res://tools/check_scripts.gd
check_rc=$?
grep -E 'SCRIPT ERROR|at: GDScript|CHECK FAILED|check_scripts:' "$run_directory/check.log" 2>/dev/null
if [ "$check_rc" -ne 0 ] || grep -Eq "$script_errors" "$run_directory/check.log" || ! grep -Eq '^check_scripts: [0-9]+ scripts, 0 failed[[:space:]]*$' "$run_directory/check.log"; then
    cat "$run_directory/check.log" "$run_directory/check.console.log" 2>/dev/null
    echo "run_tests: strict compilation failed; see $run_directory/check.log" >&2
    exit 1
fi

run_stage tests -s res://addons/gut/gut_cmdln.gd "$@"
rc=$?
cat "$run_directory/tests.log" 2>/dev/null
# GUT keeps going when a script cannot be loaded; treat that as a failure.
if grep -Eq "$script_errors" "$run_directory/tests.log"; then
    echo "run_tests: script errors found; see $run_directory/tests.log" >&2
    rc=1
fi
if ! grep -Eq '^SUMMARY: PASS=[0-9]+ FAIL=[0-9]+ SKIP=[0-9]+ EXIT=[013][[:space:]]*$' "$run_directory/tests.log"; then
    echo "run_tests: no complete summary; see $run_directory/tests.log" >&2
    rc=1
fi
exit "$rc"
