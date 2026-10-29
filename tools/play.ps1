param(
    [string]$Scene = "res://scenes/game/gameplay.tscn",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GameArguments = @()
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$arguments = @($GameArguments)
if (-not ($arguments | Where-Object { $_ -like "--data-dir=*" }) -and $env:FROGGER_DATA_DIR) {
    $arguments += "--data-dir=$($env:FROGGER_DATA_DIR)"
}
& $godot --headless --disable-crash-handler --path . --import *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Output "play: class-name cache refresh failed; run godot --headless --path . --import to see why"
    exit 1
}
& $godot --path . $Scene -- @arguments
exit $LASTEXITCODE
