#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.." || exit 2
GODOT="${GODOT:-godot}"
if [ "$GODOT" = godot ] && ! command -v "$GODOT" >/dev/null 2>&1 && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "run_tests: Godot not found; set GODOT=/path/to/godot" >&2
    exit 2
fi

if [ -d assets/fonts ]; then
    if ! "${PYTHON:-python3}" tools/make_font_newfont.py --check --quiet; then
        echo "run_tests: the committed newfont fonts differ from their generator" >&2
        exit 2
    fi
fi

if [ -d assets/fonts/angular ]; then
    UV="${UV:-uv}"
    if ! command -v "$UV" >/dev/null 2>&1 && [ ! -x "$UV" ]; then
        echo "run_tests: uv not found; install uv or set UV=/path/to/uv" >&2
        exit 2
    fi
    if ! "$UV" run --locked --quiet tools/make_angular_font.py --check --quiet; then
        echo "run_tests: the committed angular font differs from its generator" >&2
        exit 2
    fi
fi

if ! "${PYTHON:-python3}" tools/test_capture_tools.py >/dev/null 2>&1; then
    echo "run_tests: capture tool self-test failed" >&2
    exit 2
fi

if [ -d assets ]; then
    while IFS= read -r -d '' asset; do
        first_line=""
        IFS= read -r first_line <"$asset" || true
        case "$first_line" in
            "version https://git-lfs.github.com/spec"*)
                echo "run_tests: assets contain git LFS pointers; run git lfs pull" >&2
                exit 2
                ;;
        esac
    done < <(find assets -type f -size -1024c -print0)
fi

archive_requested=0
archive_data_dir=""
if [ -n "${FROGGER_DATA_DIR+x}" ]; then
    archive_requested=1
    archive_data_dir="$FROGGER_DATA_DIR"
fi
unset FROGGER_DATA_DIR FROGGER_TEST_SUITE

run_directory="$(mktemp -d "${TMPDIR:-/tmp}/frogger-tests.XXXXXX")" || exit 2
mkdir "$run_directory/appdata" "$run_directory/data" "$run_directory/config" "$run_directory/temp" || exit 2
export APPDATA="$run_directory/appdata"
export XDG_DATA_HOME="$run_directory/data"
export XDG_CONFIG_HOME="$run_directory/config"
export TMPDIR="$run_directory/temp"
export TEMP="$run_directory/temp"
export TMP="$run_directory/temp"
project_directory="$PWD"
case "$(uname -s)" in
    Darwin)
        project_directory="$("${PYTHON:-python3}" tools/godot_project.py "$PWD" "$run_directory/data")" || exit 2
        ;;
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
    "$GODOT" --headless --disable-crash-handler --path "$project_directory" --log-file "$run_directory/$stage.log" "$@" >"$run_directory/$stage.console.log" 2>&1
}

run_stage import --import
import_rc=$?
if [ "$import_rc" -ne 0 ] || [ ! -s "$run_directory/import.log" ] || grep -Eq "$script_errors" "$run_directory/import.log"; then
    cat "$run_directory/import.log" "$run_directory/import.console.log" 2>/dev/null
    echo "run_tests: import failed; see $run_directory/import.log" >&2
    exit 1
fi

run_stage check -s res://tools/check_scripts.gd
check_rc=$?
grep -E 'SCRIPT ERROR|at: GDScript|CHECK FAILED|check_scripts:' "$run_directory/check.log" 2>/dev/null
if [ "$check_rc" -ne 0 ] || grep -Eq "$script_errors" "$run_directory/check.log" || ! grep -Eq '^check_scripts: [0-9]+ scripts, 0 failed[[:space:]]*$' "$run_directory/check.log"; then
    cat "$run_directory/check.log" "$run_directory/check.console.log" 2>/dev/null
    echo "run_tests: strict compilation failed; see $run_directory/check.log" >&2
    exit 1
fi

"$GODOT" --headless --disable-crash-handler --path "$PWD" --log-file "$run_directory/refresh.log" --import >"$run_directory/refresh.console.log" 2>&1
if [ $? -ne 0 ] || [ ! -s .godot/global_script_class_cache.cfg ]; then
    echo "run_tests: checkout class-name cache refresh failed; direct launches may hit parse errors; see $run_directory/refresh.log" >&2
else
    echo "run_tests: checkout class-name cache refreshed for direct launches"
fi

run_stage architecture -s res://tools/check_architecture.gd
architecture_rc=$?
grep -E 'ARCHITECTURE|architecture_check:' "$run_directory/architecture.log" 2>/dev/null
if [ "$architecture_rc" -ne 0 ] || grep -Eq "$script_errors" "$run_directory/architecture.log" || ! grep -Eq '^architecture_check: [0-9]+ scripts, 0 failed[[:space:]]*$' "$run_directory/architecture.log"; then
    cat "$run_directory/architecture.log" "$run_directory/architecture.console.log" 2>/dev/null
    echo "run_tests: architecture check failed; see $run_directory/architecture.log" >&2
    exit 1
fi

rc=0

check_suite() {
    local suite="$1"
    shift
    run_stage "$suite" -s res://addons/gut/gut_cmdln.gd "$@"
    local tests_rc=$?
    cat "$run_directory/$suite.log" 2>/dev/null
    if grep -Eq "$script_errors" "$run_directory/$suite.log"; then
        echo "run_tests: script errors found in the $suite suite; see $run_directory/$suite.log" >&2
        rc=1
    fi
    if [ "$tests_rc" -ne 0 ]; then
        rc=1
    fi
    run_stage "$suite-results" -s res://tools/check_test_results.gd -- "$run_directory/$suite.log" "$tests_rc" "--suite=$suite"
    local results_rc=$?
    grep -E 'RESULT ERROR|test_results:' "$run_directory/$suite-results.log" 2>/dev/null
    if [ "$results_rc" -ne 0 ] || grep -Eq "$script_errors" "$run_directory/$suite-results.log" || ! grep -Eq "^test_results: valid $suite suite, exit [01][[:space:]]*\$" "$run_directory/$suite-results.log"; then
        echo "run_tests: $suite suite result validation failed; see $run_directory/$suite-results.log" >&2
        rc=1
    fi
}

check_suite game "$@"

if [ "$archive_requested" -eq 1 ]; then
    export FROGGER_DATA_DIR="$archive_data_dir"
    run_stage input -s res://tools/check_test_results.gd -- --input
    input_rc=$?
    if [ "$input_rc" -ne 0 ] || grep -Eq "$script_errors" "$run_directory/input.log" || ! grep -Eq '^test_input: valid[[:space:]]*$' "$run_directory/input.log"; then
        cat "$run_directory/input.log" "$run_directory/input.console.log" 2>/dev/null
        echo "run_tests: invalid archive input; see $run_directory/input.log" >&2
        exit 1
    fi
    export FROGGER_TEST_SUITE=archive
    check_suite archive -gconfig=res://archive/tests/.gutconfig.json
    unset FROGGER_TEST_SUITE
else
    echo "run_tests: archive suite not run (FROGGER_DATA_DIR unset)"
fi
exit "$rc"
