# Runs every test headless with GUT (Windows PowerShell wrapper; same exit codes as run_tests.sh).
#
#   $env:GODOT = "C:\path\to\Godot.exe"; .\tools\run_tests.ps1 [extra GUT options]
#
# Exit codes: 0 all passed; 1 a failure or a script that does not compile;
# 2 Godot not found; 3 nothing failed but some tests were skipped.
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
if (-not (Get-Command $godot -ErrorAction SilentlyContinue)) {
    Write-Error "run_tests: Godot not found; set `$env:GODOT to the Godot executable"
    exit 2
}
Set-Location (Join-Path $PSScriptRoot "..")

& $godot --headless --path . --import *> $null

$check = & $godot --headless --path . -s res://tools/check_scripts.gd 2>&1 | Out-String
$checkRc = $LASTEXITCODE
$check -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|at: GDScript|CHECK FAILED|check_scripts:" }

$out = & $godot --headless --path . -s res://addons/gut/gut_cmdln.gd @args 2>&1 | Out-String
$rc = $LASTEXITCODE
Write-Output $out
if ($checkRc -ne 0) { $rc = 1 }
if ($out -match "SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Could not load") {
    if ($rc -eq 0 -or $rc -eq 3) { $rc = 1 }
}
if ($out -notmatch "(?m)^SUMMARY: ") { if ($rc -eq 0) { $rc = 1 } }
exit $rc
