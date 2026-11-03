param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Presets = @()
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$godotCommand = Get-Command $godot -CommandType Application -ErrorAction SilentlyContinue
if (-not $godotCommand) {
    Write-Output "export: Godot not found; set `$env:GODOT to the Godot executable"
    exit 2
}
$godotExecutable = $godotCommand.Source
if ($Presets.Count -eq 0) {
    $Presets = @("macOS", "Windows", "Linux")
}
$versionLine = Select-String -Path project.godot -Pattern '^config/version="(.*)"$' | Select-Object -First 1
$version = if ($versionLine) { $versionLine.Matches[0].Groups[1].Value } else { "0.0.0" }
$logs = "build/logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
New-Item -ItemType File -Force -Path "build/.gdignore" | Out-Null

$import = Start-Process -FilePath $godotExecutable -ArgumentList "--headless --path . --import" -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput "$logs/import.log" -RedirectStandardError "$logs/import.err.log"
if ($import.ExitCode -ne 0) {
    Write-Output "export: the import failed; see $logs/import.log"
    exit 1
}

$targets = @{
    "macOS" = @("build/macos", "build/macos/Frogger.zip", "macos")
    "Windows" = @("build/windows", "build/windows/Frogger.exe", "windows-x86_64")
    "Linux" = @("build/linux", "build/linux/Frogger.x86_64", "linux-x86_64")
}
$allowed = '^res://(assets/fonts/angular/frogger_angular\.ttf\.import|assets/rendering/emissive_images\.tres\.remap|\.godot/imported/(frogger_angular\.ttf|frogger_icon\.(png|svg))-[0-9a-f]+\.[a-z]+)$'
$rc = 0
foreach ($preset in $Presets) {
    if (-not $targets.ContainsKey($preset)) {
        Write-Output "export: unknown preset $preset (macOS, Windows or Linux)"
        $rc = 1
        continue
    }
    $folder, $target, $name = $targets[$preset]
    if (Test-Path $folder) { Remove-Item -Recurse -Force $folder }
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $log = "$logs/$name.log"
    $run = Start-Process -FilePath $godotExecutable -ArgumentList "--headless --path . --export-release `"$preset`" `"$target`"" `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$logs/$name.err.log"
    $text = (Get-Content -Raw $log) + (Get-Content -Raw "$logs/$name.err.log")
    if ($run.ExitCode -ne 0 -or -not (Test-Path $target) -or $text -match 'SCRIPT ERROR|Cannot export|export for preset .* failed') {
        Write-Output "export: $preset failed (exit $($run.ExitCode)); see $log"
        $rc = 1
        continue
    }
    $plain = $text -replace "`e\[[0-9;]*m", ""
    $leaked = [regex]::Matches($plain, 'Storing File: (res://\S+)') | ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -match '^res://(assets/|\.godot/imported/)' -and $_ -notmatch $allowed }
    if ($leaked) {
        Remove-Item -Recurse -Force $folder
        Write-Output "export: $preset would ship files outside the shippable assets:"
        $leaked | ForEach-Object { Write-Output $_ }
        $rc = 1
        continue
    }
    if ($preset -eq "Linux") {
        Copy-Item icon/frogger_icon.png "$folder/frogger.png"
        $entry = @(
            "[Desktop Entry]", "Type=Application", "Version=1.0", "Name=Frogger", "Comment=Frogger (1997) in Godot",
            "Exec=sh -c 'cd `"`$(dirname `"`$1`")`" && exec ./Frogger.x86_64' sh %k",
            "Icon=frogger", "Terminal=false", "Categories=Game;ArcadeGame;"
        ) -join "`n"
        [System.IO.File]::WriteAllText((Join-Path (Get-Location) "$folder/frogger.desktop"), $entry + "`n")
    }
    $archive = "build/Frogger-$version-$name.zip"
    if (Test-Path $archive) { Remove-Item -Force $archive }
    if ($preset -eq "macOS") {
        Copy-Item $target $archive
    } else {
        Compress-Archive -Path "$folder/*" -DestinationPath $archive
    }
    Write-Output "export: $preset -> $target, $archive"
}
exit $rc
