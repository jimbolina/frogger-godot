param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [string]$ReferenceBuild = "$PSScriptRoot/../../../froggy/engine/build")
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
$repo=[IO.Path]::GetFullPath("$PSScriptRoot/../..")
$build=[IO.Path]::GetFullPath($ReferenceBuild)
$frozen=[IO.Path]::GetFullPath("$build/../..")
foreach($protected in @($repo,$frozen)) {
    if ($out -eq $protected -or $out.StartsWith($protected+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Oracle binaries must be outside the project and frozen reference repositories.'
    }
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$commands=Get-Content "$build/compile_commands.json" | ConvertFrom-Json
$entry=$commands | Where-Object {$_.file -match '[\\/]GRID.C$'} | Select-Object -First 1
$compiler=($entry.command -split ' ')[0]
$env:PATH="$(Split-Path $compiler);$env:PATH"
$includes=[regex]::Matches($entry.command,'-I(?:"[^"]+"|[^ ]+)') | ForEach-Object {$_.Value}
$grid="$build/$($entry.output)"
$math="$build/mr_stub/CMakeFiles/mr_stub_common.dir/src/gpu/mr_stub_math.c.obj"
& $compiler @includes -std=gnu99 -O2 "$PSScriptRoot/grid_oracle_adapter.c" $grid $math -lm -o "$out/grid_oracle.exe"
if($LASTEXITCODE -ne 0) { throw 'Oracle link failed.' }
Get-FileHash $entry.file,$grid,$math,"$out/grid_oracle.exe" | Format-Table -AutoSize
$metadata=[ordered]@{
    sanitized_grid_source_sha256=(Get-FileHash $entry.file).Hash.ToLowerInvariant()
    grid_object_sha256=(Get-FileHash $grid).Hash.ToLowerInvariant()
    math_object_sha256=(Get-FileHash $math).Hash.ToLowerInvariant()
    adapter_source_sha256=(Get-FileHash "$PSScriptRoot/grid_oracle_adapter.c").Hash.ToLowerInvariant()
    adapter_binary_sha256=(Get-FileHash "$out/grid_oracle.exe").Hash.ToLowerInvariant()
    compiler=$compiler
    reference_build=$build
    linkage='Existing frozen GRID.C.obj and mr_stub_math.c.obj; only transport compiled'
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath "$out/provenance.json" -Encoding utf8
