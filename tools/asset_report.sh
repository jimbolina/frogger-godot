#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.." || exit 2
GODOT="${GODOT:-godot}"
if [ "$GODOT" = godot ] && ! command -v "$GODOT" >/dev/null 2>&1 && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "asset_report: Godot not found; set GODOT=/path/to/godot" >&2
    exit 2
fi
if ! "$GODOT" --headless --disable-crash-handler --path . --import >/dev/null 2>&1; then
    echo "asset_report: class-name cache refresh failed; run godot --headless --path . --import to see why" >&2
    exit 2
fi
"$GODOT" --headless --disable-crash-handler --path . -s res://tools/asset_report.gd -- "$@"
exit $?
