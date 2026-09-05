[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$lockPath = Join-Path $repoRoot 'upstreams.lock.json'
$defaultsPath = Join-Path $repoRoot 'runtime.defaults.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$defaults = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json

if ($lock.schemaVersion -ne 1) { throw 'upstreams.lock.json schemaVersion 必须为 1。' }
if ($defaults.schemaVersion -ne 1) { throw 'runtime.defaults.json schemaVersion 必须为 1。' }
if ($lock.core.commit -notmatch '^[0-9a-f]{40}$') { throw 'Core commit 不是完整 SHA。' }

$names = @{}
foreach ($module in $lock.modules) {
    if ($module.commit -notmatch '^[0-9a-f]{40}$') { throw "$($module.name) commit 不是完整 SHA。" }
    if ($names.ContainsKey($module.name)) { throw "模块名称重复：$($module.name)" }
    $names[$module.name] = $true
    foreach ($profile in $module.profiles) {
        if ($profile -notin @('stable', 'enhanced')) { throw "$($module.name) 包含未知 profile：$profile" }
    }
}

foreach ($patch in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'patches') -Filter '*.patch' -File -ErrorAction SilentlyContinue) {
    if ($patch.Name -notmatch '^\d{4}-[a-z0-9][a-z0-9-]*\.patch$') {
        throw "补丁文件名必须采用 0001-description.patch 格式：$($patch.Name)"
    }
}

$sqlFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'modules\custom') -Filter '*.sql' -File -Recurse -ErrorAction SilentlyContinue)
foreach ($file in $sqlFiles) {
    $relative = [IO.Path]::GetRelativePath($repoRoot, $file.FullName).Replace('\', '/')
    if ($relative -notmatch '/data/sql/db-(auth|characters|world)/') {
        throw "SQL 必须位于模块的 data/sql/db-* 目录：$relative"
    }
    $sql = Get-Content -LiteralPath $file.FullName -Raw
    if ($sql -match '(?im)^\s*(DROP\s+(DATABASE|TABLE)|TRUNCATE\s+TABLE)\b') {
        throw "自定义 SQL 包含破坏性语句：$relative"
    }
}

$mythicRewards = Join-Path $repoRoot 'modules\custom\mod-mythic-rewards'
if (Test-Path -LiteralPath $mythicRewards) {
    $bridgePatch = Join-Path $repoRoot 'patches\0002-mythic-rewards-bridge.patch'
    if (-not (Test-Path -LiteralPath $bridgePatch)) { throw 'mod-mythic-rewards 缺少 Mythic Plus 桥接补丁。' }
    $bridge = Get-Content -LiteralPath $bridgePatch -Raw
    if ($bridge -notmatch 'RewardMythicEquipment') { throw 'Mythic Plus 桥接补丁未调用 RewardMythicEquipment。' }
    foreach ($required in @(
        'conf\mod_mythic_rewards.conf.dist',
        'data\sql\db-world\mod_mythic_rewards.sql',
        'data\sql\db-characters\mod_mythic_rewards.sql',
        'src\mod_mythic_rewards_loader.cpp',
        'src\MythicRewards.cpp'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $mythicRewards $required))) {
            throw "mod-mythic-rewards 缺少文件：$required"
        }
    }
}

$trackedRiskPatterns = @('secrets.json', 'runtime.settings.json', '.pdb', '.zip')
$tracked = git -C $repoRoot ls-files
foreach ($pattern in $trackedRiskPatterns) {
    if ($tracked | Where-Object { $_ -like "*$pattern" }) { throw "检测到不应提交的文件：$pattern" }
}

Write-Host "检查通过：$(@($lock.modules).Count) 个锁定模块，$($sqlFiles.Count) 个自定义 SQL 文件。"
