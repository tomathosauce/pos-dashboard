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

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $Line | Tee-Object -FilePath $LogPath -Append
}

function Start-DockerDesktopIfNeeded {
    if (docker info *> $null) {
        return
    }

    $DockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path $DockerDesktop) {
        Write-Log "Starting Docker Desktop."
        Start-Process -FilePath $DockerDesktop | Out-Null
    }

    $Deadline = (Get-Date).AddSeconds(120)
    do {
        Start-Sleep -Seconds 3
        if (docker info *> $null) {
            return
        }
    } while ((Get-Date) -lt $Deadline)

    throw "Docker Desktop is not running or Docker CLI is unavailable."
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
    & $PythonExe -m alembic upgrade head *>> $LogPath
    if ($LASTEXITCODE -ne 0) {
        throw "Alembic migration failed with exit code $LASTEXITCODE."
    }

    $HostName = [string]$Config.host
    $Port = [int]$Config.port
    Write-Log "Starting FastAPI on $HostName`:$Port."
    & $PythonExe -m uvicorn app.main:app --host $HostName --port $Port *>> $LogPath
    if ($LASTEXITCODE -ne 0) {
        throw "Uvicorn exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
