param([Parameter(Mandatory=$true)][string]$OutputDirectory,
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
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/integrated_terrain_oracle.c" @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" '-Wl,--wrap=MRSNDPlaySound' '-Wl,--wrap=AddFrogScore' '-Wl,--wrap=MRCreatePgen' '-Wl,--wrap=MRCreate3DSprite' '-Wl,--wrap=CreateParticleEffect' '-Wl,--wrap=GameAddObjectToViewports' '-Wl,--wrap=SetGameMainloopMode' -lws2_32 -lshell32 -lm -o "$out/integrated_terrain_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Terrain oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$objects += "$build/real_source/libfrogger_real_source.a","$build/asset_pipeline/libasset_pipeline.a"
$metadata=[ordered]@{
    adapter_source_sha256=(Get-FileHash "$PSScriptRoot/integrated_terrain_oracle.c").Hash.ToLowerInvariant()
    adapter_binary_sha256=(Get-FileHash "$out/integrated_terrain_oracle.exe").Hash.ToLowerInvariant()
    reference_build=$build
    reference_inputs=@($objects | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash $_).Hash.ToLowerInvariant()} })
    reference_sources=@($commands | Where-Object {$_.file -match '[\\/](FROG|GRID|COLLIDE|CAMERA|froganim|MR_ANIM)\.[cC]$'} | ForEach-Object {
        [ordered]@{path=$_.file;sha256=(Get-FileHash $_.file).Hash.ToLowerInvariant();object=$_.output}
    })
    components=@('ControlFrog','MoveFrog','CollideFrog','UpdateCamera','UpdateFrogAnimationScripts','MRAnimUpdateEnvironments')
    scenarios=@('direction arbitration','camera twist wait','fall 513 stun and idle','water deferred death')
    omitted_requests=@('MRSNDPlaySound','AddFrogScore')
    phases=@('ControlFrog','MoveFrog','CollideFrog','UpdateCamera','UpdateFrogAnimationScripts','MRAnimUpdateEnvironments')
    pose_omission='MR_ANIM_ENV_UPDATE temporarily cleared and restored, omitting renderer transform construction'
    factory_wrappers=@('MRCreatePgen','MRCreate3DSprite','CreateParticleEffect','GameAddObjectToViewports')
    game_mode_wrapper='SetGameMainloopMode records mode without running setup callbacks'
    rng_scope='Effect factories may consume RNG in the full engine; their omitted work is not simulated or compensated.'
    seed=12345
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$out/provenance.json" -Encoding utf8
