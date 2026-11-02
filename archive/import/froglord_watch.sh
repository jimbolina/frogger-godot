#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.." || exit 2
GODOT="${GODOT:-godot}"
if [ "$GODOT" = godot ] && ! command -v "$GODOT" >/dev/null 2>&1 && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "froglord_watch: Godot not found; set GODOT=/path/to/godot" >&2
    exit 2
fi
args=()
data_dir="${FROGGER_DATA_DIR:-}"
for argument in "$@"; do
    case "$argument" in
        --data-dir=*) data_dir="${argument#--data-dir=}" ;;
        *) args+=("$argument") ;;
    esac
done
if [ -z "$data_dir" ]; then
    echo "froglord_watch: pass --data-dir=<FrogLord folder> or set FROGGER_DATA_DIR" >&2
    exit 2
fi
if ! "$GODOT" --headless --disable-crash-handler --path . --import >/dev/null 2>&1; then
    echo "froglord_watch: class-name cache refresh failed; run godot --headless --path . --import to see why" >&2
    exit 2
fi
exec "$GODOT" --headless --disable-crash-handler --path . -s res://archive/import/froglord_watch.gd -- "--data-dir=$data_dir" ${args[@]+"${args[@]}"}
