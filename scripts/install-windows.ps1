[CmdletBinding()]
param(
    [string]$Repo = $env:POS_DASHBOARD_REPO,
    [string]$RepoOwner = $env:POS_DASHBOARD_REPO_OWNER,
    [string]$RepoName = $env:POS_DASHBOARD_REPO_NAME,
    [string]$ReleaseTag = $env:POS_DASHBOARD_RELEASE_TAG,
    [string]$AssetName = $env:POS_DASHBOARD_ASSET_NAME,
    [string]$PackagePath,
    [string]$InstallDir = $env:POS_DASHBOARD_INSTALL_DIR,
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [string]$PosSourcePath = $env:POS_DASHBOARD_SOURCE_PATH,
    [string]$SourceName = $env:POS_DASHBOARD_SOURCE_NAME,
    [ValidateSet("odbc")][string]$Reader = "odbc",
    [string]$OdbcDsn = $env:POS_DASHBOARD_ODBC_DSN,
    [string]$OdbcConnectionString = $env:POS_DASHBOARD_ODBC_CONNECTION_STRING,
    [int]$Port = $(if ($env:POS_DASHBOARD_PORT) { [int]$env:POS_DASHBOARD_PORT } else { 8000 }),
    [string]$TaskName = $(if ($env:POS_DASHBOARD_TASK_NAME) { $env:POS_DASHBOARD_TASK_NAME } else { "POS Dashboard" }),
    [string]$PostgresContainerName = $(if ($env:POS_DASHBOARD_POSTGRES_CONTAINER) { $env:POS_DASHBOARD_POSTGRES_CONTAINER } else { "pos-dashboard-postgres" }),
    [string]$PostgresVolumeName = $(if ($env:POS_DASHBOARD_POSTGRES_VOLUME) { $env:POS_DASHBOARD_POSTGRES_VOLUME } else { "pos-dashboard-postgres-data" }),
    [int]$PostgresPort = $(if ($env:POS_DASHBOARD_POSTGRES_PORT) { [int]$env:POS_DASHBOARD_POSTGRES_PORT } else { 5432 }),
    [string]$PostgresPassword,
    [switch]$SkipTask
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

function Set-TextFileNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Lines
    )

    $Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $Encoding)
}

function Expand-PackageArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (Test-Path $DestinationPath) {
        Remove-Item -Recurse -Force $DestinationPath
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationPath)
}

function New-LocalPassword {
    $Chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789".ToCharArray()
    -join (1..32 | ForEach-Object { $Chars | Get-Random })
}

function Resolve-InstallDefaults {
    $CurrentDirectory = (Get-Location).Path

    if (-not $ReleaseTag) {
        $script:ReleaseTag = "latest"
    }
    if (-not $AssetName) {
        $script:AssetName = "pos-dashboard-windows-x86.zip"
    }
    if (-not $InstallDir) {
        $script:InstallDir = $CurrentDirectory
    }
    if (-not $PosSourcePath) {
        $script:PosSourcePath = $CurrentDirectory
    }
    if (-not $SourceName) {
        $script:SourceName = "main"
    }

    if ($Repo -and (-not $RepoOwner -or -not $RepoName)) {
        $RepoParts = $Repo.Trim().Trim("/") -split "/"
        if ($RepoParts.Count -ne 2 -or -not $RepoParts[0] -or -not $RepoParts[1]) {
            throw "POS_DASHBOARD_REPO or -Repo must be in owner/repo format."
        }
        $script:RepoOwner = $RepoParts[0]
        $script:RepoName = $RepoParts[1]
    }

    if (-not $PackagePath -and (-not $RepoOwner -or -not $RepoName)) {
        throw "Set -Repo owner/repo, -RepoOwner/-RepoName, or POS_DASHBOARD_REPO before running the installer."
    }
}

function New-GitHubHeaders {
    param([Parameter(Mandatory = $true)][string]$Accept)

    $Headers = @{
        Accept = $Accept
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "pos-dashboard-installer"
    }
    if ($GitHubToken) {
        $Headers["Authorization"] = "Bearer $GitHubToken"
    }
    return $Headers
}

