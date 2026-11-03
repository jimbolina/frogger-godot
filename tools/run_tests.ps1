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

$uv = if ($env:UV) { $env:UV } else { "uv" }
$angularDirectory = Join-Path $projectDirectory "content\fonts\angular"
if (Test-Path -LiteralPath $angularDirectory -PathType Container) {
    if (-not (Get-Command $uv -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Output "run_tests: uv not found; install uv or set `$env:UV to the uv executable"
        exit 2
    }
    & $uv run --locked --quiet --project $projectDirectory (Join-Path $projectDirectory "tools\make_angular_font.py") --check --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Output "run_tests: the committed angular font differs from its generator"
        exit 2
    }
    & $uv run --locked --quiet --project $projectDirectory (Join-Path $projectDirectory "tools\make_lettering.py") --check --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Output "run_tests: the committed lettering images differ from their generator"
        exit 2
    }
}

$python = if ($env:PYTHON) { $env:PYTHON } else { "python3" }
& $python (Join-Path $projectDirectory "tools\test_capture_tools.py") *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Output "run_tests: capture tool self-test failed"
    exit 2
}

$pointerPrefix = "version https://git-lfs.github.com/spec"
foreach ($folder in @("assets", "content")) {
    $assetDirectory = Join-Path $projectDirectory $folder
    if (-not (Test-Path -LiteralPath $assetDirectory -PathType Container)) { continue }
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
    if ($tests.Output -cmatch $scriptErrorPattern) {
        Write-Output "run_tests: script errors found in the $suite suite; see $($tests.LogPath)"
        $passed = $false
    }
    $validation = Invoke-GodotStage "$suite-results" @("-s", "res://tools/check_test_results.gd", "--", $tests.LogPath, [string]$tests.ExitCode, "--suite=$suite")
    $validation.Output -split "`n" | Where-Object { $_ -cmatch "RESULT ERROR|test_results:" }
    if ($validation.ExitCode -ne 0 -or $validation.Output -cmatch $scriptErrorPattern -or $validation.Output -cnotmatch "(?m)^test_results: valid $suite suite, exit [01]\s*$") {
        Write-Output "run_tests: $suite suite result validation failed; see $($validation.LogPath)"
        $passed = $false
    }
    $script:suiteFailed = $script:suiteFailed -or -not $passed
}

$savedEnvironment = @{}
foreach ($name in @("APPDATA", "TEMP", "TMP", "FROGGER_DATA_DIR", "FROGGER_TEST_SUITE", "FROGGER_GENERATED_DIR")) {
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

    if (Test-Path -LiteralPath (Join-Path $projectDirectory "assets\textures\images") -PathType Container) {
        $generated = Join-Path $runDirectory "generated"
        $python = if ($env:PYTHON) { $env:PYTHON } else { "python3" }
        & $python (Join-Path $projectDirectory "tools\make_font_newfont.py") --out (Join-Path $generated "newfont") --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Output "run_tests: the newfont generator failed"
            exit 2
        }
        & $uv run --locked --quiet --project $projectDirectory (Join-Path $projectDirectory "tools\make_lettering.py") --composite (Join-Path $projectDirectory "assets") --out (Join-Path $generated "lettering") --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Output "run_tests: the lettering tile generator failed"
            exit 2
        }
        $env:FROGGER_GENERATED_DIR = $generated
    }

    $import = Invoke-GodotStage "import" @("--import")
    if ($import.ExitCode -ne 0 -or -not $import.Output -or $import.Output -cmatch $scriptErrorPattern) {
        Write-Output $import.Output
        Write-Output "run_tests: import failed; see $($import.LogPath)"
        exit 1
    }

    $check = Invoke-GodotStage "check" @("-s", "res://tools/check_scripts.gd")
    $check.Output -split "`n" | Where-Object { $_ -cmatch "SCRIPT ERROR|at: GDScript|CHECK FAILED|check_scripts:" }
    if ($check.ExitCode -ne 0 -or $check.Output -cmatch $scriptErrorPattern -or $check.Output -cnotmatch "(?m)^check_scripts: \d+ scripts, 0 failed\s*$") {
        Write-Output $check.Output
        Write-Output "run_tests: strict compilation failed; see $($check.LogPath)"
        exit 1
    }

    $architecture = Invoke-GodotStage "architecture" @("-s", "res://tools/check_architecture.gd")
    $architecture.Output -split "`n" | Where-Object { $_ -cmatch "ARCHITECTURE|architecture_check:" }
    if ($architecture.ExitCode -ne 0 -or $architecture.Output -cmatch $scriptErrorPattern -or $architecture.Output -cnotmatch "(?m)^architecture_check: \d+ scripts, 0 failed\s*$") {
        Write-Output $architecture.Output
        Write-Output "run_tests: architecture check failed; see $($architecture.LogPath)"
        exit 1
    }

    $script:suiteFailed = $false
    Test-Suite "game" $gutArguments

    if ($archiveRequested) {
        $env:FROGGER_DATA_DIR = $archiveDataDirectory
        $inputCheck = Invoke-GodotStage "input" @("-s", "res://tools/check_test_results.gd", "--", "--input")
        if ($inputCheck.ExitCode -ne 0 -or $inputCheck.Output -cmatch $scriptErrorPattern -or $inputCheck.Output -cnotmatch "(?m)^test_input: valid\s*$") {
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
