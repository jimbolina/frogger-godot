param(
    [switch]$Check,
    [switch]$DownloadGodot,
    [switch]$Import
)

Set-Location (Join-Path $PSScriptRoot '..')
$godotVersion = '4.5.1-stable'
$godotRelease = "https://github.com/godotengine/godot/releases/download/$godotVersion"
$godotHome = 'build/godot'
$script:problems = 0

function Step([string]$message) { Write-Output "setup_dev: $message" }
function Problem([string]$message) {
    Write-Output "setup_dev: $message"
    $script:problems += 1
}
function Found([string]$command) {
    return [bool](Get-Command $command -ErrorAction SilentlyContinue)
}

if (-not (Found 'git')) {
    Problem 'git not found'
} else {
    git lfs version *> $null
    if ($LASTEXITCODE -ne 0) {
        Problem 'git-lfs not found; install it from https://git-lfs.com and rerun'
    } else {
        if (-not $Check) { git lfs install --local *> $null }
        $pointers = 0
        if (Test-Path content) {
            Get-ChildItem content -Recurse -File | Where-Object { $_.Length -lt 1024 } | ForEach-Object {
                $line = Get-Content $_.FullName -TotalCount 1 -ErrorAction SilentlyContinue
                if ($line -and $line.StartsWith('version https://git-lfs.github.com/spec')) { $pointers += 1 }
            }
        }
        if ($pointers -gt 0) {
            if ($Check) {
                Problem "$pointers git LFS pointers under content/; run git lfs pull"
            } else {
                Step "pulling git LFS objects ($pointers pointers under content/)"
                git lfs pull
                if ($LASTEXITCODE -ne 0) { Problem 'git lfs pull failed' }
            }
        } else {
            Step 'git LFS objects present'
        }
    }
}

$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
if (-not (Found $python)) {
    Problem 'python not found (3.9 or newer); set $env:PYTHON to its executable'
} else {
    & $python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'
    if ($LASTEXITCODE -ne 0) { Problem "$(& $python --version) is older than 3.9" }
    else { Step "$(& $python --version) at $((Get-Command $python).Source) (uv manages its own interpreter for pyproject.toml)" }
}

$uv = if ($env:UV) { $env:UV } else { 'uv' }
if (-not (Found $uv)) {
    Problem 'uv not found; install it from https://docs.astral.sh/uv/ or set $env:UV'
} elseif (-not $Check) {
    Step "syncing the Python tools' environment (uv sync --locked)"
    & $uv sync --locked --quiet
    if ($LASTEXITCODE -ne 0) { Problem 'uv sync failed' }
} else {
    Step "$(& $uv --version) found"
}

$godot = if ($env:GODOT) { $env:GODOT } else { 'godot' }
if ($godot -eq 'godot' -and -not (Found $godot)) {
    $local = Get-ChildItem $godotHome -Filter 'Godot_v*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*console*' } | Select-Object -First 1
    if ($local) { $godot = $local.FullName }
}

function Download-Godot {
    if (-not [System.Environment]::Is64BitOperatingSystem) {
        Write-Output 'setup_dev: no pinned Godot download for 32-bit Windows; install 4.5.1 and set $env:GODOT'
        return $false
    }
    $zip = "Godot_v${godotVersion}_win64.exe.zip"
    $sha = 'ab84df90ead5a888530faaabe744a27678ef7635068883900174fae37f7fc6178d033b551d88963c7dc2466580915a582bbc79aca97c19085900655761f56a27'
    New-Item -ItemType Directory -Force $godotHome | Out-Null
    New-Item -ItemType File -Force 'build/.gdignore' | Out-Null
    $target = Join-Path $godotHome $zip
    Step "downloading $zip"
    Invoke-WebRequest -Uri "$godotRelease/$zip" -OutFile $target
    $hash = (Get-FileHash $target -Algorithm SHA512).Hash.ToLower()
    if ($hash -ne $sha) {
        Write-Output "setup_dev: checksum mismatch for $zip"
        return $false
    }
    Expand-Archive -Path $target -DestinationPath $godotHome -Force
    Remove-Item $target
    $script:godot = (Resolve-Path (Join-Path $godotHome "Godot_v${godotVersion}_win64.exe")).Path
    return $true
}