function Download-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $Headers = New-GitHubHeaders -Accept "application/vnd.github+json"

    if ($ReleaseTag -eq "latest") {
        $ReleaseUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    }
    else {
        $ReleaseUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/$ReleaseTag"
    }

    Write-Step "Downloading release metadata from GitHub"
    $Release = Invoke-RestMethod -Uri $ReleaseUrl -Headers $Headers
    $Asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if (-not $Asset) {
        throw "Release asset not found: $AssetName"
    }

    $DownloadHeaders = New-GitHubHeaders -Accept "application/octet-stream"
    if ($GitHubToken) {
        Invoke-WebRequest -Uri $Asset.url -Headers $DownloadHeaders -OutFile $Destination
    }
    else {
        Invoke-WebRequest -Uri $Asset.browser_download_url -Headers $DownloadHeaders -OutFile $Destination
    }
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
        Write-Step "Starting Docker Desktop"
        Start-Process -FilePath $DockerDesktop | Out-Null
    }
    else {
        Write-Step "Waiting for Docker Desktop engine"
    }

    $Deadline = (Get-Date).AddSeconds(180)
    do {
        Start-Sleep -Seconds 3
        if ((Use-DockerDesktopContextIfAvailable) -and (Test-DockerEngineReady)) {
            return
        }
    } while ((Get-Date) -lt $Deadline)

    throw "Docker Desktop engine is not reachable from Docker CLI. Start Docker Desktop, wait until the Linux engine is running, then rerun this installer."
}

function Get-ExistingContainerPassword {
    param([Parameter(Mandatory = $true)][string]$ContainerName)

    $Exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
    if (-not $Exists) {
        return $null
    }

    $EnvLines = docker inspect --format "{{range .Config.Env}}{{println .}}{{end}}" $ContainerName
    $PasswordLine = $EnvLines | Where-Object { $_ -like "POSTGRES_PASSWORD=*" } | Select-Object -First 1
    if ($PasswordLine) {
        return $PasswordLine.Substring("POSTGRES_PASSWORD=".Length)
    }
    return $null
}

function Ensure-PostgresContainer {
    Start-DockerDesktopIfNeeded

    $Exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $PostgresContainerName }
    if ($Exists) {
        $Running = docker ps --format "{{.Names}}" | Where-Object { $_ -eq $PostgresContainerName }
        if (-not $Running) {
            Write-Step "Starting existing PostgreSQL container"
            Invoke-Native -FilePath docker -Arguments @("start", $PostgresContainerName)
        }
    }
    else {
        Write-Step "Creating PostgreSQL container"
        $DockerRunArgs = @(
            "run", "-d",
            "--name", $PostgresContainerName,
            "-e", "POSTGRES_DB=pos_dashboard",
            "-e", "POSTGRES_USER=pos_dashboard",
            "-e", "POSTGRES_PASSWORD=$PostgresPassword",
            "-p", "127.0.0.1:$PostgresPort`:5432",
            "-v", "$PostgresVolumeName`:/var/lib/postgresql/data",
            "postgres:16-alpine"
        )
        Invoke-Native -FilePath docker -Arguments $DockerRunArgs
    }

    $Deadline = (Get-Date).AddSeconds(120)
    do {
        Start-Sleep -Seconds 2
        docker exec $PostgresContainerName pg_isready -U pos_dashboard -d pos_dashboard *> $null
        if ($LASTEXITCODE -eq 0) {
            return
        }
    } while ((Get-Date) -lt $Deadline)

    throw "PostgreSQL container did not become ready: $PostgresContainerName"
}

