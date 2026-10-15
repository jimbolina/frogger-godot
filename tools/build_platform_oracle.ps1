param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [string]$ReferenceBuild = "$PSScriptRoot/../../froggy/engine/build")
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
$repo=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$build=[IO.Path]::GetFullPath($ReferenceBuild)
$frozen=[IO.Path]::GetFullPath("$build/../..")
$acos=[IO.Path]::GetFullPath("$frozen/engine/vendor/frogger-psx-src/source/API.BIN/acos_le.dat")
if(-not (Test-Path -LiteralPath $acos)) { throw "Frozen acos table missing: $acos" }
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
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/platform_oracle.c" @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" '-Wl,--wrap=MRSNDPlaySound' '-Wl,--wrap=AddFrogScore' '-Wl,--wrap=MRCreatePgen' '-Wl,--wrap=MRCreate3DSprite' '-Wl,--wrap=CreateParticleEffect' '-Wl,--wrap=GameAddObjectToViewports' '-Wl,--wrap=SetGameMainloopMode' '-Wl,--wrap=ENTSTRCreateMovingMOF' '-Wl,--wrap=ENTSTRCreateDynamicMOF' '-Wl,--wrap=ENTSTRCreateStationaryMOF' '-Wl,--wrap=PlayMovingSound' -lws2_32 -lshell32 -lm -o "$out/platform_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Platform oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$objects += "$build/real_source/libfrogger_real_source.a","$build/asset_pipeline/libasset_pipeline.a"
$metadata=[ordered]@{
    adapter_source_sha256=(Get-FileHash "$PSScriptRoot/platform_oracle.c").Hash.ToLowerInvariant()
    org1_adapter_source_sha256=(Get-FileHash "$PSScriptRoot/org1_route_oracle.h").Hash.ToLowerInvariant()
    entity_script_adapter_source_sha256=(Get-FileHash "$PSScriptRoot/entity_script_oracle.h").Hash.ToLowerInvariant()
    adapter_binary_sha256=(Get-FileHash "$out/platform_oracle.exe").Hash.ToLowerInvariant()
    reference_build=$build
    reference_inputs=@($objects | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash $_).Hash.ToLowerInvariant()} })
    reference_sources=@($commands | Where-Object {$_.file -match '[\\/](FROG|GRID|COLLIDE|CAMERA|froganim|MR_ANIM|MR_ANIM3|MR_COLL|ENTITY|PATH|ZONE|MISC|scripter|scripts|ent_org|ent_sub|ent_gen|sound|MR_SOUND|mr_stub_math)\.[cC]$'} | ForEach-Object {
        [ordered]@{path=$_.file;sha256=(Get-FileHash $_.file).Hash.ToLowerInvariant();object=$_.output;command=$_.command}
    })
    acos_table=[ordered]@{path=$acos;sha256=(Get-FileHash $acos).Hash.ToLowerInvariant();count=8193;encoding='signed 16-bit little-endian'}
    components=@('UpdatePathRunners','ENTSTRUpdateMovingMOF','ControlFrog','MoveFrog','CollideFrog','UpdateCamera','UpdateFrogAnimationScripts','MRAnimUpdateEnvironments','CheckCoordsInZones')
    scenarios=@('moving SAFE landing, centring, carry and departure','within-platform hop','no-centring interior cell','quarter-turn with no rotation snap','angled camera attachment','no-entity-angle departure','quick within-platform hop','super off-platform hop','thirty-unit centring','USABLE-only within-platform hop','POPDEATH within-platform hop','water freefall with retained link','water freefall with NO_ENTITY_ANGLE')
    omitted_requests=@('MRSNDPlaySound','AddFrogScore','MRCreatePgen')
    phases=@('ControlFrog','MoveFrog','CollideFrog','UpdateCamera','UpdateFrogAnimationScripts','MRAnimUpdateEnvironments')
    pose_omission='MR_ANIM_ENV_UPDATE temporarily cleared and restored, omitting renderer transform construction'
    factory_wrappers=@('MRCreatePgen','MRCreate3DSprite','CreateParticleEffect','GameAddObjectToViewports')
    game_mode_wrapper='SetGameMainloopMode records mode without running setup callbacks'
    entity_scope='All fixtures use a single SAFE live entity with a one- or two-cell form. One case advances its bounded moving path before frog control; the others use static transforms.'
    retail_route_scope='Decoded high-detail JUN1 bank-log-bank route: all 115 authored identities in source group order; six script-free generic logs use frozen live/path/FORM behavior; 109 geometry-certified neighbors are explicit null-live proof exclusions. The adapter checks independent path positions and the admitted rectangle each phase. It does not execute excluded scripts, audio/effect factories, or retail animation action lengths.'
    org1_route_scope='All 64 decoded identities retain path/script updates in descending all-attached order. Ten admitted primitive-free FORMs are collision-live; all identities remain in ordered scan transport. Real turtle, baby, checkpoint and fly creation/update functions execute with decoded model metadata replacing renderer allocation. Retail flipbook and frog action lengths drive animation; one allocated mesh instance observes colour writes. Logical moving sounds use real allocation; playback and sprite rendering are deferred ordered requests. Distinct sprite storage prevents fly/splash aliasing. No checkpoint collection, selective reset, primitive execution or full engine rendering is certified.'
    org1_probe_scope='All integer support-path orientations and finite frog root closure, all collision hilites and reachable action cels of GEN_FROG.XAR. Separate modes call unchanged root-transition and stored-LW matrix operations. No arbitrary interpolated presentation pose is substituted for collision transforms.'
    entity_script_scope='Invented asset-free programs execute unchanged UpdateScriptInfo, callbacks and animation with synthetic flipbook lengths. Real logical sound allocation executes without playback. Records include source-width state, ordered requests, callback slots, colours, clocks and RNG. Invalid/non-yielding programs are rejected by independent/runtime tests rather than sent to unsafe C.'
    zone_scope='The --zones mode calls frozen CheckCoordsInZones for invented and all-cell retail queries. Input fixtures contain decimal decoded bounds and regions only.'
    script_rng_scope='The --script-rng mode calls frozen ENTSCR_SCRIPT_IF_command for RANDOM with zero hit/carry flags and sound enabled/disabled. Only the branch instruction executes; an invented target is a pointer marker, not executed code. No entity lifecycle, script loop or complete ORG1 route is simulated.'
    background_scope='The --org1-background mode executes UpdateScriptInfo for all 24 traffic programs and real ORG bonus-fly creation/update, using supplied decoded script streams and checkpoint positions. Inactive frogs exclude contact and distance sound. Forward and reverse inventory orders are explicit component cases, not a claim about retail visibility order. Sprite storage is supplied by the existing renderer wrapper; no route, geometry, audio playback or rendering is certified.'
    moving_sound_scope='The --moving-sound-state mode executes the real script command, PlayMovingSound, MRSNDCreateMovingSound and KillMovingSound with a real memory arena. Sound suppression, allocation reuse, owner clearing and recreation are observed; no voice/playback update runs.'
    rng_scope='Effect factories may consume RNG in the full engine; their omitted work is not simulated or compensated.'
    seed=12345
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$out/provenance.json" -Encoding utf8
