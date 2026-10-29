#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.." || exit 2
GODOT="${GODOT:-godot}"
if [ "$GODOT" = godot ] && ! command -v "$GODOT" >/dev/null 2>&1 && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "play: Godot not found; set GODOT=/path/to/godot" >&2
    exit 2
fi
scene="res://scenes/game/gameplay.tscn"
args=()
data_given=0
for argument in "$@"; do
    case "$argument" in
        --scene=*) scene="${argument#--scene=}" ;;
        --data-dir=*) data_given=1; args+=("$argument") ;;
        *) args+=("$argument") ;;
    esac
done
if [ "$data_given" -eq 0 ] && [ -n "${FROGGER_DATA_DIR:-}" ]; then
    args+=("--data-dir=$FROGGER_DATA_DIR")
fi
if ! "$GODOT" --headless --disable-crash-handler --path . --import >/dev/null 2>&1; then
    echo "play: class-name cache refresh failed; run godot --headless --path . --import to see why" >&2
    exit 1
fi
exec "$GODOT" --path . "$scene" -- "${args[@]}"
