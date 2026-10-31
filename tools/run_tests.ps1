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

$assetDirectory = Join-Path $projectDirectory "assets"
if (Test-Path -LiteralPath $assetDirectory -PathType Container) {
    $pointerPrefix = "version https://git-lfs.github.com/spec"
    foreach ($asset in Get-ChildItem -LiteralPath $assetDirectory -Recurse -File | Where-Object { $_.Length -lt 1024 }) {
        $bytes = [IO.File]::ReadAllBytes($asset.FullName)
        $start = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min($bytes.Length, $pointerPrefix.Length))
        if ($start -ceq $pointerPrefix) {
            Write-Output "run_tests: assets contain git LFS pointers; run git lfs pull"
            exit 2
        }
    }
}

$archiveRequested = Test-Path Env:FROGGER_DATA_DIR
$archiveDataDirectory = if ($archiveRequested) { $env:FROGGER_DATA_DIR } else { "" }

function Test-Suite([string] $suite, [string[]] $suiteArguments) {
    $tests = Invoke-GodotStage $suite (@("-s", "res://addons/gut/gut_cmdln.gd") + $suiteArguments)
    Write-Output $tests.Output
    $passed = $tests.ExitCode -eq 0
    if ($tests.Output -match $scriptErrorPattern) {
        Write-Output "run_tests: script errors found in the $suite suite; see $($tests.LogPath)"
        $passed = $false
    }
    $validation = Invoke-GodotStage "$suite-results" @("-s", "res://tools/check_test_results.gd", "--", $tests.LogPath, [string]$tests.ExitCode, "--suite=$suite")
    $validation.Output -split "`n" | Where-Object { $_ -match "RESULT ERROR|test_results:" }
    if ($validation.ExitCode -ne 0 -or $validation.Output -match $scriptErrorPattern -or $validation.Output -notmatch "(?m)^test_results: valid $suite suite, exit [01]\s*$") {
        Write-Output "run_tests: $suite suite result validation failed; see $($validation.LogPath)"
        $passed = $false
    }
    $script:suiteFailed = $script:suiteFailed -or -not $passed
}

$savedEnvironment = @{}
foreach ($name in @("APPDATA", "TEMP", "TMP", "FROGGER_DATA_DIR", "FROGGER_TEST_SUITE")) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$runPrepared = $false
try {
    $runDirectory = Join-Path ([IO.Path]::GetTempPath()) ("frogger-tests-" + [Guid]::NewGuid().ToString("N"))
    $profileDirectory = Join-Path $runDirectory "appdata"
    $temporaryDirectory = Join-Path $runDirectory "temp"
    New-Item -ItemType Directory -Path $profileDirectory, $temporaryDirectory -Force | Out-Null
    $runPrepared = $true
    $env:APPDATA = $profileDirectory
    $env:TEMP = $temporaryDirectory
    $env:TMP = $temporaryDirectory
    Remove-Item Env:FROGGER_DATA_DIR, Env:FROGGER_TEST_SUITE -ErrorAction SilentlyContinue
    Write-Output "run_tests: logs and isolated profile: $runDirectory"

    $import = Invoke-GodotStage "import" @("--import")
    if ($import.ExitCode -ne 0 -or -not $import.Output -or $import.Output -match $scriptErrorPattern) {
        Write-Output $import.Output
        Write-Output "run_tests: import failed; see $($import.LogPath)"
        exit 1
    }

    $check = Invoke-GodotStage "check" @("-s", "res://tools/check_scripts.gd")
    $check.Output -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|at: GDScript|CHECK FAILED|check_scripts:" }
    if ($check.ExitCode -ne 0 -or $check.Output -match $scriptErrorPattern -or $check.Output -notmatch "(?m)^check_scripts: \d+ scripts, 0 failed\s*$") {
        Write-Output $check.Output
        Write-Output "run_tests: strict compilation failed; see $($check.LogPath)"
        exit 1
    }

    $architecture = Invoke-GodotStage "architecture" @("-s", "res://tools/check_architecture.gd")
    $architecture.Output -split "`n" | Where-Object { $_ -match "ARCHITECTURE|architecture_check:" }
    if ($architecture.ExitCode -ne 0 -or $architecture.Output -match $scriptErrorPattern -or $architecture.Output -notmatch "(?m)^architecture_check: \d+ scripts, 0 failed\s*$") {
        Write-Output $architecture.Output
        Write-Output "run_tests: architecture check failed; see $($architecture.LogPath)"
        exit 1
    }

    $script:suiteFailed = $false
    Test-Suite "game" $gutArguments

    if ($archiveRequested) {
        $env:FROGGER_DATA_DIR = $archiveDataDirectory
        $inputCheck = Invoke-GodotStage "input" @("-s", "res://tools/check_test_results.gd", "--", "--input")
        if ($inputCheck.ExitCode -ne 0 -or $inputCheck.Output -match $scriptErrorPattern -or $inputCheck.Output -notmatch "(?m)^test_input: valid\s*$") {
            Write-Output $inputCheck.Output
            Write-Output "run_tests: invalid archive input; see $($inputCheck.LogPath)"
            exit 1
        }
        $env:FROGGER_TEST_SUITE = "archive"
        Test-Suite "archive" @("-gconfig=res://archive/tests/.gutconfig.json")
        Remove-Item Env:FROGGER_TEST_SUITE -ErrorAction SilentlyContinue
    } else {
        Write-Output "run_tests: archive suite not run (FROGGER_DATA_DIR unset)"
    }
    exit $(if ($script:suiteFailed) { 1 } else { 0 })
} catch {
    Write-Output "run_tests: $($_.Exception.Message)"
    if (-not $runPrepared) { exit 2 }
    exit 1
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], "Process")
    }
}