function Write-BackendEnv {
    param(
        [Parameter(Mandatory = $true)][string]$BackendDir,
        [Parameter(Mandatory = $true)][string]$FrontendDistDir
    )

    $EscapedPassword = [Uri]::EscapeDataString($PostgresPassword)
    $DatabaseUrl = "postgresql+pg8000://pos_dashboard:$EscapedPassword@127.0.0.1:$PostgresPort/pos_dashboard"

    $Source = [ordered]@{
        name = $SourceName
        path = $PosSourcePath
        reader = $Reader
        timezone = "America/Bogota"
        currency = "USD"
        odbc_connection_string = if ($OdbcConnectionString) { $OdbcConnectionString } else { $null }
        odbc_dsn = if ($OdbcDsn) { $OdbcDsn } else { $null }
    }
    $PosSourcesJson = ConvertTo-Json -InputObject @($Source) -Compress

    $EnvPath = Join-Path $BackendDir ".env"
    Set-TextFileNoBom -Path $EnvPath -Lines @(
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

function Register-DashboardTask {
    param([Parameter(Mandatory = $true)][string]$RunScript)

    Write-Step "Registering Task Scheduler autostart"
    $Action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RunScript`""
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Trigger.Delay = "PT30S"
    $Principal = New-ScheduledTaskPrincipal `
        -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive `
        -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Days 0)

    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $Action `
            -Trigger $Trigger `
            -Principal $Principal `
            -Settings $Settings `
            -Force | Out-Null
    }
    catch {
        Write-Warning "Could not register scheduled task '$TaskName': $($_.Exception.Message)"
        Write-Warning "The dashboard is installed, but autostart was not configured. Use the manual run command below, or rerun this installer from an elevated PowerShell window."
    }
}

Resolve-InstallDefaults
Assert-Command docker

if (-not (Test-Path $PosSourcePath)) {
    throw "POS source path does not exist: $PosSourcePath"
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pos-dashboard-install-" + [Guid]::NewGuid().ToString("N"))
$PackageZip = Join-Path $TempDir $AssetName
$ExtractDir = Join-Path $TempDir "package"
New-Item -ItemType Directory -Force -Path $TempDir, $ExtractDir | Out-Null

try {
    if ($PackagePath) {
        Write-Step "Using local package $PackagePath"
        Copy-Item -Force $PackagePath $PackageZip
    }
    else {
        Download-ReleaseAsset -Destination $PackageZip
    }

    Write-Step "Extracting package"
    Expand-PackageArchive -ArchivePath $PackageZip -DestinationPath $ExtractDir

    Write-Step "Installing files to $InstallDir"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($Name in @("backend", "frontend", "runtime")) {
        $TargetPath = Join-Path $InstallDir $Name
        if (Test-Path $TargetPath) {
            Remove-Item -Recurse -Force $TargetPath
        }
    }
    Copy-Item -Path (Join-Path $ExtractDir "*") -Destination $InstallDir -Recurse -Force

    $BundledPython = Join-Path $InstallDir "runtime\python-x86\python.exe"
    if (-not (Test-Path $BundledPython)) {
        throw "Package is missing bundled Python: $BundledPython"
    }
    & $BundledPython -c "import struct; raise SystemExit(0 if struct.calcsize('P') * 8 == 32 else 1)"
    if ($LASTEXITCODE -ne 0) {
        throw "Bundled Python is not 32-bit."
    }

    if (-not $PostgresPassword) {
        $ExistingConfigPath = Join-Path $InstallDir "install-config.json"
        if (Test-Path $ExistingConfigPath) {
            $ExistingConfig = Get-Content -Raw -Path $ExistingConfigPath | ConvertFrom-Json
            $PasswordProperty = $ExistingConfig.PSObject.Properties["postgresPassword"]
            if ($PasswordProperty -and $PasswordProperty.Value) {
                $PostgresPassword = [string]$PasswordProperty.Value
            }
        }
    }
    if (-not $PostgresPassword) {
        $ExistingPassword = Get-ExistingContainerPassword -ContainerName $PostgresContainerName
        if ($ExistingPassword) {
            $PostgresPassword = $ExistingPassword
        }
    }
    if (-not $PostgresPassword) {
        $PostgresPassword = New-LocalPassword
    }

    Ensure-PostgresContainer

    $BackendDir = Join-Path $InstallDir "backend"
    $FrontendDistDir = Join-Path $InstallDir "frontend\dist"
    Write-BackendEnv -BackendDir $BackendDir -FrontendDistDir $FrontendDistDir

    $InstallConfigPath = Join-Path $InstallDir "install-config.json"
    [ordered]@{
        host = "0.0.0.0"
        port = $Port
        repoOwner = $RepoOwner
        repoName = $RepoName
        releaseTag = $ReleaseTag
        assetName = $AssetName
        posSourcePath = $PosSourcePath
        sourceName = $SourceName
        reader = $Reader
        odbcDsn = $OdbcDsn
        odbcConnectionString = $OdbcConnectionString
        taskName = $TaskName
        postgresContainerName = $PostgresContainerName
        postgresVolumeName = $PostgresVolumeName
        postgresPort = $PostgresPort
        postgresPassword = $PostgresPassword
        installedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json | Set-Content -Path $InstallConfigPath -Encoding UTF8

    Write-Step "Running migrations"
    Push-Location $BackendDir
    try {
        Invoke-Native $BundledPython -m alembic upgrade head
    }
    finally {
        Pop-Location
    }

    $RunScript = Join-Path $InstallDir "run-dashboard.ps1"
    if (-not $SkipTask) {
        Register-DashboardTask -RunScript $RunScript
    }

    Write-Step "Install complete"
    Write-Host "Dashboard URL: http://127.0.0.1:$Port/"
    Write-Host "Run manually: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$RunScript`""
}
finally {
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force $TempDir
    }
}
