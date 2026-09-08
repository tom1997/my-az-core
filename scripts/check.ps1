[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$githubUpdater = Join-Path $repoRoot 'scripts\update-from-github.ps1'
if (-not (Test-Path -LiteralPath $githubUpdater)) { throw '缺少 GitHub 自动更新脚本。' }
$githubUpdaterText = Get-Content -LiteralPath $githubUpdater -Raw
foreach ($requiredMarker in @('gh run download', 'Get-FileHash', 'update.ps1', 'start.ps1')) {
    if ($githubUpdaterText -notmatch [regex]::Escape($requiredMarker)) {
        throw "GitHub 自动更新脚本缺少标记：$requiredMarker"
    }
}
[void][scriptblock]::Create($githubUpdaterText)
foreach ($launcher in @('自动更新测试版.cmd', '自动更新正式版.cmd')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $launcher))) { throw "缺少一键更新入口：$launcher" }
}

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

$pvpDuelControlPatch = Join-Path $repoRoot 'patches\0008-playerbot-pvp-duel-matchups-and-control.patch'
if (-not (Test-Path -LiteralPath $pvpDuelControlPatch)) { throw '缺少 Playerbot PvP 决斗与控制链补丁。' }
$pvpDuelControlPatchText = Get-Content -LiteralPath $pvpDuelControlPatch -Raw
foreach ($requiredMarker in @(
    'Duel.SafeRadius',
    'RangedOpponent.EmergencyDistance',
    'pvp concussive shot',
    'pvp polymorph',
    'pvp fear',
    'pvp death grip',
    'cancel pvp feign death',
    'pvp tactical duel maintenance',
    'GetDuelSecondaryTarget'
)) {
    if ($pvpDuelControlPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 决斗与控制链补丁缺少标记：$requiredMarker"
    }
}

foreach ($pvpPatchName in @(
    '0009-playerbot-pvp-state-capabilities-dr-movement.patch',
    '0010-playerbot-pvp-warrior-paladin-death-knight.patch',
    '0011-playerbot-pvp-hunter-rogue-druid.patch',
    '0012-playerbot-pvp-casters-healers.patch',
    '0013-playerbot-pvp-world-group-coordination.patch'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "patches\$pvpPatchName"))) {
        throw "缺少分层 PvP 补丁：$pvpPatchName"
    }
}

$pvpPhaseOnePatch = Join-Path $repoRoot 'patches\0018-playerbot-pvp-phase-one-planners.patch'
if (-not (Test-Path -LiteralPath $pvpPhaseOnePatch)) { throw '缺少 Playerbot PvP 第一阶段规划器补丁。' }
$pvpPhaseOnePatchText = Get-Content -LiteralPath $pvpPhaseOnePatch -Raw
foreach ($requiredMarker in @(
    'PvpSnapshot',
    'PvpIntent',
    'PvpArchetype',
    'PvpAllyTriage',
    'ShouldCommitPvpInterrupt',
    'IsSafeForPvpCast',
    'CanApplyPvpControl',
    'pvp tactical fake cast',
    'pvp tactical target swap',
    '#include "SpellAuras.h"'
)) {
    if ($pvpPhaseOnePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 第一阶段补丁缺少标记：$requiredMarker"
    }
}
if ($pvpPhaseOnePatchText -match '(?m)^\+\s*#include "Aura\.h"') {
    throw 'Playerbot PvP 第一阶段补丁引用了当前核心不存在的 Aura.h。'
}

$pvpClassPatchText = Get-Content -LiteralPath (Join-Path $repoRoot 'patches\0010-playerbot-pvp-warrior-paladin-death-knight.patch') -Raw
if ($pvpClassPatchText -match 'AI_VALUE\(' -and $pvpClassPatchText -notmatch '#include "Playerbots\.h"') {
    throw '使用 AI_VALUE 的 PvP 动作缺少 Playerbots.h。'
}

