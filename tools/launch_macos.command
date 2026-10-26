#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
    echo 'Install Godot 4.5.1 in /Applications or set GODOT to its executable.' >&2
    exit 2
fi
if [ -z "${FROGGER_DATA_DIR:-}" ] && [ -f ../froggy/resources/pc-version/extracted/FROGGER/FROGGER.EXE ]; then
    export FROGGER_DATA_DIR="$(cd ../froggy/resources/pc-version/extracted/FROGGER && pwd)"
fi
if [ "$#" -eq 0 ]; then
    set -- --editor
fi
exec "$GODOT" --disable-crash-handler --path "$PWD" "$@"
