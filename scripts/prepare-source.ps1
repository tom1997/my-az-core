[CmdletBinding()]
param(
    [ValidateSet('stable', 'enhanced')][string]$Profile = 'stable',
    [string]$WorkingRoot = 'C:\azbuild'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workingFull = [IO.Path]::GetFullPath($WorkingRoot).TrimEnd('\')
if ($workingFull -notmatch '^[A-Za-z]:\\[^\\]+') { throw "不安全的工作目录：$workingFull" }
$sourceRoot = Join-Path $workingFull 'source'

if (Test-Path -LiteralPath $workingFull) { Remove-Item -LiteralPath $workingFull -Recurse -Force }
New-Item -ItemType Directory -Path $workingFull | Out-Null
$lock = Get-Content -LiteralPath (Join-Path $repoRoot 'upstreams.lock.json') -Raw | ConvertFrom-Json

function Get-LockedRepository {
    param([object]$Entry, [string]$Destination)
    Write-Host "获取 $($Entry.name) @ $($Entry.commit)"
    git clone --filter=blob:none --no-checkout --single-branch --branch $Entry.branch $Entry.repository $Destination
    if ($LASTEXITCODE -ne 0) { throw "克隆 $($Entry.name) 失败。" }
    git -C $Destination checkout --detach $Entry.commit
    if ($LASTEXITCODE -ne 0) { throw "检出 $($Entry.name) 锁定版本失败。" }
}

Get-LockedRepository -Entry $lock.core -Destination $sourceRoot
foreach ($module in $lock.modules | Where-Object { $_.profiles -contains $Profile }) {
    Get-LockedRepository -Entry $module -Destination (Join-Path $sourceRoot "modules\$($module.name)")
}

$customRoot = Join-Path $repoRoot 'modules\custom'
foreach ($moduleDir in Get-ChildItem -LiteralPath $customRoot -Directory -ErrorAction SilentlyContinue) {
    Copy-Item -LiteralPath $moduleDir.FullName -Destination (Join-Path $sourceRoot "modules\$($moduleDir.Name)") -Recurse
}

foreach ($patch in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'patches') -Filter '*.patch' -File | Sort-Object Name) {
    git -C $sourceRoot apply --check $patch.FullName
    if ($LASTEXITCODE -ne 0) { throw "补丁检查失败：$($patch.Name)" }
    git -C $sourceRoot apply $patch.FullName
    if ($LASTEXITCODE -ne 0) { throw "补丁应用失败：$($patch.Name)" }
}

Copy-Item -LiteralPath (Join-Path $repoRoot 'upstreams.lock.json') -Destination (Join-Path $workingFull 'upstreams.lock.json')
Write-Host "源码准备完成：$sourceRoot"
