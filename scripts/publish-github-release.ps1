[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Title,
    [string]$Notes,
    [string]$Repo = $env:POS_DASHBOARD_REPO,
    [string]$Remote = "origin",
    [string]$PythonVersion = "3.11.9",
    [string]$PackageName = "pos-dashboard-windows-x86.zip",
    [switch]$Draft,
    [switch]$Prerelease,
    [switch]$SkipFrontendBuild,
    [switch]$SkipBuild,
    [switch]$AllowDirty,
    [switch]$ClobberAsset
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PackageScript = Join-Path $PSScriptRoot "build-windows-x86-package.ps1"
$ReleaseDir = Join-Path $ProjectRoot "release"
$PackagePath = Join-Path $ReleaseDir $PackageName

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
        [string[]]$Arguments = @()
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $Output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    return ($Output -join "`n").Trim()
}

function Get-OriginRepo {
    $RemoteUrl = Invoke-GitText -Arguments @("remote", "get-url", $Remote)
    if ($RemoteUrl -match "github\.com[:/](?<owner>[^/]+)/(?<name>[^/.]+)(\.git)?$") {
        return "$($Matches.owner)/$($Matches.name)"
    }
    throw "Could not infer owner/repo from remote '$Remote' URL: $RemoteUrl. Pass -Repo owner/repo."
}

Assert-Command git
Assert-Command gh

Push-Location $ProjectRoot
try {
    $HeadSha = Invoke-GitText -Arguments @("rev-parse", "HEAD")
    $ShortSha = Invoke-GitText -Arguments @("rev-parse", "--short", "HEAD")

    if (-not $AllowDirty) {
        $Status = Invoke-GitText -Arguments @("status", "--porcelain")
        if ($Status) {
            throw "Working tree has uncommitted changes. Commit them first so the release is from the current commit, or pass -AllowDirty."
        }
    }

    if (-not $Repo) {
        $Repo = Get-OriginRepo
    }

    if (-not $Title) {
        $Title = "POS Dashboard $Tag"
    }
    if (-not $Notes) {
        $Notes = "Windows x86 self-contained dashboard release built from commit $ShortSha."
    }

    if ($SkipBuild) {
        Write-Step "Using existing Windows x86 release package"
        if (-not (Test-Path $PackagePath)) {
            throw "Package does not exist: $PackagePath. Run $PackageScript first, or omit -SkipBuild."
        }
    }
    else {
        Write-Step "Building Windows x86 release package"
        $BuildArgs = @(
            "-PythonVersion", $PythonVersion,
            "-PackageName", $PackageName,
            "-OutputDir", $ReleaseDir
        )
        if ($SkipFrontendBuild) {
            $BuildArgs += "-SkipFrontendBuild"
        }
        $PowerShellArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PackageScript) + $BuildArgs
        Invoke-Native -FilePath "powershell.exe" -Arguments $PowerShellArgs

        if (-not (Test-Path $PackagePath)) {
            throw "Package was not created: $PackagePath"
        }
    }

    Write-Step "Preparing release tag $Tag"
    $ExistingTagSha = ""
    & git rev-parse -q --verify "refs/tags/$Tag" *> $null
    if ($LASTEXITCODE -eq 0) {
        $ExistingTagSha = Invoke-GitText -Arguments @("rev-list", "-n", "1", $Tag)
        if ($ExistingTagSha -ne $HeadSha) {
            throw "Local tag $Tag points to $ExistingTagSha, not current commit $HeadSha."
        }
    }
    else {
        Invoke-Native -FilePath "git" -Arguments @("tag", $Tag, $HeadSha)
    }

    Invoke-Native -FilePath "git" -Arguments @("push", $Remote, $Tag)

    Write-Step "Publishing GitHub Release"
    $ReleaseExists = $false
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & gh release view $Tag --repo $Repo *> $null
        if ($LASTEXITCODE -eq 0) {
            $ReleaseExists = $true
        }
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($ReleaseExists) {
        Write-Step "Release exists; uploading asset"
        $UploadArgs = @("release", "upload", $Tag, $PackagePath, "--repo", $Repo)
        if ($ClobberAsset) {
            $UploadArgs += "--clobber"
        }
        Invoke-Native -FilePath "gh" -Arguments $UploadArgs
    }
    else {
        $CreateArgs = @(
            "release", "create", $Tag,
            $PackagePath,
            "--repo", $Repo,
            "--target", $HeadSha,
            "--title", $Title,
            "--notes", $Notes
        )
        if ($Draft) {
            $CreateArgs += "--draft"
        }
        if ($Prerelease) {
            $CreateArgs += "--prerelease"
        }
        Invoke-Native -FilePath "gh" -Arguments $CreateArgs
    }

    Write-Step "Release complete"
    Write-Host "Repo: $Repo"
    Write-Host "Tag: $Tag"
    Write-Host "Commit: $HeadSha"
    Write-Host "Asset: $PackagePath"
}
finally {
    Pop-Location
}
