#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.." || exit 2

GODOT_VERSION=4.5.1-stable
GODOT_RELEASE="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION"
GODOT_HOME="build/godot"

download=0
check_only=0
for argument in "$@"; do
    case "$argument" in
        --download-godot) download=1 ;;
        --check) check_only=1 ;;
        -h|--help)
            cat <<'USAGE'
usage: tools/setup_dev.sh [--check] [--download-godot]

Prepares a checkout for development: git LFS objects, the Python tools'
environment, a Godot 4.5.1 editor and the project's first import.

  --check           report what is missing without changing anything
  --download-godot  fetch the pinned editor into build/godot/ when none is found

Set GODOT to a Godot 4.5.1 executable to use an existing install. Set
FROGGER_DATA_DIR to the retail game folder to also run the archive suite.
USAGE
            exit 0
            ;;
        *) echo "setup_dev: unknown argument $argument" >&2; exit 2 ;;
    esac
done

problems=0
problem() {
    echo "setup_dev: $1" >&2
    problems=$((problems + 1))
}
step() {
    echo "setup_dev: $1"
}

if ! command -v git >/dev/null 2>&1; then
    problem "git not found"
elif ! git lfs version >/dev/null 2>&1; then
    problem "git-lfs not found; install it from https://git-lfs.com and rerun"
else
    if [ "$check_only" -eq 0 ]; then
        git lfs install --local >/dev/null || problem "git lfs install failed"
    fi
    pointers=0
    while IFS= read -r -d '' asset; do
        first_line=""
        IFS= read -r first_line <"$asset" || true
        case "$first_line" in
            "version https://git-lfs.github.com/spec"*) pointers=$((pointers + 1)) ;;
        esac
    done < <(find assets -type f -size -1024c -print0 2>/dev/null)
    if [ "$pointers" -gt 0 ]; then
        if [ "$check_only" -eq 1 ]; then
            problem "$pointers git LFS pointers under assets/; run git lfs pull"
        else
            step "pulling git LFS objects ($pointers pointers under assets/)"
            git lfs pull || problem "git lfs pull failed"
        fi
    else
        step "git LFS objects present"
    fi
fi

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
    problem "python3 not found (3.9 or newer); set PYTHON=/path/to/python3"
elif ! "$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'; then
    problem "$("$PYTHON" --version 2>&1) is older than 3.9"
else
    step "$("$PYTHON" --version 2>&1) at $(command -v "$PYTHON") (uv manages its own interpreter for pyproject.toml)"
fi

UV="${UV:-uv}"
if ! command -v "$UV" >/dev/null 2>&1 && [ ! -x "$UV" ]; then
    problem "uv not found; install it from https://docs.astral.sh/uv/ or set UV=/path/to/uv"
elif [ "$check_only" -eq 0 ]; then
    step "syncing the Python tools' environment (uv sync --locked)"
    "$UV" sync --locked --quiet || problem "uv sync failed"
else
    step "uv $("$UV" --version 2>&1 | awk '{print $2}') found"
fi

