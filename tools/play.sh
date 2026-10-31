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
profile=""
profile_given=0
for argument in "$@"; do
    case "$argument" in
        --scene=*) scene="${argument#--scene=}" ;;
        --rendering=*)
            if [ "$profile_given" = 0 ]; then
                profile_given=1
                profile="$(printf '%s' "${argument#--rendering=}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
            fi
            args+=("$argument")
            ;;
        *) args+=("$argument") ;;
    esac
done
if [ -z "$profile" ]; then
    profile="$(awk -F= '/^\[/ { section = $0 } section == "[frogger]" && $1 == "rendering/default_profile" { gsub(/"/, "", $2); print tolower($2) }' project.godot)"
fi
engine=()
if [ "$profile" = modern ]; then
    engine+=(--rendering-method forward_plus)
fi
if [ -d assets/textures/images_x4 ] && ! "${PYTHON:-python3}" tools/bake_pages_x4.py --quiet; then
    echo "play: baking the x4 texture pages failed" >&2
    exit 1
fi
if ! "$GODOT" --headless --disable-crash-handler --path . --import >/dev/null 2>&1; then
    echo "play: class-name cache refresh failed; run godot --headless --path . --import to see why" >&2
    exit 1
fi
exec "$GODOT" --path . ${engine[@]+"${engine[@]}"} "$scene" -- ${args[@]+"${args[@]}"}
