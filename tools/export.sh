#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.." || exit 2
GODOT="${GODOT:-godot}"
if [ "$GODOT" = godot ] && ! command -v "$GODOT" >/dev/null 2>&1 && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "export: Godot not found; set GODOT=/path/to/godot" >&2
    exit 2
fi

presets=("$@")
if [ ${#presets[@]} -eq 0 ]; then
    presets=(macOS Windows Linux)
fi
version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)"
version="${version:-0.0.0}"

mkdir -p build || exit 2
touch build/.gdignore
logs="build/logs"
mkdir -p "$logs" || exit 2

if ! "$GODOT" --headless --path . --import >"$logs/import.log" 2>&1; then
    echo "export: the import failed; see $logs/import.log" >&2
    exit 1
fi

zip_folder() {
    local folder="$1" archive="$2"
    rm -f "$archive"
    if [ "$(uname -s)" = Darwin ]; then
        ditto -c -k --sequesterRsrc --keepParent "$folder" "$archive"
    else
        (cd "$(dirname "$folder")" && zip -q -r -y "$(basename "$archive")" "$(basename "$folder")") &&
            mv "$(dirname "$folder")/$(basename "$archive")" "$archive"
    fi
}

rc=0
for preset in "${presets[@]}"; do
    case "$preset" in
        macOS) folder="build/macos"; target="$folder/Frogger.app"; name="macos" ;;
        Windows) folder="build/windows"; target="$folder/Frogger.exe"; name="windows-x86_64" ;;
        Linux) folder="build/linux"; target="$folder/Frogger.x86_64"; name="linux-x86_64" ;;
        *) echo "export: unknown preset $preset (macOS, Windows or Linux)" >&2; rc=1; continue ;;
    esac
    rm -rf "$folder"
    mkdir -p "$folder"
    log="$logs/$name.log"
    "$GODOT" --headless --path . --export-release "$preset" "$target" >"$log" 2>&1
    export_rc=$?
    if [ "$export_rc" -ne 0 ] || [ ! -e "$target" ] || grep -Eq 'SCRIPT ERROR|Cannot export|export for preset .* failed' "$log"; then
        echo "export: $preset failed (exit $export_rc); see $log" >&2
        rc=1
        continue
    fi
    leaked="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -o 'Storing File: res://[^ ]*' | sed 's/^Storing File: //' |
        grep -E '^res://(assets/|\.godot/imported/)' |
        grep -vE '^res://(assets/fonts/angular/frogger_angular\.ttf\.import|assets/rendering/emissive_images\.tres\.remap|\.godot/imported/(frogger_angular\.ttf|frogger_icon\.(png|svg))-[0-9a-f]+\.[a-z]+)$')"
    if [ -n "$leaked" ]; then
        rm -rf "$folder"
        echo "export: $preset would ship files outside the shippable assets:" >&2
        echo "$leaked" >&2
        rc=1
        continue
    fi
    if [ "$preset" = Linux ]; then
        cp icon/frogger_icon.png "$folder/frogger.png"
        cat >"$folder/frogger.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Frogger
Comment=Frogger (1997) in Godot
Exec=sh -c 'cd "$(dirname "$1")" && exec ./Frogger.x86_64' sh %k
Icon=frogger
Terminal=false
Categories=Game;ArcadeGame;
EOF
        chmod +x "$folder/frogger.desktop" "$target"
    fi
    archive="build/Frogger-$version-$name.zip"
    if [ "$preset" = macOS ]; then
        zip_folder "$target" "$archive"
    else
        staged="build/Frogger-$version-$name"
        rm -rf "$staged"
        cp -R "$folder" "$staged"
        zip_folder "$staged" "$archive"
        rm -rf "$staged"
    fi
    echo "export: $preset -> $target, $archive"
done
exit "$rc"
