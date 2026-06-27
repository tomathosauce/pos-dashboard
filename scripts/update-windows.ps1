[CmdletBinding()]
param(
    [string]$InstallDir = $env:POS_DASHBOARD_INSTALL_DIR,
    [string]$Repo = $env:POS_DASHBOARD_REPO,
    [string]$RepoOwner = $env:POS_DASHBOARD_REPO_OWNER,
    [string]$RepoName = $env:POS_DASHBOARD_REPO_NAME,
    [string]$ReleaseTag = $env:POS_DASHBOARD_RELEASE_TAG,
    [string]$AssetName = $env:POS_DASHBOARD_ASSET_NAME,
    [string]$Ref = $env:POS_DASHBOARD_REF,
    [string]$PackagePath,
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
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

function Get-ScriptDirectory {
    if ($PSCommandPath) {
        return Split-Path -Parent $PSCommandPath
    }
    return $null
}

function New-GitHubHeaders {
    param([Parameter(Mandatory = $true)][string]$Accept)

    $Headers = @{
        Accept = $Accept
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "pos-dashboard-updater"
    }
    if ($GitHubToken) {
        $Headers["Authorization"] = "Bearer $GitHubToken"
    }
    return $Headers
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

function Resolve-UpdateDefaults {
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

    $script:ConfigPath = Join-Path $script:InstallDir "install-config.json"
    if (-not (Test-Path $script:ConfigPath)) {
        throw "Missing install config: $script:ConfigPath"
    }
    $script:Config = Get-Content -Raw -Path $script:ConfigPath | ConvertFrom-Json

    if (-not $RepoOwner) {
        $script:RepoOwner = [string](Get-ConfigValue -Config $script:Config -Name "repoOwner")
    }
    if (-not $RepoName) {
        $script:RepoName = [string](Get-ConfigValue -Config $script:Config -Name "repoName")
    }
    if ($Repo -and (-not $script:RepoOwner -or -not $script:RepoName)) {
        $RepoParts = $Repo.Trim().Trim("/") -split "/"
        if ($RepoParts.Count -ne 2 -or -not $RepoParts[0] -or -not $RepoParts[1]) {
            throw "POS_DASHBOARD_REPO or -Repo must be in owner/repo format."
        }
        $script:RepoOwner = $RepoParts[0]
        $script:RepoName = $RepoParts[1]
    }

    if (-not $ReleaseTag) {
        $SavedReleaseTag = [string](Get-ConfigValue -Config $script:Config -Name "releaseTag")
        $script:ReleaseTag = if ($SavedReleaseTag) { $SavedReleaseTag } else { "latest" }
    }
    if (-not $AssetName) {
        $SavedAssetName = [string](Get-ConfigValue -Config $script:Config -Name "assetName")
        $script:AssetName = if ($SavedAssetName) { $SavedAssetName } else { "pos-dashboard-windows-x86.zip" }
    }

    if (-not $PackagePath -and (-not $script:RepoOwner -or -not $script:RepoName)) {
        throw "Set -Repo owner/repo, -RepoOwner/-RepoName, or POS_DASHBOARD_REPO before updating."
    }
}

function Download-ReleaseAsset {
    param([Parameter(Mandatory = $true)][string]$Destination)

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
    $script:UpdatedFrom = if ($Release.tag_name) { "release:$($Release.tag_name)" } else { "release:$ReleaseTag" }
}

function Download-RefZipball {
    param([Parameter(Mandatory = $true)][string]$Destination)

    if (-not $Ref) {
        throw "Missing -Ref for ref zipball update."
    }

    $Headers = New-GitHubHeaders -Accept "application/vnd.github+json"
    $ZipUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/zipball/$Ref"
    Write-Step "Downloading repository zipball for ref $Ref"
    Invoke-WebRequest -Uri $ZipUrl -Headers $Headers -OutFile $Destination
    $script:UpdatedFrom = "ref:$Ref"
}

function Find-PackageRoot {
    param([Parameter(Mandatory = $true)][string]$ExtractDir)

    $Candidate = $ExtractDir
    if (-not (Test-Path (Join-Path $Candidate "backend"))) {
        $Children = Get-ChildItem -Path $ExtractDir -Directory
        if ($Children.Count -eq 1) {
            $Candidate = $Children[0].FullName
        }
    }

    $NestedCandidate = Join-Path $Candidate "pos-dashboard"
    if ((Test-Path (Join-Path $NestedCandidate "backend")) -and (Test-Path (Join-Path $NestedCandidate "frontend"))) {
        $Candidate = $NestedCandidate
    }

    foreach ($Required in @("backend", "frontend", "runtime")) {
        if (-not (Test-Path (Join-Path $Candidate $Required))) {
            throw "Update package is missing required directory '$Required'. Commit/ref updates must contain a prebuilt package layout, including runtime/python-x86 and frontend/dist."
        }
    }
    if (-not (Test-Path (Join-Path $Candidate "frontend\dist\index.html"))) {
        throw "Update package is missing frontend/dist/index.html."
    }
    if (-not (Test-Path (Join-Path $Candidate "runtime\python-x86\python.exe"))) {
        throw "Update package is missing runtime/python-x86/python.exe."
    }

    return $Candidate
}

function Stop-DashboardTask {
    $TaskName = [string](Get-ConfigValue -Config $Config -Name "taskName")
    if (-not $TaskName) {
        $TaskName = "POS Dashboard"
    }

    $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($Task) {
        Write-Step "Stopping scheduled task $TaskName"
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    return $TaskName
}

function Stop-DashboardProcess {
    $Port = [int](Get-ConfigValue -Config $Config -Name "port")
    if (-not $Port) {
        $Port = 8000
    }

    $Connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($Connection in $Connections) {
        $ProcessId = $Connection.OwningProcess
        if ($ProcessId -and $ProcessId -ne $PID) {
            Write-Step "Stopping dashboard process $ProcessId on port $Port"
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        }
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

    throw "Docker Desktop engine is not reachable from Docker CLI."
}

function Ensure-PostgresContainer {
    Start-DockerDesktopIfNeeded

    $ContainerName = [string](Get-ConfigValue -Config $Config -Name "postgresContainerName")
    if (-not $ContainerName) {
        $ContainerName = "pos-dashboard-postgres"
    }

    $Exists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
    if (-not $Exists) {
        throw "PostgreSQL container does not exist: $ContainerName. Run install-windows.ps1 first."
    }

    $Running = docker ps --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
    if (-not $Running) {
        Write-Step "Starting PostgreSQL container $ContainerName"
        Invoke-Native -FilePath docker -Arguments @("start", $ContainerName)
    }

    $Deadline = (Get-Date).AddSeconds(120)
    do {
        Start-Sleep -Seconds 2
        docker exec $ContainerName pg_isready -U pos_dashboard -d pos_dashboard *> $null
        if ($LASTEXITCODE -eq 0) {
            return
        }
    } while ((Get-Date) -lt $Deadline)

    throw "PostgreSQL container did not become ready: $ContainerName"
}

function Copy-PackageIntoInstall {
    param([Parameter(Mandatory = $true)][string]$PackageRoot)

    $BackupDir = Join-Path $InstallDir ("backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

    foreach ($Name in @("backend", "frontend", "runtime", "install-windows.ps1", "run-dashboard.ps1", "update-windows.ps1", "set-pos-source.ps1", "PACKAGE.txt")) {
        $CurrentPath = Join-Path $InstallDir $Name
        if (Test-Path $CurrentPath) {
            Move-Item -Force $CurrentPath (Join-Path $BackupDir $Name)
        }
    }

    foreach ($Name in @("backend", "frontend", "runtime")) {
        Copy-Item -Path (Join-Path $PackageRoot $Name) -Destination $InstallDir -Recurse -Force
    }
    foreach ($Name in @("install-windows.ps1", "run-dashboard.ps1", "update-windows.ps1", "set-pos-source.ps1", "PACKAGE.txt")) {
        $SourcePath = Join-Path $PackageRoot $Name
        if (Test-Path $SourcePath) {
            Copy-Item -Force $SourcePath (Join-Path $InstallDir $Name)
        }
    }

    Write-Host "Backup saved to: $BackupDir"
}

function Rewrite-BackendEnv {
    $BackendDir = Join-Path $InstallDir "backend"
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
    $PosSourcesJson = @($Source) | ConvertTo-Json -Compress

    Set-Content -Path (Join-Path $BackendDir ".env") -Encoding UTF8 -Value @(
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

function Run-Migrations {
    $BackendDir = Join-Path $InstallDir "backend"
    $PythonExe = Join-Path $InstallDir "runtime\python-x86\python.exe"
    if (-not (Test-Path $PythonExe)) {
        throw "Missing bundled Python runtime: $PythonExe"
    }
    & $PythonExe -c "import struct; raise SystemExit(0 if struct.calcsize('P') * 8 == 32 else 1)"
    if ($LASTEXITCODE -ne 0) {
        throw "Bundled Python is not 32-bit."
    }

    Push-Location $BackendDir
    try {
        Invoke-Native $PythonExe -m alembic upgrade head
    }
    finally {
        Pop-Location
    }
}

function Save-UpdatedConfig {
    $Config | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue (Get-Date).ToString("o") -Force
    $Config | Add-Member -NotePropertyName "updatedFrom" -NotePropertyValue $UpdatedFrom -Force
    $Config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

Resolve-UpdateDefaults

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pos-dashboard-update-" + [Guid]::NewGuid().ToString("N"))
$PackageZip = Join-Path $TempDir "update.zip"
$ExtractDir = Join-Path $TempDir "package"
New-Item -ItemType Directory -Force -Path $TempDir, $ExtractDir | Out-Null

try {
    if ($PackagePath) {
        Write-Step "Using local package $PackagePath"
        Copy-Item -Force $PackagePath $PackageZip
        $UpdatedFrom = "local:$PackagePath"
    }
    elseif ($Ref) {
        Download-RefZipball -Destination $PackageZip
    }
    else {
        Download-ReleaseAsset -Destination $PackageZip
    }

    Write-Step "Extracting update package"
    Expand-Archive -Path $PackageZip -DestinationPath $ExtractDir -Force
    $PackageRoot = Find-PackageRoot -ExtractDir $ExtractDir

    $TaskName = Stop-DashboardTask
    Stop-DashboardProcess

    Write-Step "Applying update"
    Copy-PackageIntoInstall -PackageRoot $PackageRoot
    Rewrite-BackendEnv
    Ensure-PostgresContainer
    Run-Migrations
    Save-UpdatedConfig

    if (-not $SkipRestart) {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Write-Step "Starting scheduled task $TaskName"
            Start-ScheduledTask -TaskName $TaskName
        }
        else {
            Write-Host "Task not found. Start manually: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\run-dashboard.ps1`""
        }
    }

    Write-Step "Update complete"
    $DashboardPort = [int](Get-ConfigValue -Config $Config -Name "port")
    if (-not $DashboardPort) {
        $DashboardPort = 8000
    }
    Write-Host "Updated from: $UpdatedFrom"
    Write-Host "Dashboard URL: http://127.0.0.1:$DashboardPort/"
}
finally {
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force $TempDir
    }
}
