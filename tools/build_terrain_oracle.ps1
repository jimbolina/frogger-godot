param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [switch]$Run,
      [switch]$Camera,
      [string]$ReferenceBuild = "$PSScriptRoot/../../froggy/engine/build")
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
$repo=[IO.Path]::GetFullPath("$PSScriptRoot/..")
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
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/terrain_oracle_adapter.c" @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" '-Wl,--wrap=FrogRequestAnimation' '-Wl,--wrap=MRSNDPlaySound' '-Wl,--wrap=AddFrogScore' -lws2_32 -lshell32 -lm -o "$out/terrain_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Terrain oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$objects += "$build/real_source/libfrogger_real_source.a","$build/asset_pipeline/libasset_pipeline.a"
$metadata=[ordered]@{
    adapter_source_sha256=(Get-FileHash "$PSScriptRoot/terrain_oracle_adapter.c").Hash.ToLowerInvariant()
    adapter_binary_sha256=(Get-FileHash "$out/terrain_oracle.exe").Hash.ToLowerInvariant()
    reference_build=$build
    reference_inputs=@($objects | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash $_).Hash.ToLowerInvariant()} })
    reference_sources=@($commands | Where-Object {$_.file -match '[\\/](FROG|GRID|COLLIDE|CAMERA)\.C$'} | ForEach-Object {
        [ordered]@{path=$_.file;sha256=(Get-FileHash $_.file).Hash.ToLowerInvariant();object=$_.output}
    })
    components=@('ControlFrog','MoveFrog')
    scenarios=@('normal north hop','unusable north destination','north hop with in-flight east press/hold/release')
    omitted_requests=@('FrogRequestAnimation','MRSNDPlaySound','AddFrogScore')
    seed=12345
    camera_components=@('ResetCamera','UpdateCamera','ShakeCamera')
    camera_shake_seed=1
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$out/provenance.json" -Encoding utf8
if($Run) {
    $stem=if($Camera) {'camera_'} else {''}
    $launch=@{FilePath="$out/terrain_oracle.exe";WindowStyle='Hidden';PassThru=$true;Wait=$true;RedirectStandardOutput="$out/${stem}stdout.log";RedirectStandardError="$out/${stem}stderr.log"}
    if($Camera) {$launch.ArgumentList='--camera'}
    $process=Start-Process @launch
    if($process.ExitCode -ne 0) { throw "Terrain oracle failed with exit $($process.ExitCode)." }
    $lines=Get-Content -LiteralPath "$out/${stem}stdout.log"
    $pattern=if($Camera) {'^scenario,tick,mode,'} else {'^scenario,tick,component,'}
    $header=($lines | Select-String $pattern).LineNumber
    if(-not $header) { throw 'Terrain trace header missing.' }
    $lines | Select-Object -Skip ($header-1) | Set-Content -LiteralPath "$out/${stem}trace.csv" -Encoding utf8
    Write-Output "$out/${stem}trace.csv"
}
