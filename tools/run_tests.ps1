# Runs every test headless with GUT in an isolated temporary Godot profile.
#
#   $env:GODOT = "C:\path\to\Godot.exe"; .\tools\run_tests.ps1 [extra GUT options]
#
# Logs and the named-skip summary are retained in the printed temporary folder.
# Exit codes: 0 all passed; 1 a failure or a script that does not compile;
# 2 setup problem; 3 nothing failed but some tests were skipped.
$ErrorActionPreference = "Stop"
$gutArguments = @($args)
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$godotCommand = Get-Command $godot -CommandType Application -ErrorAction SilentlyContinue
if (-not $godotCommand) {
    Write-Output "run_tests: Godot not found; set `$env:GODOT to the Godot executable"
    exit 2
}
$godotExecutable = $godotCommand.Source
$projectDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$scriptErrorPattern = "SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Could not load|CHECK FAILED"

# Start-Process joins its arguments into one Windows command line. Quote each
# one using native escaping rules, including embedded quotes and final '\'.
function ConvertTo-NativeArgument([string] $value) {
    $quoted = '"'
    $slashes = 0
    foreach ($character in $value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes += 1
        } elseif ($character -eq '"') {
            $quoted += ('\' * ($slashes * 2 + 1)) + '"'
            $slashes = 0
        } else {
            $quoted += ('\' * $slashes) + $character
            $slashes = 0
        }
    }
    return $quoted + ('\' * ($slashes * 2)) + '"'
}

function Invoke-GodotStage([string] $name, [string[]] $stageArguments) {
    $logPath = Join-Path $runDirectory ($name + ".log")
    $nativeArguments = @("--headless", "--disable-crash-handler", "--path", $projectDirectory, "--log-file", $logPath) + $stageArguments
    $commandLine = ($nativeArguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join " "
    $process = Start-Process -FilePath $godotExecutable -ArgumentList $commandLine -WorkingDirectory $projectDirectory -WindowStyle Hidden -Wait -PassThru
    $output = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { "" }
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output; LogPath = $logPath }
}

$savedEnvironment = @{}
foreach ($name in @("APPDATA", "TEMP", "TMP")) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    $runDirectory = Join-Path ([IO.Path]::GetTempPath()) ("frogger-tests-" + [Guid]::NewGuid().ToString("N"))
    $profileDirectory = Join-Path $runDirectory "appdata"
    $temporaryDirectory = Join-Path $runDirectory "temp"
    New-Item -ItemType Directory -Path $profileDirectory, $temporaryDirectory -Force | Out-Null
    $env:APPDATA = $profileDirectory
    $env:TEMP = $temporaryDirectory
    $env:TMP = $temporaryDirectory
    Write-Output "run_tests: logs and isolated profile: $runDirectory"

    $import = Invoke-GodotStage "import" @("--import")
    if ($import.ExitCode -ne 0 -or -not $import.Output -or $import.Output -match $scriptErrorPattern) {
        Write-Output $import.Output
        Write-Output "run_tests: import failed; see $($import.LogPath)"
        exit 1
    }

    # Compile first: GUT otherwise continues past scripts it could not load.
    $check = Invoke-GodotStage "check" @("-s", "res://tools/check_scripts.gd")
    $check.Output -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|at: GDScript|CHECK FAILED|check_scripts:" }
    if ($check.ExitCode -ne 0 -or $check.Output -match $scriptErrorPattern -or $check.Output -notmatch "(?m)^check_scripts: \d+ scripts, 0 failed\s*$") {
        Write-Output $check.Output
        Write-Output "run_tests: strict compilation failed; see $($check.LogPath)"
        exit 1
    }

    $tests = Invoke-GodotStage "tests" (@("-s", "res://addons/gut/gut_cmdln.gd") + $gutArguments)
    Write-Output $tests.Output
    $result = $tests.ExitCode
    if ($tests.Output -match $scriptErrorPattern) {
        Write-Output "run_tests: script errors found; see $($tests.LogPath)"
        $result = 1
    }
    if ($tests.Output -notmatch "(?m)^SUMMARY: PASS=\d+ FAIL=\d+ SKIP=\d+ EXIT=[013]\s*$") {
        Write-Output "run_tests: no complete summary; see $($tests.LogPath)"
        $result = 1
    }
    exit $result
} catch {
    Write-Output "run_tests: $($_.Exception.Message)"
    exit 1
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], "Process")
    }
}
