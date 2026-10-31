param(
    [string]$Scene = "res://scenes/game/gameplay.tscn",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GameArguments = @()
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$godotCommand = Get-Command $godot -CommandType Application -ErrorAction SilentlyContinue
if (-not $godotCommand) {
    Write-Output "play: Godot not found; set `$env:GODOT to the Godot executable"
    exit 2
}
$godotExecutable = $godotCommand.Source
$arguments = @($GameArguments)
$import = Start-Process -FilePath $godotExecutable -ArgumentList "--headless --disable-crash-handler --path . --import" -WorkingDirectory (Get-Location).Path -WindowStyle Hidden -Wait -PassThru
if ($import.ExitCode -ne 0) {
    Write-Output "play: class-name cache refresh failed; run godot --headless --path . --import to see why"
    exit 1
}
& $godotExecutable --path . $Scene -- @arguments
exit $LASTEXITCODE
