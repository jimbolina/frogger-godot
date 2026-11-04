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
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/entity_primitive_oracle.c" @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" -lws2_32 -lshell32 -lm -o "$out/entity_primitive_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Entity primitive oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$objects += "$build/real_source/libfrogger_real_source.a","$build/asset_pipeline/libasset_pipeline.a"
[ordered]@{
    adapter_source_sha256=(Get-FileHash "$PSScriptRoot/entity_primitive_oracle.c").Hash.ToLowerInvariant()
    adapter_binary_sha256=(Get-FileHash "$out/entity_primitive_oracle.exe").Hash.ToLowerInvariant()
    reference_inputs=@($objects | ForEach-Object { [ordered]@{path=$_;sha256=(Get-FileHash $_).Hash.ToLowerInvariant()} })
    functions=@('MulMatrix0','ApplyMatrix','ApplyMatrixSV','MRCheckCollPrimWithWorldPoint')
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$out/entity_primitive_oracle.json" -Encoding utf8
Write-Output "$out/entity_primitive_oracle.exe"
