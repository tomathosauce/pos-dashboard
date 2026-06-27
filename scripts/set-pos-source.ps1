[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Path,
    [string]$InstallDir = $env:POS_DASHBOARD_INSTALL_DIR,
    [string]$SourceName,
    [ValidateSet("odbc")][string]$Reader = "odbc",
    [string]$OdbcDsn,
    [string]$OdbcConnectionString,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Get-ScriptDirectory {
    if ($PSCommandPath) {
        return Split-Path -Parent $PSCommandPath
    }
    return $null
}

function Set-TextFileNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Lines
    )

    $Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $Encoding)
}

function Get-ConfigValue {
    param(
        [object]$Config,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $Property = $Config.PSObject.Properties[$Name]
    if ($Property) {
        return $Property.Value
    }
    return $null
}

function Set-ConfigValue {
    param(
        [object]$Config,
        [Parameter(Mandatory = $true)][string]$Name,
        [object]$Value
    )
    $Config | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Resolve-InstallDir {
    $ScriptDirectory = Get-ScriptDirectory
    if (-not $InstallDir) {
        if ($ScriptDirectory -and (Test-Path (Join-Path $ScriptDirectory "install-config.json"))) {
            $script:InstallDir = $ScriptDirectory
        }
        else {
            $script:InstallDir = (Get-Location).Path
        }
    }
    $script:InstallDir = [System.IO.Path]::GetFullPath($script:InstallDir)
}

function Rewrite-BackendEnv {
    param([Parameter(Mandatory = $true)][object]$Config)

    $BackendDir = Join-Path $InstallDir "backend"
    if (-not (Test-Path $BackendDir)) {
        throw "Missing backend directory: $BackendDir"
    }

    $FrontendDistDir = Join-Path $InstallDir "frontend\dist"
    $Password = [string](Get-ConfigValue -Config $Config -Name "postgresPassword")
    $PostgresPort = [int](Get-ConfigValue -Config $Config -Name "postgresPort")
    if (-not $PostgresPort) {
        $PostgresPort = 5432
    }
    $Port = [int](Get-ConfigValue -Config $Config -Name "port")
    if (-not $Port) {
        $Port = 8000
    }

    $EscapedPassword = [Uri]::EscapeDataString($Password)
    $DatabaseUrl = "postgresql+pg8000://pos_dashboard:$EscapedPassword@127.0.0.1:$PostgresPort/pos_dashboard"
    $Source = [ordered]@{
        name = [string](Get-ConfigValue -Config $Config -Name "sourceName")
        path = [string](Get-ConfigValue -Config $Config -Name "posSourcePath")
        reader = [string](Get-ConfigValue -Config $Config -Name "reader")
        timezone = "America/Bogota"
        currency = "USD"
        odbc_connection_string = Get-ConfigValue -Config $Config -Name "odbcConnectionString"
        odbc_dsn = Get-ConfigValue -Config $Config -Name "odbcDsn"
    }
    if (-not $Source.name) {
        $Source.name = "main"
    }
    if (-not $Source.reader) {
        $Source.reader = "odbc"
    }
    $PosSourcesJson = ConvertTo-Json -InputObject @($Source) -Compress

    Set-TextFileNoBom -Path (Join-Path $BackendDir ".env") -Lines @(
        "DATABASE_URL=$DatabaseUrl",
        "API_CORS_ORIGINS=http://localhost:$Port,http://127.0.0.1:$Port",
        "ENABLE_SCHEDULER=true",
        "DAILY_SYNC_HOUR=8",
        "DAILY_SYNC_MINUTE=0",
        "DEFAULT_TIMEZONE=America/Bogota",
        "DEFAULT_CURRENCY=USD",
        "FRONTEND_DIST_DIR=$FrontendDistDir",
        "POS_SOURCES_JSON=$PosSourcesJson"
    )
}

function Restart-DashboardTask {
    param([Parameter(Mandatory = $true)][object]$Config)

    $TaskName = [string](Get-ConfigValue -Config $Config -Name "taskName")
    if (-not $TaskName) {
        $TaskName = "POS Dashboard"
    }

    $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($Task) {
        Write-Step "Restarting scheduled task $TaskName"
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-ScheduledTask -TaskName $TaskName
    }
    else {
        Write-Host "Task not found. Start manually: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\run-dashboard.ps1`""
    }
}

Resolve-InstallDir

if (-not $Path) {
    $Path = Read-Host "Paradox database folder"
}
$ResolvedPath = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path $ResolvedPath)) {
    throw "Paradox database folder does not exist: $ResolvedPath"
}

$ConfigPath = Join-Path $InstallDir "install-config.json"
if (-not (Test-Path $ConfigPath)) {
    throw "Missing install config: $ConfigPath"
}
$Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

if (-not $SourceName) {
    $SourceName = [string](Get-ConfigValue -Config $Config -Name "sourceName")
    if (-not $SourceName) {
        $SourceName = "main"
    }
}
if (-not $OdbcDsn) {
    $OdbcDsn = [string](Get-ConfigValue -Config $Config -Name "odbcDsn")
}
if (-not $OdbcConnectionString) {
    $OdbcConnectionString = [string](Get-ConfigValue -Config $Config -Name "odbcConnectionString")
}

Set-ConfigValue -Config $Config -Name "posSourcePath" -Value $ResolvedPath
Set-ConfigValue -Config $Config -Name "sourceName" -Value $SourceName
Set-ConfigValue -Config $Config -Name "reader" -Value $Reader
Set-ConfigValue -Config $Config -Name "odbcDsn" -Value $OdbcDsn
Set-ConfigValue -Config $Config -Name "odbcConnectionString" -Value $OdbcConnectionString
Set-ConfigValue -Config $Config -Name "sourceUpdatedAt" -Value (Get-Date).ToString("o")

$Config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
Rewrite-BackendEnv -Config $Config

Write-Step "POS source updated"
Write-Host "Install directory: $InstallDir"
Write-Host "Source name: $SourceName"
Write-Host "Paradox folder: $ResolvedPath"

if (-not $NoRestart) {
    Restart-DashboardTask -Config $Config
}
