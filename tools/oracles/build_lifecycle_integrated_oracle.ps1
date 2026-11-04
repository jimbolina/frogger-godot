param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [string]$ReferenceBuild = "$PSScriptRoot/../../../froggy/engine/build")
$ErrorActionPreference = 'Stop'
$out = [IO.Path]::GetFullPath($OutputDirectory)
$repo = [IO.Path]::GetFullPath("$PSScriptRoot/../..")
$build = [IO.Path]::GetFullPath($ReferenceBuild)
$frozen = [IO.Path]::GetFullPath("$build/../..")
foreach ($protected in @($repo, $frozen)) {
    if ($out -eq $protected -or $out.StartsWith($protected + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Output must be outside both repositories.'
    }
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$source = Get-Content "$PSScriptRoot/integrated_entity_oracle.c" -Raw
$needle = 'int main(void) {'
if (-not $source.Contains($needle)) { throw 'Integrated oracle entry point changed.' }
$source = $source.Replace($needle, 'int integrated_source_main_unused(void) {')
$tail = Get-Content "$PSScriptRoot/lifecycle_integrated_oracle_tail.c" -Raw
$combined = Join-Path $out 'lifecycle_integrated_combined.c'
[IO.File]::WriteAllText($combined, $source + "`n" + $tail)
$commands = Get-Content "$build/compile_commands.json" | ConvertFrom-Json
$entry = $commands | Where-Object { $_.file -match '[\\/]mr_grid_slice_main.c$' } | Select-Object -First 1
$compiler = ($entry.command -split ' ')[0]
$env:PATH = "$(Split-Path $compiler);$build/_deps/sdl2-build;$env:PATH"
$includes = [regex]::Matches($entry.command, '-I(?:"[^"]+"|[^ ]+)') | ForEach-Object { $_.Value }
$objects = Get-ChildItem "$build/mr_stub/CMakeFiles/mr_stub_common.dir" -Filter '*.obj' -Recurse | ForEach-Object { $_.FullName }
& $compiler @includes -std=gnu99 -O2 $combined @objects "$build/real_source/libfrogger_real_source.a" "$build/asset_pipeline/libasset_pipeline.a" "$build/_deps/sdl2-build/libSDL2.dll.a" '-Wl,--wrap=MRSNDPlaySound' '-Wl,--wrap=AddFrogScore' '-Wl,--wrap=MRCreatePgen' '-Wl,--wrap=MRCreate3DSprite' '-Wl,--wrap=CreateParticleEffect' '-Wl,--wrap=GameAddObjectToViewports' '-Wl,--wrap=SetGameMainloopMode' -lws2_32 -lshell32 -lm -o "$out/lifecycle_integrated_oracle.exe"
if ($LASTEXITCODE -ne 0) { throw 'Lifecycle integrated oracle link failed.' }
Copy-Item -LiteralPath "$build/_deps/sdl2-build/SDL2.dll" -Destination "$out/SDL2.dll" -Force
$metadata = [ordered]@{
    adapter_source_sha256 = (Get-FileHash "$PSScriptRoot/lifecycle_integrated_oracle_tail.c").Hash.ToLowerInvariant()
    shared_transport_source_sha256 = (Get-FileHash "$PSScriptRoot/integrated_entity_oracle.c").Hash.ToLowerInvariant()
    combined_source_sha256 = (Get-FileHash $combined).Hash.ToLowerInvariant()
    adapter_binary_sha256 = (Get-FileHash "$out/lifecycle_integrated_oracle.exe").Hash.ToLowerInvariant()
    reference_build = $build
    reference_inputs = @($objects + @("$build/real_source/libfrogger_real_source.a", "$build/asset_pipeline/libasset_pipeline.a") | ForEach-Object { [ordered]@{ path = $_; sha256 = (Get-FileHash $_).Hash.ToLowerInvariant() } })
    components = @('ControlFrog','MoveFrog','CollideFrog','UpdateCamera','UpdateFrogAnimationScripts','MRAnimUpdateEnvironments')
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$out/provenance.json" -Encoding utf8
Write-Output "$out/lifecycle_integrated_oracle.exe"
