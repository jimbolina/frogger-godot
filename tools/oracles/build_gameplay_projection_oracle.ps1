param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [switch]$Run,
      [switch]$CaptureFacts,
      [string]$ReferenceBuild = "$PSScriptRoot/../../../froggy/engine/build")
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
$repo=[IO.Path]::GetFullPath("$PSScriptRoot/../..")
$build=[IO.Path]::GetFullPath($ReferenceBuild)
$frozen=[IO.Path]::GetFullPath("$build/../..")
foreach($protected in @($repo,$frozen)) {
    if($out -eq $protected -or $out.StartsWith($protected+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside both repositories.' }
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$commands=Get-Content "$build/compile_commands.json" | ConvertFrom-Json
$entry=$commands | Where-Object {$_.file -match '[\\/]mr_grid_slice_main.c$'} | Select-Object -First 1
$compiler=($entry.command -split ' ')[0]
$env:PATH="$(Split-Path $compiler);$build/_deps/sdl2-build;$env:PATH"
$includes=[regex]::Matches($entry.command,'-I(?:"[^"]+"|[^ ]+)') | ForEach-Object {$_.Value}
$objects=Get-ChildItem "$build/mr_stub/CMakeFiles/mr_stub_common.dir" -Filter '*.obj' -Recurse | ForEach-Object {$_.FullName}
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/gameplay_projection_oracle.c" @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" -lws2_32 -lshell32 -lm -o "$out/gameplay_projection_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Projection oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$objects += "$build/real_source/libfrogger_real_source.a","$build/asset_pipeline/libasset_pipeline.a"

$metadata=[ordered]@{adapter_sha256=(Get-FileHash "$PSScriptRoot/gameplay_projection_oracle.c").Hash;binary_sha256=(Get-FileHash "$out/gameplay_projection_oracle.exe").Hash;reference_build=$build;inputs=@($objects | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash $_).Hash}})}
$metadata | ConvertTo-Json -Depth 4 | Set-Content "$out/provenance.json" -Encoding utf8
if($Run) {
    $process=Start-Process -FilePath "$out/gameplay_projection_oracle.exe" -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$out/projection.csv" -RedirectStandardError "$out/stderr.log"
    if($process.ExitCode -ne 0) {throw "Projection oracle failed: $($process.ExitCode)"}
    Write-Output "$out/projection.csv"
}

if($CaptureFacts) {
    $driverObjects=Get-ChildItem "$build/mr_stub/CMakeFiles/frog_slice.dir" -Filter '*.obj' -Recurse | ForEach-Object {$_.FullName}
    & $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/gameplay_capture_facts.c" @driverObjects @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" '-Wl,--wrap=save_screenshot' -lws2_32 -lshell32 -lm -o "$out/gameplay_reference_capture.exe"
    if($LASTEXITCODE -ne 0) {throw 'Capture facts adapter link failed.'}
    [ordered]@{adapter_sha256=(Get-FileHash "$PSScriptRoot/gameplay_capture_facts.c").Hash;binary_sha256=(Get-FileHash "$out/gameplay_reference_capture.exe").Hash;driver_objects=@($driverObjects | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash $_).Hash}})} | ConvertTo-Json -Depth 4 | Set-Content "$out/capture-provenance.json" -Encoding utf8
    Write-Output "$out/gameplay_reference_capture.exe"
}
