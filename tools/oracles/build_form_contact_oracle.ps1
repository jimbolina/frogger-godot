param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [string]$ReferenceBuild = "$PSScriptRoot/../../../froggy/engine/build")
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
$repo=[IO.Path]::GetFullPath("$PSScriptRoot/../..")
$build=[IO.Path]::GetFullPath($ReferenceBuild)
$frozen=[IO.Path]::GetFullPath("$build/../..")
foreach($protected in @($repo,$frozen)) {
    if($out -eq $protected -or $out.StartsWith($protected+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Oracle output must be outside both repositories.'
    }
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$commands=Get-Content "$build/compile_commands.json" | ConvertFrom-Json
$entry=$commands | Where-Object {$_.file -match '[\\/]COLLIDE\.C$'} | Select-Object -First 1
if(-not $entry) { throw 'Frozen COLLIDE.C compile command is missing.' }
$compiler=($entry.command -split ' ')[0]
$env:PATH="$(Split-Path $compiler);$build/_deps/sdl2-build;$env:PATH"
$includes=[regex]::Matches($entry.command,'-I(?:"[^"]+"|[^ ]+)') | ForEach-Object {$_.Value}
$objects=Get-ChildItem "$build/mr_stub/CMakeFiles/mr_stub_common.dir" -Filter '*.obj' -Recurse | ForEach-Object {$_.FullName}
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/form_contact_oracle.c" @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" -lws2_32 -lshell32 -lm -o "$out/form_contact_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Form contact oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$metadata=[ordered]@{
    adapter_source_sha256=(Get-FileHash "$PSScriptRoot/form_contact_oracle.c").Hash.ToLowerInvariant()
    adapter_binary_sha256=(Get-FileHash "$out/form_contact_oracle.exe").Hash.ToLowerInvariant()
    reference_build=$build
    reference_inputs=@($objects + @("$build/real_source/libfrogger_real_source.a","$build/asset_pipeline/libasset_pipeline.a") | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash $_).Hash.ToLowerInvariant()} })
    reference_sources=@($commands | Where-Object {$_.file -match '[\\/](COLLIDE|FORM|MAPLOAD)\.C$'} | ForEach-Object {
        [ordered]@{path=$_.file;sha256=(Get-FileHash $_.file).Hash.ToLowerInvariant();object=$_.output}
    })
    scope='Unchanged CollideFrog model-backed FORM geometry; one synthetic live entity/group; no API collprims; USABLE|SLIPPY cells; hit flag observation; no reaction claims'
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$out/provenance.json" -Encoding utf8
Write-Output "$out/form_contact_oracle.exe"