if (-not (Found $godot) -and -not (Test-Path $godot)) {
    if ($DownloadGodot -and -not $Check) {
        if (-not (Download-Godot)) { Problem 'Godot download failed' }
    } else {
        Problem 'Godot not found; install 4.5.1 and set $env:GODOT, or rerun with -DownloadGodot'
    }
}
if ((Found $godot) -or (Test-Path $godot)) {
    $reported = (& $godot --version 2>$null | Select-Object -Last 1)
    if (-not $reported) { Problem "$godot did not report a version" }
    elseif ($reported -like '4.5.1.stable*') { Step "Godot $reported at $godot" }
    else { Problem "Godot $reported at $godot; the project needs 4.5.1" }
}

if (-not $Check -and $script:problems -eq 0) {
    if (Test-Path override.cfg) { Problem 'a checkout-local override.cfg is present; remove it before isolated test runs' }
    Step 'importing the project (first run takes a few minutes)'
    New-Item -ItemType Directory -Force build | Out-Null
    New-Item -ItemType File -Force 'build/.gdignore' | Out-Null
    & $godot --headless --disable-crash-handler --path . --log-file build/setup_import.log --import *> $null
    if ($LASTEXITCODE -ne 0) { Problem 'import failed; see build/setup_import.log' }
}

Write-Output ''
$retailReady = $false
if ($env:FROGGER_DATA_DIR) {
    if ((Test-Path (Join-Path $env:FROGGER_DATA_DIR 'FROGGER.EXE')) -and (Test-Path (Join-Path $env:FROGGER_DATA_DIR 'FROGPSX.MWD'))) {
        $retailReady = $true
        Step 'FROGGER_DATA_DIR holds the retail files; the archive and imported suites will run'
    } else {
        Problem "FROGGER_DATA_DIR is set but $env:FROGGER_DATA_DIR lacks FROGGER.EXE or FROGPSX.MWD"
    }
} else {
    Step 'FROGGER_DATA_DIR unset: the game suite needs no retail files; set it to import your copy and run the other suites'
}
if ($env:FROGGER_DISC -and -not (Test-Path $env:FROGGER_DISC -PathType Leaf)) {
    Problem "FROGGER_DISC is set but $env:FROGGER_DISC is not a file"
}
if ($Import) {
    $oggenc = if ($env:OGGENC) { $env:OGGENC } else { 'oggenc' }
    if (-not $retailReady) {
        Problem '-Import needs FROGGER_DATA_DIR pointing at FROGGER.EXE and FROGPSX.MWD'
    } elseif (-not (Found 'bash')) {
        Problem '-Import runs archive/import/import_assets.sh, which needs the bash that comes with Git for Windows'
    } elseif ($env:FROGGER_DISC -and -not (Found $oggenc)) {
        Problem 'FROGGER_DISC is set but oggenc is missing; install vorbis-tools or clear FROGGER_DISC to skip the music'
    } elseif (-not $Check -and $script:problems -eq 0) {
        Step 'importing your copy of the game into assets/ (takes several minutes)'
        $env:GODOT = $godot
        bash archive/import/import_assets.sh
        if ($LASTEXITCODE -ne 0) { Problem 'the retail import failed; see the log folder it printed' }
    }
}
if (Test-Path assets/catalog.tres) {
    Step 'assets/ holds an import of the game'
} else {
    Step 'assets/ is empty: the game opens its setup screen; run with -Import to play and test from source'
}
if ($script:problems -ne 0) {
    Write-Output "setup_dev: $($script:problems) problem(s); fix them and rerun"
    exit 2
}
if ($godot -ne 'godot') { Write-Output "setup_dev: `$env:GODOT = '$godot' for the tools\ wrappers" }
Step 'ready: tools\run_tests.ps1 runs the tests, tools\play.ps1 --scene=res://scenes/front_end.tscn plays'
exit 0
