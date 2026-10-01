# Deterministic windowed map capture with isolated writable user data.
# Usage: $env:GODOT='C:\path\Godot.exe'; tools/capture_map.ps1 -OutputDirectory C:\captures -Level SUB1
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$Level = 'SUB1',
    [ValidateSet('default','map-slice')][string]$Camera = 'map-slice',
    [string]$CameraSource = '',
    [string]$CameraTarget = '',
    [ValidateScript({ $_ -eq 0 -or ($_ -ge 3 -and $_ -le 8192) })][int]$Projection = 0,
    [ValidateRange(0,100000)][int]$Tick = 0,
    [switch]$LowDetail,
    [switch]$Linear,
    [switch]$Benchmark,
    [string]$ProbeModel = ''
)
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { throw 'Output directory must be absolute.' }
$captureDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if ($captureDirectory -eq $projectDirectory -or $captureDirectory.StartsWith($projectDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Captures must stay outside the repository.'
}
$godotExecutable = (Get-Command $(if ($env:GODOT) { $env:GODOT } else { 'godot' }) -CommandType Application -ErrorAction Stop).Source
function ConvertTo-NativeArgument([string]$value) {
    $quoted = '"'; $slashes = 0
    foreach ($character in $value.ToCharArray()) {
        if ($character -eq '\') { $slashes += 1 }
        elseif ($character -eq '"') { $quoted += ('\' * ($slashes * 2 + 1)) + '"'; $slashes = 0 }
        else { $quoted += ('\' * $slashes) + $character; $slashes = 0 }
    }
    return $quoted + ('\' * ($slashes * 2)) + '"'
}
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('frogger-map-capture-' + [Guid]::NewGuid().ToString('N'))
$profileDirectory = Join-Path $runDirectory 'appdata'
$temporaryDirectory = Join-Path $runDirectory 'temp'
New-Item -ItemType Directory -Path $profileDirectory,$temporaryDirectory,$captureDirectory -Force | Out-Null
$savedEnvironment = @{}
foreach ($name in @('APPDATA','TEMP','TMP')) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $env:APPDATA = $profileDirectory; $env:TEMP = $temporaryDirectory; $env:TMP = $temporaryDirectory
    # Refresh global script classes before running a newly checked-out viewer.
    $importLog = Join-Path $runDirectory 'import.log'
    $importArguments = @('--headless','--disable-crash-handler','--path',$projectDirectory,'--log-file',$importLog,'--import')
    $importLine = ($importArguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $importProcess = Start-Process -FilePath $godotExecutable -ArgumentList $importLine -WorkingDirectory $projectDirectory -WindowStyle Hidden -Wait -PassThru
    $importOutput = if (Test-Path -LiteralPath $importLog) { Get-Content -LiteralPath $importLog -Raw } else { '' }
    if ($importProcess.ExitCode -ne 0 -or -not $importOutput -or $importOutput -match 'SCRIPT ERROR|Parse Error|Failed to load script') {
        Write-Output $importOutput
        Write-Output "capture_map: import failed; see $importLog"
        exit 1
    }
    $logPath = Join-Path $runDirectory 'capture.log'
    $arguments = @('--disable-crash-handler','--path',$projectDirectory,'--log-file',$logPath,'res://scenes/tools/map_viewer.tscn','--',('--level=' + $Level),('--camera=' + $Camera),('--tick=' + $Tick),('--low-poly=' + $LowDetail.IsPresent.ToString().ToLower()),('--linear=' + $Linear.IsPresent.ToString().ToLower()),('--screenshot-dir=' + $captureDirectory))
    if ($Benchmark) { $arguments += '--benchmark' }
    if ($ProbeModel) { $arguments += '--probe-model=' + $ProbeModel }
    # The viewer validates raw comma-separated coordinates and distinct poses.
    if ($CameraSource) { $arguments += '--camera-source=' + $CameraSource }
    if ($CameraTarget) { $arguments += '--camera-target=' + $CameraTarget }
    if ($Projection -ne 0) { $arguments += '--projection=' + $Projection }
    $commandLine = ($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    Write-Output "capture_map: log $logPath"
    $process = Start-Process -FilePath $godotExecutable -ArgumentList $commandLine -WorkingDirectory $projectDirectory -WindowStyle Hidden -Wait -PassThru
    $output = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { '' }
    Write-Output $output
    $checkedOutput = $output -replace 'ERROR: Failed to read the root certificate store\.[\r\n]+\s+at: get_system_ca_certificates[^\r\n]*', ''
    if ($process.ExitCode -ne 0 -or $checkedOutput -match 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' -or $output -notmatch 'map capture .*: OK') { exit 1 }
    exit 0
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],'Process') }
}
