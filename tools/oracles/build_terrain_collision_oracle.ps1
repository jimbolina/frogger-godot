param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [switch]$Run,
      [switch]$Collision,
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
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/terrain_collision_oracle.c" @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" '-Wl,--wrap=FrogRequestAnimation' '-Wl,--wrap=MRSNDPlaySound' '-Wl,--wrap=AddFrogScore' '-Wl,--wrap=MRCreatePgen' '-Wl,--wrap=MRCreate3DSprite' '-Wl,--wrap=CreateParticleEffect' '-Wl,--wrap=GameAddObjectToViewports' '-Wl,--wrap=SetGameMainloopMode' -lws2_32 -lshell32 -lm -o "$out/terrain_collision_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Terrain oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$objects += "$build/real_source/libfrogger_real_source.a","$build/asset_pipeline/libasset_pipeline.a"
$metadata=[ordered]@{
    adapter_source_sha256=(Get-FileHash "$PSScriptRoot/terrain_collision_oracle.c").Hash.ToLowerInvariant()
    adapter_binary_sha256=(Get-FileHash "$out/terrain_collision_oracle.exe").Hash.ToLowerInvariant()
    reference_build=$build
    reference_inputs=@($objects | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash $_).Hash.ToLowerInvariant()} })
    reference_sources=@($commands | Where-Object {$_.file -match '[\\/](FROG|GRID|COLLIDE|CAMERA)\.C$'} | ForEach-Object {
        [ordered]@{path=$_.file;sha256=(Get-FileHash $_.file).Hash.ToLowerInvariant();object=$_.output}
    })
    component_routes=@('default: ControlFrog/MoveFrog','--collision: ControlFrog/MoveFrog/CollideFrog','--matrix: UpdateFrogMatrix','--special/--roll/--freeform/--startup/--wall/--slope: declared setup and MoveFrog','--steering: freeform ControlFrog/MoveFrog','--modifiers: UpdateFrogPowerUps','--bounds/--odd: JumpFrog/MoveFrog','--priority: ReactFrogWithGridFlags','--map-branches: MoveFrog/FrogKill/CollideFrog','--narrow: JumpFrog/wall/freeform MoveFrog signed32 prefixes')
    components= $(if($Collision) {@('ControlFrog','MoveFrog','CollideFrog')} else {@('ControlFrog','MoveFrog')})
    scenarios= $(if($Collision) {@('fall 512','fall 513 stun','fall 1024 stun','fall 1025 death','soft fall 1025','safe and deadly','deadly SUB','pop','water','fade precedence','empty target theme height','deadly FOR')}
        else {@('super hop','fixture quick hop','fixture auto hop','up 200','up 201 blocked','down 256 smooth','down 257 freefall','empty target freefall')})
    omitted_requests=@('FrogRequestAnimation','MRSNDPlaySound','AddFrogScore')
    factory_wrappers=@('MRCreatePgen','MRCreate3DSprite','CreateParticleEffect','GameAddObjectToViewports')
    game_mode_wrapper='SetGameMainloopMode records mode without running setup callbacks'
    rng_scope='Effect factories may consume RNG in the full engine; their omitted work is not simulated or compensated.'
    seed=12345
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$out/provenance.json" -Encoding utf8
if($Run) {
    $processOptions=@{FilePath="$out/terrain_collision_oracle.exe";WindowStyle='Hidden';PassThru=$true;Wait=$true;RedirectStandardOutput="$out/stdout.log";RedirectStandardError="$out/stderr.log"}
    if($Collision) { $processOptions.ArgumentList=@('--collision') }
    $process=Start-Process @processOptions
    if($process.ExitCode -ne 0) { throw "Terrain oracle failed with exit $($process.ExitCode)." }
    $lines=Get-Content -LiteralPath "$out/stdout.log"
    $header=($lines | Select-String '^scenario,tick,component,').LineNumber
    if(-not $header) { throw 'Terrain trace header missing.' }
    $lines | Select-Object -Skip ($header-1) | Set-Content -LiteralPath "$out/trace.csv" -Encoding utf8
    Write-Output "$out/trace.csv"
}
