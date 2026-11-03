#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.." || exit 2
GODOT="${GODOT:-godot}"
if [ "$GODOT" = godot ] && ! command -v "$GODOT" >/dev/null 2>&1 && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "import_assets: Godot not found; set GODOT=/path/to/godot" >&2
    exit 2
fi
data_dir="${FROGGER_DATA_DIR:-}"
disc="${FROGGER_DISC:-}"
extra=()
roots=()
for argument in "$@"; do
    case "$argument" in
        --data-dir=*) data_dir="${argument#--data-dir=}" ;;
        --disc=*) disc="${argument#--disc=}" ;;
        --assets-root=*|--fallback-root=*) roots+=("$argument") ;;
        *) extra+=("$argument") ;;
    esac
done
if [ -z "$data_dir" ]; then
    echo "import_assets: pass --data-dir=<folder> or set FROGGER_DATA_DIR" >&2
    exit 2
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/frogger-import.XXXXXX")" || exit 2
logs="$scratch/logs"
mkdir -p "$logs"
echo "import_assets: scratch and logs: $scratch"
script_errors='SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Could not load'

run_phase() {
    local phase="$1"
    shift
    "$GODOT" --headless --disable-crash-handler --path . --log-file "$logs/$phase.log" \
        -s res://archive/import/import_assets.gd -- "--data-dir=$data_dir" "--disc=$disc" \
        "--scratch=$scratch" "--phase=$phase" ${roots[@]+"${roots[@]}"} "$@" >"$logs/$phase.console.log" 2>&1
    local rc=$?
    grep -E '^import:' "$logs/$phase.log" 2>/dev/null
    if [ "$rc" -ne 0 ] || grep -Eq "$script_errors" "$logs/$phase.log"; then
        cat "$logs/$phase.log" "$logs/$phase.console.log" 2>/dev/null | tail -60
        echo "import_assets: phase $phase failed; see $logs/$phase.log" >&2
        exit 1
    fi
}

run_import() {
    local stage="$1"
    "$GODOT" --headless --disable-crash-handler --path . --log-file "$logs/$stage.log" --import >"$logs/$stage.console.log" 2>&1
    if [ $? -ne 0 ] || grep -Eq "$script_errors" "$logs/$stage.log"; then
        cat "$logs/$stage.log" "$logs/$stage.console.log" 2>/dev/null | tail -60
        echo "import_assets: Godot import ($stage) failed; see $logs/$stage.log" >&2
        exit 1
    fi
}

run_import refresh
run_phase raw ${extra[@]+"${extra[@]}"}
if [ -x archive/import/encode_music.sh ]; then
    archive/import/encode_music.sh "$scratch" ${extra[@]+"${extra[@]}"} || exit 1
fi
run_import import-raw
run_phase resources ${extra[@]+"${extra[@]}"}
run_import import-resources
echo "import_assets: done"
