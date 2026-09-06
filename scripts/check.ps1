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

$ownedBotsPatch = Join-Path $repoRoot 'patches\0003-playerbot-owned-autonomy-and-duels.patch'
if (-not (Test-Path -LiteralPath $ownedBotsPatch)) { throw '缺少 Playerbot 自主与决斗补丁。' }
$ownedBotsPatchText = Get-Content -LiteralPath $ownedBotsPatch -Raw
foreach ($requiredMarker in @(
    'ApplyUserStrategies',
    'login-solo',
    'login-persistent',
    'PersistentOwned',
    'botduel',
    'LogoutRandomBots'
)) {
    if ($ownedBotsPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot 自主与决斗补丁缺少标记：$requiredMarker"
    }
}

$pvpMeleePatch = Join-Path $repoRoot 'patches\0005-playerbot-pvp-tactical-melee-flanking.patch'
if (-not (Test-Path -LiteralPath $pvpMeleePatch)) { throw '缺少 Playerbot PvP 近战抓背补丁。' }
$pvpMeleePatchText = Get-Content -LiteralPath $pvpMeleePatch -Raw
foreach ($requiredMarker in @(
    'PvPTactical.Melee.Enable',
    'pvp tactical melee flank',
    'PvpTacticalMeleeFlankAction',
    'pvpTacticalMeleeDecisionInterval'
)) {
    if ($pvpMeleePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 近战抓背补丁缺少标记：$requiredMarker"
    }
}

$pvpTacticalPatch = Join-Path $repoRoot 'patches\0004-playerbot-pvp-tactical-ranged.patch'
if (-not (Test-Path -LiteralPath $pvpTacticalPatch)) { throw '缺少 Playerbot PvP 战术补丁。' }
$pvpTacticalPatchText = Get-Content -LiteralPath $pvpTacticalPatch -Raw
foreach ($requiredMarker in @(
    'PvPTactical.Enable',
    'pvp tactical ranged too close',
    'PvpTacticalRetreatAction',
    'pvpTacticalDecisionInterval',
    'TargetLeashDistance'
)) {
    if ($pvpTacticalPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 战术补丁缺少标记：$requiredMarker"
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
    if ($bridge -notmatch 'RewardMythicCompletion') { throw 'Mythic Plus 桥接补丁未调用 RewardMythicCompletion。' }
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
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts\generate-mythic-items.ps1'))) {
        throw 'mod-mythic-rewards 缺少装备 SQL 生成器。'
    }
    $rewardSql = Get-Content -LiteralPath (Join-Path $mythicRewards 'data\sql\db-world\mod_mythic_rewards.sql') -Raw
    foreach ($mapId in @(574,575,576,578,599,600,601,602,604,619,632,658)) {
        if ($rewardSql -notmatch "(?<!\d)$mapId(?!\d)") { throw "大秘境装备池缺少地图：$mapId" }
    }
    if ($rewardSql -notmatch 'src\.itemset\s*=\s*0' -or $rewardSql -notmatch 'InventoryType NOT IN \(0,12\)') {
        throw '大秘境装备池必须排除套装、兑换物和饰品。'
    }
}

$trackedRiskPatterns = @('secrets.json', 'runtime.settings.json', '.pdb', '.zip')
$tracked = git -C $repoRoot ls-files
foreach ($pattern in $trackedRiskPatterns) {
    if ($tracked | Where-Object { $_ -like "*$pattern" }) { throw "检测到不应提交的文件：$pattern" }
}

Write-Host "检查通过：$(@($lock.modules).Count) 个锁定模块，$($sqlFiles.Count) 个自定义 SQL 文件。"