$pvpStatePatchText = Get-Content -LiteralPath (Join-Path $repoRoot 'patches\0009-playerbot-pvp-state-capabilities-dr-movement.patch') -Raw
foreach ($requiredMarker in @('PvpTacticalState', 'PvpMovementOwner', 'DIMINISHING_LEVEL_IMMUNE', 'DecisionInterval", 200')) {
    if ($pvpStatePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "PvP 状态补丁缺少标记：$requiredMarker"
    }
}

$mythicUiModule = Join-Path $repoRoot 'modules\custom\mod-mythic-plus-ui'
foreach ($requiredFile in @(
    'include.sh',
    'src\mod_mythic_plus_ui.cpp',
    'src\mod_mythic_plus_ui_loader.cpp',
    'client\MythicPlusUI.lua',
    'client\MythicPlusUI.toc',
    'data\sql\db-world\mod_mythic_plus_ui.sql',
    'data\sql\db-characters\mod_mythic_plus_ui_progress.sql'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $mythicUiModule $requiredFile))) {
        throw "大秘境 UI 模块缺少文件：$requiredFile"
    }
}
if ((Get-Item -LiteralPath (Join-Path $mythicUiModule 'include.sh')).Length -ne 0) {
    throw 'mod-mythic-plus-ui/include.sh 必须为空；C++ 注册代码应位于模块 loader.cpp。'
}

foreach ($script in @('generate-mythic-items.ps1', 'build-client-compat-patch.ps1', 'package-build.ps1')) {
    [void][scriptblock]::Create((Get-Content -LiteralPath (Join-Path $repoRoot "scripts\$script") -Raw))
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

$pvpCooperativePatch = Join-Path $repoRoot 'patches\0006-playerbot-pvp-cooperative-scheduling.patch'
if (-not (Test-Path -LiteralPath $pvpCooperativePatch)) { throw '缺少 Playerbot PvP 协作调度修复补丁。' }
$pvpCooperativePatchText = Get-Content -LiteralPath $pvpCooperativePatch -Raw
foreach ($requiredMarker in @(
    'ACTION_NORMAL + 4',
    'IsCombatPointMovementActive',
    'GetAiObjectContext()->GetValue<LastMovement&>',
    'HandleBotDuelCommand',
    'IsPlayerPvpActive',
    'RemoveFollowerPassive'
)) {
    if ($pvpCooperativePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 协作调度修复补丁缺少标记：$requiredMarker"
    }
}
if ($pvpCooperativePatchText -match '(?m)^\+\s*bot->InterruptNonMeleeSpells') {
    throw 'PvP 空间控制器不得主动中断职业策略的施法。'
}
if ($pvpCooperativePatchText -match '(?m)^\+\s*LastMovement const& last = AI_VALUE') {
    throw '普通辅助函数不得使用依赖 Action::context 的 AI_VALUE 宏。'
}
if ($pvpCooperativePatchText -notmatch '(?s)bool FleeAction::isUseful\(\).{0,400}\+\s*// Stock ranged flee') {
    throw '原版 ranged flee 抑制逻辑必须位于 FleeAction::isUseful。'
}
if ($pvpCooperativePatchText -match '(?s)bool PvpTacticalMeleeFlankAction::isUseful\(\).{0,400}\+\s*// Stock ranged flee') {
    throw '原版 ranged flee 抑制逻辑被错误放入近战 flank 判断。'
}

$pvpRangedDistancePatch = Join-Path $repoRoot 'patches\0007-playerbot-pvp-ranged-distance-control.patch'
if (-not (Test-Path -LiteralPath $pvpRangedDistancePatch)) { throw '缺少 Playerbot PvP 远程持续拉距补丁。' }
$pvpRangedDistancePatchText = Get-Content -LiteralPath $pvpRangedDistancePatch -Raw
foreach ($requiredMarker in @(
    'PreferredDistance',
    'retreating = false',
    'pvp freezing trap',
    'EnemyTooCloseForAutoShotTrigger::IsActive',
    'shadowfury',
    'psychic scream'
)) {
    if ($pvpRangedDistancePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 远程持续拉距补丁缺少标记：$requiredMarker"
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
