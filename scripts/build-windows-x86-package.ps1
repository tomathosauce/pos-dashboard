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
# SQLAlchemy's greenlet extra is not needed for this synchronous app, and
# greenlet can force a compiler path on 32-bit Windows. Install SQLAlchemy
# first without dependencies, then let the remaining requirements resolve.
Invoke-Native $PythonExe -m pip install --no-warn-script-location --no-deps SQLAlchemy==2.0.36
Invoke-Native $PythonExe -m pip install --no-warn-script-location -r (Join-Path $StageBackend "requirements-windows-x86.txt")
Invoke-Native $PythonExe -c "import struct, pyodbc, fastapi, sqlalchemy, pg8000, uvicorn; assert struct.calcsize('P') * 8 == 32; print('validated 32-bit runtime')"

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
