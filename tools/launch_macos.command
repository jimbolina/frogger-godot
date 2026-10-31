#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
    echo 'Install Godot 4.5.1 in /Applications or set GODOT to its executable.' >&2
    exit 2
fi
if [ "$#" -eq 0 ]; then
    set -- --editor
fi
profile=""
profile_given=0
for argument in "$@"; do
    case "$argument" in
        --rendering-method|--rendering-method=*) profile_given=2 ;;
        --rendering=*)
            if [ "$profile_given" = 0 ]; then
                profile_given=1
                profile="$(printf '%s' "${argument#--rendering=}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
            fi
            ;;
    esac
done
if [ "$profile_given" != 2 ] && [ -z "$profile" ]; then
    profile="$(awk -F= '/^\[/ { section = $0 } section == "[frogger]" && $1 == "rendering/default_profile" { gsub(/"/, "", $2); print tolower($2) }' project.godot)"
fi
if [ "$profile_given" != 2 ] && [ "$profile" = modern ]; then
    set -- --rendering-method forward_plus "$@"
fi
exec "$GODOT" --disable-crash-handler --path "$PWD" "$@"
