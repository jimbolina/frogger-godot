#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.." || exit 2
scratch="${1:-}"
if [ -z "$scratch" ] || [ ! -d "$scratch" ]; then
    echo "encode_music: pass the scratch folder holding track_NN.wav" >&2
    exit 2
fi
shift
force=0
for argument in "$@"; do
    [ "$argument" = --force-music ] && force=1
done
oggenc="${OGGENC:-oggenc}"
if ! command -v "$oggenc" >/dev/null 2>&1 && [ -x /opt/homebrew/bin/oggenc ]; then
    oggenc=/opt/homebrew/bin/oggenc
fi
shopt -s nullglob
wavs=("$scratch"/track_[0-9][0-9].wav)
[ "${#wavs[@]}" -eq 0 ] && exit 0
if ! command -v "$oggenc" >/dev/null 2>&1 && [ ! -x "$oggenc" ]; then
    echo "encode_music: oggenc not found; install vorbis-tools or set OGGENC" >&2
    exit 1
fi
mkdir -p assets/audio/music || exit 1
jobs_max="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

encode() {
    local wav="$1" name track ogg part
    name="$(basename "$wav" .wav)"
    track=$((10#${name#track_}))
    ogg="assets/audio/music/$name.ogg"
    part="$scratch/$name.ogg"
    if ! "$oggenc" --quiet -q 6 --serial "$track" -o "$part" "$wav"; then
        rm -f "$part"
        echo "encode_music: oggenc failed on $wav" >&2
        return 1
    fi
    if [ -e "$ogg" ] && cmp -s "$part" "$ogg"; then
        rm -f "$part"
    else
        mv -f "$part" "$ogg"
    fi
}

export -f encode
export oggenc scratch
started=$SECONDS
pending=()
for wav in "${wavs[@]}"; do
    name="$(basename "$wav" .wav)"
    if [ -e "assets/audio/music/$name.ogg" ] && [ "$force" -eq 0 ]; then
        continue
    fi
    pending+=("$wav")
done
[ "${#pending[@]}" -eq 0 ] && exit 0
printf '%s\0' "${pending[@]}" | xargs -0 -n 1 -P "$jobs_max" bash -c 'encode "$1"' encode || exit 1
echo "import: music encoded ${#pending[@]} tracks, $((SECONDS - started)) s"
