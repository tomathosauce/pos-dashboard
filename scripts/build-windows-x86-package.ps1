[CmdletBinding()]
param(
    [string]$PythonVersion = "3.11.9",
    [string]$PackageName = "pos-dashboard-windows-x86.zip",
    [string]$OutputDir,
    [switch]$SkipFrontendBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BackendDir = Join-Path $ProjectRoot "backend"
$FrontendDir = Join-Path $ProjectRoot "frontend"
$ScriptsDir = Join-Path $ProjectRoot "scripts"
$BuildRoot = Join-Path $ProjectRoot ".package"
$StageDir = Join-Path $BuildRoot "windows-x86"
$DownloadDir = Join-Path $BuildRoot "downloads"
if (-not $OutputDir) {
    $OutputDir = Join-Path $ProjectRoot "release"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$PackagePath = Join-Path $OutputDir $PackageName

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

function Invoke-Robocopy {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$ExcludeDirectories = @(),
        [string[]]$ExcludeFiles = @()
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $Args = @($Source, $Destination, "/MIR", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
    if ($ExcludeDirectories.Count -gt 0) {
        $Args += "/XD"
        $Args += $ExcludeDirectories
    }
    if ($ExcludeFiles.Count -gt 0) {
        $Args += "/XF"
        $Args += $ExcludeFiles
    }

    & robocopy @Args | Out-Host
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed with exit code $LASTEXITCODE."
    }
}

Assert-Command npm
Assert-Command robocopy

New-Item -ItemType Directory -Force -Path $BuildRoot, $DownloadDir, $OutputDir | Out-Null
if (Test-Path $StageDir) {
    Remove-Item -Recurse -Force $StageDir
}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

if (-not $SkipFrontendBuild) {
    Push-Location $FrontendDir
    try {
        if (Test-Path (Join-Path $FrontendDir "package-lock.json")) {
            Invoke-Native npm ci
        }
        else {
            Invoke-Native npm install
        }

        $PreviousApiBase = $env:VITE_API_BASE_URL
        Remove-Item Env:VITE_API_BASE_URL -ErrorAction SilentlyContinue
        try {
            Invoke-Native npm run build
        }
        finally {
            if ($null -ne $PreviousApiBase) {
                $env:VITE_API_BASE_URL = $PreviousApiBase
            }
        }
    }
    finally {
        Pop-Location
    }
}

$FrontendDist = Join-Path $FrontendDir "dist"
if (-not (Test-Path (Join-Path $FrontendDist "index.html"))) {
    throw "Missing built frontend. Run npm run build or omit -SkipFrontendBuild."
}

$StageBackend = Join-Path $StageDir "backend"
$StageFrontend = Join-Path $StageDir "frontend"
$StageRuntime = Join-Path $StageDir "runtime\python-x86"

Invoke-Robocopy `
    -Source $BackendDir `
    -Destination $StageBackend `
    -ExcludeDirectories @(".venv", "__pycache__", ".pytest_cache") `
    -ExcludeFiles @("*.pyc", "*.pyo")

New-Item -ItemType Directory -Force -Path (Join-Path $StageFrontend "dist") | Out-Null
Invoke-Robocopy -Source $FrontendDist -Destination (Join-Path $StageFrontend "dist")

$PythonZip = Join-Path $DownloadDir ("python-{0}-embed-win32.zip" -f $PythonVersion)
$PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-win32.zip"
if (-not (Test-Path $PythonZip)) {
    Write-Host "Downloading $PythonUrl"
    Invoke-WebRequest -Uri $PythonUrl -OutFile $PythonZip
}

New-Item -ItemType Directory -Force -Path $StageRuntime | Out-Null
Expand-Archive -Path $PythonZip -DestinationPath $StageRuntime -Force

$PthFile = Get-ChildItem -Path $StageRuntime -Filter "python*._pth" | Select-Object -First 1
if (-not $PthFile) {
    throw "Could not find Python embeddable ._pth file."
}

$PthLines = Get-Content -Path $PthFile.FullName
$NewPthLines = New-Object System.Collections.Generic.List[string]
$AddedSitePackages = $false
$BackendPathEntry = "..\..\backend"
foreach ($Line in $PthLines) {
    if ($Line -eq "#import site" -or $Line -eq "import site") {
        if (-not $AddedSitePackages) {
            $NewPthLines.Add("Lib\site-packages")
            $AddedSitePackages = $true
        }
        $NewPthLines.Add("import site")
    }
    else {
        $NewPthLines.Add($Line)
    }
}
if (-not $NewPthLines.Contains($BackendPathEntry)) {
    $NewPthLines.Add($BackendPathEntry)
}
if (-not $AddedSitePackages) {
    $NewPthLines.Add("Lib\site-packages")
    $NewPthLines.Add("import site")
}
Set-Content -Path $PthFile.FullName -Value $NewPthLines -Encoding ASCII

$PythonExe = Join-Path $StageRuntime "python.exe"
$GetPip = Join-Path $DownloadDir "get-pip.py"
if (-not (Test-Path $GetPip)) {
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $GetPip
}

Invoke-Native $PythonExe $GetPip "--no-warn-script-location"
Invoke-Native $PythonExe -m pip install --no-warn-script-location --upgrade pip
$WindowsRequirements = Join-Path $StageBackend "requirements-windows-x86.txt"
$RuntimeRequirements = Join-Path $BuildRoot "requirements-windows-x86-runtime.txt"
$WindowsRequirementLines = Get-Content -Path $WindowsRequirements
$SqlAlchemyRequirement = ($WindowsRequirementLines | Where-Object { $_ -match "^\s*SQLAlchemy\s*(==|>=|<=|~=|!=|>|<)" } | Select-Object -First 1).Trim()
$AlembicRequirement = ($WindowsRequirementLines | Where-Object { $_ -match "^\s*alembic\s*(==|>=|<=|~=|!=|>|<)" } | Select-Object -First 1).Trim()
if (-not $SqlAlchemyRequirement) {
    throw "Missing SQLAlchemy requirement in $WindowsRequirements."
}
if (-not $AlembicRequirement) {
    throw "Missing alembic requirement in $WindowsRequirements."
}

# SQLAlchemy's greenlet dependency is not needed for this synchronous app, and
# greenlet does not currently provide a cp311-win32 wheel. Install SQLAlchemy,
# and Alembic's SQLAlchemy-facing package, without dependency resolution; then
# resolve the rest of the runtime normally.
Invoke-Native $PythonExe -m pip install --no-warn-script-location --no-deps $SqlAlchemyRequirement
Invoke-Native $PythonExe -m pip install --no-warn-script-location --no-deps $AlembicRequirement
$WindowsRequirementLines |
    Where-Object { $_ -notmatch "^\s*(SQLAlchemy|alembic)\s*(==|>=|<=|~=|!=|>|<)" } |
    Set-Content -Path $RuntimeRequirements -Encoding ASCII
Invoke-Native $PythonExe -m pip install --no-warn-script-location -r $RuntimeRequirements Mako

$PreviousDatabaseUrl = $env:DATABASE_URL
$PreviousFrontendDistDir = $env:FRONTEND_DIST_DIR
$PreviousDontWriteBytecode = $env:PYTHONDONTWRITEBYTECODE
$env:DATABASE_URL = "postgresql+pg8000://pos_dashboard:pos_dashboard@127.0.0.1:10001/pos_dashboard"
$env:FRONTEND_DIST_DIR = Join-Path $StageFrontend "dist"
$env:PYTHONDONTWRITEBYTECODE = "1"
try {
    Invoke-Native $PythonExe -c "import struct, pyodbc, fastapi, sqlalchemy, pg8000, uvicorn; from app.main import app; assert struct.calcsize('P') * 8 == 32; assert app.title; print('validated 32-bit runtime')"
}
finally {
    if ($null -ne $PreviousDatabaseUrl) {
        $env:DATABASE_URL = $PreviousDatabaseUrl
    }
    else {
        Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
    }

    if ($null -ne $PreviousFrontendDistDir) {
        $env:FRONTEND_DIST_DIR = $PreviousFrontendDistDir
    }
    else {
        Remove-Item Env:FRONTEND_DIST_DIR -ErrorAction SilentlyContinue
    }

    if ($null -ne $PreviousDontWriteBytecode) {
        $env:PYTHONDONTWRITEBYTECODE = $PreviousDontWriteBytecode
    }
    else {
        Remove-Item Env:PYTHONDONTWRITEBYTECODE -ErrorAction SilentlyContinue
    }
}

Copy-Item -Force (Join-Path $ScriptsDir "install-windows.ps1") (Join-Path $StageDir "install-windows.ps1")
Copy-Item -Force (Join-Path $ScriptsDir "run-dashboard.ps1") (Join-Path $StageDir "run-dashboard.ps1")
Copy-Item -Force (Join-Path $ScriptsDir "update-windows.ps1") (Join-Path $StageDir "update-windows.ps1")
Copy-Item -Force (Join-Path $ScriptsDir "set-pos-source.ps1") (Join-Path $StageDir "set-pos-source.ps1")

Set-Content -Path (Join-Path $StageDir "PACKAGE.txt") -Encoding ASCII -Value @(
    "Daily POS Dashboard Windows x86 package",
    "Built: $(Get-Date -Format o)",
    "Python: $PythonVersion 32-bit embeddable",
    "Frontend: prebuilt React assets served by FastAPI"
)

if (Test-Path $PackagePath) {
    Remove-Item -Force $PackagePath
}

Compress-Archive -Path (Join-Path $StageDir "*") -DestinationPath $PackagePath -Force
Write-Host "Created package: $PackagePath"
