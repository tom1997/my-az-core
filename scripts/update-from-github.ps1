[CmdletBinding()]
param(
    [ValidateSet('dev', 'release')][string]$Channel = 'dev',
    [ValidateSet('stable', 'enhanced')][string]$Profile,
    [string]$Branch,
    [string]$Repository = 'tom1997/my-az-core',
    [string]$SettingsPath,
    [switch]$Force,
    [switch]$NoStart,
    [switch]$VisibleWorld
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
Assert-SafeInstallRoot -Path $paths.Root

function Invoke-GhJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $json = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "GitHub 命令失败：$($json -join [Environment]::NewLine)" }
    return (($json -join "`n") | ConvertFrom-Json)
}

function Get-ManifestRevision {
    param([Parameter(Mandatory)][object]$Manifest)

    if ($Manifest.customModules -and $Manifest.customModules.Count -gt 0 -and $Manifest.customModules[0].revision) {
        return [string]$Manifest.customModules[0].revision
    }
    return [string]$Manifest.core.commit
}

function Read-ZipManifest {
    param([Parameter(Mandatory)][string]$ZipPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $archive.Entries | Where-Object { $_.FullName -eq 'source-manifest.json' } | Select-Object -First 1
        if (-not $entry) { throw '下载的运行包缺少 source-manifest.json。' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { return (($reader.ReadToEnd()) | ConvertFrom-Json) }
        finally { $reader.Dispose() }
    } finally {
        $archive.Dispose()
    }
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) { throw '找不到 GitHub CLI（gh.exe），无法自动下载构建。' }
& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI 尚未登录。请先运行 gh auth login。' }

$currentManifest = $null
$currentReleaseFile = Join-Path $paths.State 'current-release.txt'
if (Test-Path -LiteralPath $currentReleaseFile) {
    $currentRelease = (Get-Content -LiteralPath $currentReleaseFile -Raw).Trim()
    $currentManifestPath = Join-Path $currentRelease 'source-manifest.json'
    if (Test-Path -LiteralPath $currentManifestPath) {
        $currentManifest = Get-Content -LiteralPath $currentManifestPath -Raw | ConvertFrom-Json
    }
}

if (-not $Profile) {
    $Profile = if ($currentManifest -and $currentManifest.profile -in @('stable', 'enhanced')) {
        [string]$currentManifest.profile
    } else {
        'enhanced'
    }
}

$downloadRoot = Join-Path $paths.Root 'downloads\github-update'
if (Test-Path -LiteralPath $downloadRoot) { Remove-Item -LiteralPath $downloadRoot -Recurse -Force }
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

try {
    $updateRequired = $true
    if ($Channel -eq 'dev') {
        if (-not $Branch) {
            $Branch = (& git -C $repoRoot branch --show-current).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $Branch) { throw '无法识别当前 Git 分支，请使用 -Branch 指定。' }
        }

        $runs = @(Invoke-GhJson -Arguments @('run', 'list', '--repo', $Repository, '--workflow', 'dev-build',
                                             '--branch', $Branch, '--limit', '1',
                                             '--json', 'databaseId,status,conclusion,headSha,url,createdAt'))
        if ($runs.Count -eq 0) { throw "分支 $Branch 没有 dev-build 构建记录。" }
        $run = $runs[0]
        if ($run.status -ne 'completed') { throw "最新构建仍在进行：$($run.url)" }
        if ($run.conclusion -ne 'success') { throw "最新构建没有成功（$($run.conclusion)）：$($run.url)" }

        Write-Host "下载测试构建：$($run.headSha.Substring(0, 8))，$Profile，$Branch"
        & gh run download ([string]$run.databaseId) --repo $Repository --name "$Profile-windows" --dir $downloadRoot
        if ($LASTEXITCODE -ne 0) { throw '下载 GitHub Actions 构建失败。' }
    } else {
        $release = Invoke-GhJson -Arguments @('release', 'view', '--repo', $Repository, '--json', 'tagName')
        Write-Host "下载正式版本：$($release.tagName)，$Profile"
        & gh release download ([string]$release.tagName) --repo $Repository --pattern "$Profile-runtime.zip" `
            --pattern "$Profile-SHA256SUMS.txt" --dir $downloadRoot --clobber
        if ($LASTEXITCODE -ne 0) { throw '下载 GitHub Release 失败。' }
    }

    $package = Get-ChildItem -LiteralPath $downloadRoot -Filter "$Profile-runtime.zip" -File -Recurse |
        Select-Object -First 1
    $sums = Get-ChildItem -LiteralPath $downloadRoot -Filter "$Profile-SHA256SUMS.txt" -File -Recurse |
        Select-Object -First 1
    if (-not $package -or -not $sums) { throw '构建制品缺少运行包或 SHA-256 校验文件。' }

    $escapedName = [regex]::Escape($package.Name)
    $sumLine = Get-Content -LiteralPath $sums.FullName |
        Where-Object { $_ -match "(?i)^([0-9a-f]{64})\s+$escapedName$" } |
        Select-Object -First 1
    if (-not $sumLine) { throw "校验文件中找不到 $($package.Name)。" }
    $expectedHash = ([regex]::Match($sumLine, '(?i)^[0-9a-f]{64}')).Value.ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) { throw '运行包 SHA-256 校验失败，已停止更新。' }

    $newManifest = Read-ZipManifest -ZipPath $package.FullName
    $newRevision = Get-ManifestRevision -Manifest $newManifest
    if ($currentManifest) {
        $currentRevision = Get-ManifestRevision -Manifest $currentManifest
        if (-not $Force -and $currentRevision -eq $newRevision -and $currentManifest.profile -eq $newManifest.profile) {
            Write-Host "已经是当前构建：$($newRevision.Substring(0, 8))，无需更新。"
            $updateRequired = $false
        } else {
            Write-Host "准备更新：$($currentRevision.Substring(0, 8)) -> $($newRevision.Substring(0, 8))"
        }
    }

    if ($updateRequired) {
        & (Join-Path $PSScriptRoot 'update.ps1') -PackagePath $package.FullName -SettingsPath $SettingsPath
    }
} finally {
    if (Test-Path -LiteralPath $downloadRoot) { Remove-Item -LiteralPath $downloadRoot -Recurse -Force }
}

if (-not $NoStart) {
    & (Join-Path $PSScriptRoot 'start.ps1') -SettingsPath $SettingsPath -VisibleWorld:$VisibleWorld
}
