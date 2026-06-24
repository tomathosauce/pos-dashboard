[CmdletBinding()]
param(
    [string]$Python = $env:POS_DASHBOARD_DEV_PYTHON,
    [ValidateSet("default", "x86", "x64")]
    [string]$PythonArchitecture = $(if ($env:POS_DASHBOARD_DEV_PYTHON_ARCH) { $env:POS_DASHBOARD_DEV_PYTHON_ARCH } else { "default" }),
    [switch]$WithOdbc,
    [switch]$WithPxlib,
    [switch]$AllReaders,
    [switch]$SkipBackend,
    [switch]$SkipFrontend,
    [switch]$SkipEnvFile,
    [switch]$RecreateVenv,
    [switch]$UseNpmInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BackendDir = Join-Path $ProjectRoot "backend"
$FrontendDir = Join-Path $ProjectRoot "frontend"
$VenvDir = Join-Path $BackendDir ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"

if ($AllReaders) {
    $WithOdbc = $true
    $WithPxlib = $true
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Resolve-PythonCommand {
    if ($Python) {
        return @{
            File = $Python
            Args = @()
        }
    }

    $PyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($PyLauncher) {
        $Selector = switch ($PythonArchitecture) {
            "x86" { "-3-32" }
            "x64" { "-3-64" }
            default { "-3" }
        }
        return @{
            File = "py"
            Args = @($Selector)
        }
    }

    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($PythonCommand) {
        return @{
            File = "python"
            Args = @()
        }
    }

    throw "Python was not found. Install Python for development, or pass -Python C:\Path\To\python.exe."
}

function Invoke-ConfiguredPython {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $AllArgs = @()
    $AllArgs += $script:PythonCommand["Args"]
    $AllArgs += $Arguments
    Invoke-Native $script:PythonCommand["File"] @AllArgs
}

function Assert-VenvArchitecture {
    if ($PythonArchitecture -eq "default") {
        return
    }

    $ExpectedBits = if ($PythonArchitecture -eq "x86") { "32" } else { "64" }
    $ActualBits = & $VenvPython -c "import struct; print(struct.calcsize('P') * 8)"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect virtualenv Python architecture."
    }
    $ActualBits = ($ActualBits -join "").Trim()
    if ($ActualBits -ne $ExpectedBits) {
        throw "Virtualenv Python is $ActualBits-bit, expected $ExpectedBits-bit. Re-run with -RecreateVenv and the right -Python or -PythonArchitecture."
    }
}

Push-Location $ProjectRoot
try {
    if (-not $SkipEnvFile) {
        $EnvExample = Join-Path $ProjectRoot ".env.example"
        $EnvFile = Join-Path $ProjectRoot ".env"
        if ((Test-Path $EnvExample) -and (-not (Test-Path $EnvFile))) {
            Write-Step "Creating .env from .env.example"
            Copy-Item -Path $EnvExample -Destination $EnvFile
        }
    }

    if (-not $SkipBackend) {
        Write-Step "Setting up backend virtualenv"
        $script:PythonCommand = Resolve-PythonCommand

        if ($RecreateVenv -and (Test-Path $VenvDir)) {
            Remove-Item -Recurse -Force $VenvDir
        }
        if (-not (Test-Path $VenvPython)) {
            Invoke-ConfiguredPython -Arguments @("-m", "venv", $VenvDir)
        }

        Assert-VenvArchitecture

        Write-Step "Installing backend dependencies"
        Invoke-Native $VenvPython -m pip install --upgrade pip
        Invoke-Native $VenvPython -m pip install -r (Join-Path $BackendDir "requirements.txt")

        if ($WithOdbc) {
            Write-Step "Installing ODBC reader dependencies"
            Invoke-Native $VenvPython -m pip install -r (Join-Path $BackendDir "requirements-odbc.txt")
        }
        if ($WithPxlib) {
            Write-Step "Installing pxlib reader dependencies"
            Invoke-Native $VenvPython -m pip install -r (Join-Path $BackendDir "requirements-pxlib.txt")
        }
    }

    if (-not $SkipFrontend) {
        Write-Step "Installing frontend dependencies"
        Assert-Command npm
        Push-Location $FrontendDir
        try {
            if ((Test-Path (Join-Path $FrontendDir "package-lock.json")) -and (-not $UseNpmInstall)) {
                Invoke-Native npm ci
            }
            else {
                Invoke-Native npm install
            }
        }
        finally {
            Pop-Location
        }
    }

    Write-Step "Development setup complete"
    Write-Host "Backend venv: $VenvDir"
    Write-Host "Start PostgreSQL: docker compose up db"
    Write-Host "Run migrations:  cd backend; .\.venv\Scripts\alembic upgrade head"
    Write-Host "Run backend:     cd backend; .\.venv\Scripts\uvicorn app.main:app --reload --host 127.0.0.1 --port 8000"
    Write-Host "Run frontend:    cd frontend; npm run dev"
}
finally {
    Pop-Location
}