GODOT="${GODOT:-godot}"
if [ "$GODOT" = godot ] && ! command -v "$GODOT" >/dev/null 2>&1; then
    if [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
        GODOT=/Applications/Godot.app/Contents/MacOS/Godot
    elif [ -x "$GODOT_HOME/Godot.app/Contents/MacOS/Godot" ]; then
        GODOT="$GODOT_HOME/Godot.app/Contents/MacOS/Godot"
    else
        for candidate in "$GODOT_HOME"/Godot_v*; do
            [ -x "$candidate" ] && GODOT="$candidate"
        done
    fi
fi

download_godot() {
    local zip sha
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64)
            zip="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
            sha=5bccbed65a94b82c7c319fdb15719ee8113a6e503976cc54e16f1c61fe95f3d74e5e40b8449b5bb89ff7f424574c20af01a4f5ef08b389e4dc338b245185b0b9
            ;;
        Linux-aarch64|Linux-arm64)
            zip="Godot_v${GODOT_VERSION}_linux.arm64.zip"
            sha=9d55e9cdccaa4b6528d0b39824d51c47987667babffbab7f83b05fba2ece842a59752b84128332421c9d261fe06846b88480f3b0171af255ea99383d3bc96b2c
            ;;
        Darwin-*)
            zip="Godot_v${GODOT_VERSION}_macos.universal.zip"
            sha=a91a7c3bb2faefafef41624fbd75705b91aec509823d41db595a38b79819e0f2e9c85eecdc7429c3159d8070604a3f4b4425aaa6094d7bcac147f52c89181ce9
            ;;
        MINGW*|MSYS*|CYGWIN*)
            zip="Godot_v${GODOT_VERSION}_win64.exe.zip"
            sha=ab84df90ead5a888530faaabe744a27678ef7635068883900174fae37f7fc6178d033b551d88963c7dc2466580915a582bbc79aca97c19085900655761f56a27
            ;;
        *)
            echo "setup_dev: no pinned Godot download for $(uname -s) $(uname -m); install 4.5.1 and set GODOT" >&2
            return 1
            ;;
    esac
    mkdir -p "$GODOT_HOME" || return 1
    touch build/.gdignore
    step "downloading $zip"
    curl -fsSL -o "$GODOT_HOME/$zip" "$GODOT_RELEASE/$zip" || return 1
    if command -v shasum >/dev/null 2>&1; then
        echo "$sha  $GODOT_HOME/$zip" | shasum -a 512 -c - >/dev/null || return 1
    elif command -v sha512sum >/dev/null 2>&1; then
        echo "$sha  $GODOT_HOME/$zip" | sha512sum -c - >/dev/null || return 1
    else
        echo "setup_dev: neither shasum nor sha512sum found to verify the download" >&2
        return 1
    fi
    unzip -q -o "$GODOT_HOME/$zip" -d "$GODOT_HOME" || return 1
    rm -f "$GODOT_HOME/$zip"
    case "$zip" in
        *macos*) GODOT="$GODOT_HOME/Godot.app/Contents/MacOS/Godot" ;;
        *) GODOT="$GODOT_HOME/${zip%.zip}" ;;
    esac
    chmod +x "$GODOT"
}

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    if [ "$download" -eq 1 ] && [ "$check_only" -eq 0 ]; then
        download_godot || problem "Godot download failed"
    else
        problem "Godot not found; install 4.5.1 and set GODOT=/path/to/godot, or rerun with --download-godot"
    fi
fi
if command -v "$GODOT" >/dev/null 2>&1 || [ -x "$GODOT" ]; then
    reported="$("$GODOT" --version 2>/dev/null | tail -n 1)"
    case "$reported" in
        4.5.1.stable*) step "Godot $reported at $GODOT" ;;
        "") problem "$GODOT did not report a version" ;;
        *) problem "Godot $reported at $GODOT; the project needs 4.5.1" ;;
    esac
fi

if [ "$check_only" -eq 0 ] && [ "$problems" -eq 0 ]; then
    if [ -e override.cfg ]; then
        problem "a checkout-local override.cfg is present; remove it before isolated test runs"
    fi
    step "importing the project (first run takes a few minutes)"
    mkdir -p build && touch build/.gdignore
    if ! "$GODOT" --headless --disable-crash-handler --path . --log-file build/setup_import.log --import >/dev/null 2>&1; then
        problem "import failed; see build/setup_import.log"
    fi
fi

echo
if [ -n "${FROGGER_DATA_DIR:-}" ]; then
    if [ -f "$FROGGER_DATA_DIR/FROGGER.EXE" ] && [ -f "$FROGGER_DATA_DIR/FROGPSX.MWD" ]; then
        step "FROGGER_DATA_DIR holds the retail files; the archive suite will run"
    else
        problem "FROGGER_DATA_DIR is set but $FROGGER_DATA_DIR lacks FROGGER.EXE or FROGPSX.MWD"
    fi
else
    step "FROGGER_DATA_DIR unset: the game and its suite need no retail files; set it to run the archive suite"
fi
if [ "$problems" -ne 0 ]; then
    echo "setup_dev: $problems problem(s); fix them and rerun" >&2
    exit 2
fi
case "$GODOT" in
    godot) ;;
    *) echo "setup_dev: export GODOT=\"$GODOT\" for the tools/ wrappers" ;;
esac
step "ready: tools/run_tests.sh runs the tests, tools/play.sh --scene=res://scenes/front_end.tscn plays"
exit 0
