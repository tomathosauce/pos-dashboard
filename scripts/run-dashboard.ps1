[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$InstallRoot = Split-Path -Parent $PSCommandPath
$ConfigPath = Join-Path $InstallRoot "install-config.json"
$BackendDir = Join-Path $InstallRoot "backend"
$PythonExe = Join-Path $InstallRoot "runtime\python-x86\python.exe"
$LogDir = Join-Path $InstallRoot "logs"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (-not (Test-Path $ConfigPath)) {
    throw "Missing install config: $ConfigPath"
}
if (-not (Test-Path $PythonExe)) {
    throw "Missing bundled 32-bit Python runtime: $PythonExe"
}

$Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$LogPath = Join-Path $LogDir ("dashboard-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$LogEncoding = New-Object System.Text.UTF8Encoding($false)

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $Line
    [System.IO.File]::AppendAllText($LogPath, "$Line`r`n", $LogEncoding)
}

function ConvertTo-CmdArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '[\s&()^|<>"]') {
        return $Value
    }

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-NativeLogged {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $CommandParts = @($FilePath) + $Arguments | ForEach-Object {
        ConvertTo-CmdArgument -Value $_
    }
    $Command = "{0} >> {1} 2>&1" -f ($CommandParts -join " "), (ConvertTo-CmdArgument -Value $LogPath)
    & $env:ComSpec /d /s /c $Command
    return $LASTEXITCODE
}

function Test-DockerEngineReady {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & docker info *> $null
        return $LASTEXITCODE -eq 0
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
}

function Use-DockerDesktopContextIfAvailable {
    if ($env:DOCKER_CONTEXT -eq "desktop-linux") {
        return $true
    }

    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & docker context inspect desktop-linux *> $null
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    $env:DOCKER_CONTEXT = "desktop-linux"
    return $true
}

function Start-DockerDesktopIfNeeded {
    if (Test-DockerEngineReady) {
        return
    }

    if ((Use-DockerDesktopContextIfAvailable) -and (Test-DockerEngineReady)) {
        return
    }

    $DockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    $DockerDesktopRunning = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if ((-not $DockerDesktopRunning) -and (Test-Path $DockerDesktop)) {
        Write-Log "Starting Docker Desktop."
        Start-Process -FilePath $DockerDesktop | Out-Null
    }
    else {
        Write-Log "Waiting for Docker Desktop engine."
    }

    $Deadline = (Get-Date).AddSeconds(120)
    do {
        Start-Sleep -Seconds 3
        if ((Use-DockerDesktopContextIfAvailable) -and (Test-DockerEngineReady)) {
            return
        }
    } while ((Get-Date) -lt $Deadline)

    throw "Docker Desktop engine is not reachable from Docker CLI."
}

function Ensure-PostgresContainer {
    Start-DockerDesktopIfNeeded

    $ContainerName = [string]$Config.postgresContainerName
    $Exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
    if ($Exists) {
        $Running = docker ps --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
        if (-not $Running) {
            Write-Log "Starting PostgreSQL container $ContainerName."
            docker start $ContainerName | Out-Null
        }
    }

    $Deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Seconds 2
        docker exec $ContainerName pg_isready -U pos_dashboard -d pos_dashboard *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "PostgreSQL container is ready."
            return
        }
    } while ((Get-Date) -lt $Deadline)

    throw "PostgreSQL container did not become ready: $ContainerName"
}

Write-Log "Starting POS Dashboard."
Ensure-PostgresContainer

Push-Location $BackendDir
try {
    Write-Log "Running database migrations."
    $ExitCode = Invoke-NativeLogged -FilePath $PythonExe -Arguments @("-m", "alembic", "upgrade", "head")
    if ($ExitCode -ne 0) {
        throw "Alembic migration failed with exit code $ExitCode."
    }

    $HostName = [string]$Config.host
    $Port = [int]$Config.port
    Write-Log "Starting FastAPI on $HostName`:$Port."
    $ExitCode = Invoke-NativeLogged -FilePath $PythonExe -Arguments @("-m", "uvicorn", "app.main:app", "--host", $HostName, "--port", [string]$Port)
    if ($ExitCode -ne 0) {
        throw "Uvicorn exited with code $ExitCode."
    }
}
finally {
    Pop-Location
}
