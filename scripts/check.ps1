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
if ($pvpPhaseOnePatchText -notmatch '(?s)diff --git a/modules/mod-playerbots/src/Ai/Class/Dk/DKActions\.cpp.{0,700}\+\#include "PvpTacticalValue\.h"') {
    throw 'DK PvP Death Grip 动作缺少 PvpTacticalValue.h。'
}

$pvpPhaseOneHardeningPatch = Join-Path $repoRoot 'patches\0019-playerbot-pvp-phase-one-hardening.patch'
if (-not (Test-Path -LiteralPath $pvpPhaseOneHardeningPatch)) { throw '缺少 Playerbot PvP 第一阶段加固补丁。' }
$pvpPhaseOneHardeningPatchText = Get-Content -LiteralPath $pvpPhaseOneHardeningPatch -Raw
foreach ($requiredMarker in @(
    'PvpControlState',
    'DamageBreakable',
    'DamageImmune',
    'CanDamagePvpTarget',
    'observedEnemyCastExpectedEndAtMs',
    'targetAcquiredAtMs',
    'PvpCastPurpose',
    'enemyInterruptThreatScore',
    'TryPvpPetMicro',
    'TryHunterScatterTrapPlan',
    'magicPressureScore',
    'PvpPriority::Control'
)) {
    if ($pvpPhaseOneHardeningPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 第一阶段加固补丁缺少标记：$requiredMarker"
    }
}
if ($pvpPhaseOneHardeningPatchText -match '(?m)^\+\s*if \(targetCasting && TryInterrupt\(botAI, "spell lock"') {
    throw 'Spell Lock 必须由宠物执行器施放，不能继续走主人施法路径。'
}

$pvpPhaseOnePolishPatch = Join-Path $repoRoot 'patches\0020-playerbot-pvp-phase-one-polish.patch'
if (-not (Test-Path -LiteralPath $pvpPhaseOnePolishPatch)) { throw '缺少 Playerbot PvP 第一阶段收尾补丁。' }
$pvpPhaseOnePolishPatchText = Get-Content -LiteralPath $pvpPhaseOnePolishPatch -Raw
foreach ($requiredMarker in @(
    'FreezingArrow',
    'freezing arrow',
    'GetPvpControlPressureBonus',
    'ClassifyPvpControlMetadata',
    'ClassifyPvpControlFallback',
    'ShouldBlockPvpDamage',
    'ShouldBlockPvpAreaDamage',
    'IsPvpDamageSpellInternal',
    'effect.TriggerSpell',
    'ACORE_MODULE_TEST_SOURCES',
    'UtilityRemainsAvailableOnProtectedTargets',
    'AreaDamageChecksBothImpactAndCasterVicinity',
    'UncertainComplexControlFallbackFailsClosed',
    'PvpTacticalScenarioMatrix.md'
)) {
    if ($pvpPhaseOnePolishPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 第一阶段收尾补丁缺少标记：$requiredMarker"
    }
}
if ($pvpPhaseOnePolishPatchText -match '(?m)^\+\s*target->HasAuraWithMechanic\(PVP_CONTROL_MASK\)') {
    throw '不确定的复杂控制效果不能继续依赖宽泛 mechanic mask 作为可安全输出的兜底。'
}

$pvpControlWindowPatch = Join-Path $repoRoot 'patches\0021-playerbot-pvp-control-windows.patch'
if (-not (Test-Path -LiteralPath $pvpControlWindowPatch)) { throw '缺少 Playerbot PvP 控制窗口补丁。' }
$pvpControlWindowPatchText = Get-Content -LiteralPath $pvpControlWindowPatch -Raw
foreach ($requiredMarker in @(
    'PvpCcUsage',
    'SetupThenBreak',
    'PvpControlWindow',
    'EstimatePvpControlWindowRemainingMs',
    'ShouldStartPvpControlWindowDamage',
    'CanPrecastPvpControlWindow',
    'TryControlWindowResourcePrep',
    'control-window-reposition',
    'control-window-life-tap',
    'control-window-release',
    'PRECAST_SAFETY_MS',
    'getStandState()',
    'ExistingPeriodicDamageShortensBreakableExpectation',
    'Duel control-window behavior'
)) {
    if ($pvpControlWindowPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 控制窗口补丁缺少标记：$requiredMarker"
    }
}

$pvpDuelPetPatch = Join-Path $repoRoot 'patches\0022-playerbot-pvp-duel-pet-pressure.patch'
if (-not (Test-Path -LiteralPath $pvpDuelPetPatch)) { throw '缺少 Playerbot PvP 决斗与宠物压力补丁。' }
$pvpDuelPetPatchText = Get-Content -LiteralPath $pvpDuelPetPatch -Raw
if ($pvpDuelPetPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 决斗与宠物压力补丁必须使用 AzerothCore 根目录下的模块路径。'
}

$pvpContinuousSpacingPatch = Join-Path $repoRoot 'patches\0023-playerbot-pvp-continuous-spacing-and-rogue-openers.patch'
if (-not (Test-Path -LiteralPath $pvpContinuousSpacingPatch)) { throw '缺少 Playerbot PvP 连续拉距与盗贼起手补丁。' }
$pvpContinuousSpacingPatchText = Get-Content -LiteralPath $pvpContinuousSpacingPatch -Raw
if ($pvpContinuousSpacingPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 连续拉距补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'PvpRangeMotion',
    'SelectPvpRangeMotion',
    'CancelPvpMovement',
    'retreat-continuous',
    'retreat-duel-orbit',
    'paladin-immunity-stop',
    'rogue-opener-sap',
    'rogue-five-point-kidney',
    'druid-hold-bear-under-pressure',
    'melee-flank-short',
    'warrior-charge-reset-step',
    'duel-opponent-hidden',
    'CanSeeOrDetect'
)) {
    if ($pvpContinuousSpacingPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 连续拉距补丁缺少标记：$requiredMarker"
    }
}
foreach ($requiredMarker in @(
    'PvpHostilePetSnapshot',
    'PvpHostilePetResponse',
    'ResolvePvpMovementThreat',
    'pvp tactical emergency escape',
    'emergency-blink',
    'hostile-pet-control',
    'hostile-pet-kill',
    'control-window-forced-release',
    'ShouldBlockPvpDuelInterference',
    'FailedRepositionCannotConsumeTheWholeControl',
    'OnlyDuelParticipantsMayAffectAnActiveDuelist'
)) {
    if ($pvpDuelPetPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 决斗与宠物压力补丁缺少标记：$requiredMarker"
    }
}

$pvpBattlegroundEngagementPatch = Join-Path $repoRoot 'patches\0024-playerbot-pvp-battleground-engagement.patch'
if (-not (Test-Path -LiteralPath $pvpBattlegroundEngagementPatch)) {
    throw '缺少 Playerbot PvP 战场接敌与移动所有权补丁。'
}
$pvpBattlegroundEngagementPatchText = Get-Content -LiteralPath $pvpBattlegroundEngagementPatch -Raw
if ($pvpBattlegroundEngagementPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 战场接敌补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'PvpBattlegroundEngagement',
    'PvpBattlegroundPressureBand',
    'pvp tactical battleground engage',
    'ResolvePvpBattlegroundEngageTarget',
    'IsPvpBattlegroundCombatOwned',
    'SelectPvpBattlegroundRangeMotion',
    'bg-engage-dismount',
    'bg-travel-resume',
    'retreat-heading-replan',
    'cooperativeRangeMove',
    'ShouldReleasePvpBattlegroundControl',
    'OnlyActivePressureStartsDangerMovement',
    'OnlyDeliberateHardCastMayReleaseTheSolePrimaryTarget',
    'Battleground engagement and movement ownership'
)) {
    if ($pvpBattlegroundEngagementPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 战场接敌补丁缺少标记：$requiredMarker"
    }
}
if ($pvpBattlegroundEngagementPatchText -notmatch '(?s)releaseBattlegroundPrimary.{0,500}castMs >= 750.{0,200}IsChanneled\(\).{0,200}IsPvpAreaOrChainSpell') {
    throw '战场唯一主目标的破控必须限定为非引导、非范围的主动硬读条。'
}

$pvpRangedPressurePatch = Join-Path $repoRoot 'patches\0025-playerbot-pvp-ranged-pressure-and-class-fixes.patch'
if (-not (Test-Path -LiteralPath $pvpRangedPressurePatch)) {
    throw '缺少 Playerbot PvP 远程压制与职业修复补丁。'
}
$pvpRangedPressurePatchText = Get-Content -LiteralPath $pvpRangedPressurePatch -Raw
if ($pvpRangedPressurePatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 远程压制补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'ShouldRequestPvpCastPlant',
    'RequestPvpCastPlant',
    'IsPvpCastPlantActive',
    'ranged-cast-plant',
    'IsInSpec(bot->GetActiveSpec())',
    'PvpArchetype::ShadowPriest',
    'SPELL_AURA_MANA_SHIELD',
    'HasReflectSpellsAura',
    'SetFacingToObject',
    'MoveStealthOpenerToTarget(botAI, opponent, false)',
    'GetPower(POWER_ENERGY) < 70',
    'PvpMovementOwner::DruidRecovery',
    'druid-recovery-cat-reposition',
    'HardCastsCanReserveAnInterruptiblePlantWindow',
    'Ranged pressure and class recovery'
)) {
    if ($pvpRangedPressurePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 远程压制补丁缺少标记：$requiredMarker"
    }
}
if ($pvpRangedPressurePatchText -match '(?m)^\+.*duelPathBecameUnsafe') {
    throw '决斗环绕路径不能恢复每几百毫秒触发一次的侧向重算。'
}

$pvpControlOwnershipPatch = Join-Path $repoRoot 'patches\0026-playerbot-pvp-control-ownership-and-kite-value.patch'
if (-not (Test-Path -LiteralPath $pvpControlOwnershipPatch)) {
    throw '缺少 Playerbot PvP 控制归属与风筝收益补丁。'
}
$pvpControlOwnershipPatchText = Get-Content -LiteralPath $pvpControlOwnershipPatch -Raw
if ($pvpControlOwnershipPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 控制归属补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'ownedByBot',
    'GetCasterGUID',
    'OwnedSetupResumesRotationButForeignControlOnlyAllowsTimedPrecast',
    'ShouldMaintainPvpRetreat',
    'HasReadyHunterMobilePressure',
    'range-plant-no-speed-advantage',
    'rogue-reset-detected-abort',
    'ShouldAttemptPvpRecoveryReset',
    'catSpeedWindow',
    'turn evil',
    'frost trap',
    'NextAction("pet attack"',
    'A hunter may keep moving while a useful instant shot is'
)) {
    if ($pvpControlOwnershipPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 控制归属补丁缺少标记：$requiredMarker"
    }
}
if ($pvpControlOwnershipPatchText -notmatch '(?s)!ownedByBot.{0,200}PvpCcUsage::Preserve') {
    throw '他人施加的破伤控制必须保持保护状态。'
}
if ($pvpControlOwnershipPatchText -notmatch '(?s)ownedByBot && setupComplete.{0,150}PvpCcUsage::SetupThenBreak') {
    throw '自己的主目标控制必须在准备完成后允许主动破控。'
}

$pvpFlowPatch = Join-Path $repoRoot 'patches\0027-playerbot-pvp-immunity-target-and-battleground-flow.patch'
if (-not (Test-Path -LiteralPath $pvpFlowPatch)) {
    throw '缺少 Playerbot PvP 免疫、目标稳定与战场流畅度补丁。'
}
$pvpFlowPatchText = Get-Content -LiteralPath $pvpFlowPatch -Raw
if ($pvpFlowPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 流畅度补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'ShouldUsePvpImmunityRecovery',
    'mage-ice-block-release',
    'enemy-immunity-heal',
    'PvpArchetype::SurvivalHunter',
    'InvalidTargetTrigger::IsActive',
    'CanCastSpell(spell, target)',
    'ShouldKeepPvpBattlegroundCombat',
    'combatSpacing',
    'M_PI * 2.0 / 3.0',
    'VisibleTargetKeepsCombatOwnershipAcrossCoreFlagDelay',
    'stock possible-target cache'
)) {
    if ($pvpFlowPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 流畅度补丁缺少标记：$requiredMarker"
    }
}
if ($pvpFlowPatchText -match '(?m)^\+.*battlegroundReengageAtMs') {
    throw '战场重新接战不能再保留会造成五秒挂机的冷却门。'
}

$pvpMaintainedEffectsPatch = Join-Path $repoRoot 'patches\0028-playerbot-pvp-maintained-effects-and-range-band.patch'
if (-not (Test-Path -LiteralPath $pvpMaintainedEffectsPatch)) {
    throw '缺少 Playerbot PvP 持续效果与距离区间补丁。'
}
$pvpMaintainedEffectsPatchText = Get-Content -LiteralPath $pvpMaintainedEffectsPatch -Raw
if ($pvpMaintainedEffectsPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 持续效果补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'ShouldSkipPvpMaintainedEffect',
    'chains of ice',
    'hunter''s mark',
    'retreatExit',
    'advanceExit',
    'CorrectionsEnterTheUsefulBandWithoutChasingOneExactDistance',
    'player tactical trigger must remain active',
    'hostile-pet action must yield'
)) {
    if ($pvpMaintainedEffectsPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 持续效果与距离区间补丁缺少标记：$requiredMarker"
    }
}
if ($pvpMaintainedEffectsPatchText -notmatch '(?s)for \(char const\* spell : \{ "black arrow", "explosive shot", "frost shock" \}\).{0,100}EXPECT_FALSE') {
    throw '有伤害价值的持续技能不能被维持型减速策略一并禁止。'
}

$pvpPetRoutingPatch = Join-Path $repoRoot 'patches\0029-playerbot-pvp-pet-action-routing.patch'
if (-not (Test-Path -LiteralPath $pvpPetRoutingPatch)) {
    throw '缺少 Playerbot PvP 宠物动作路由补丁。'
}
$pvpPetRoutingPatchText = Get-Content -LiteralPath $pvpPetRoutingPatch -Raw
if ($pvpPetRoutingPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 宠物动作路由补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'creators["pvp tactical pet attack"]',
    'PetAttackAction(ai, "pvp tactical pet attack")',
    'NextAction("pvp tactical pet attack"',
    'DoSpecificAction("pvp tactical pet attack"',
    'pet_invalid_target_error'
)) {
    if ($pvpPetRoutingPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 宠物动作路由补丁缺少标记：$requiredMarker"
    }
}
if ($pvpPetRoutingPatchText -match '(?m)^\+.*(?:NextAction|DoSpecificAction)\("pet attack"') {
    throw 'PvP 战术层不能调用与聊天命令冲突的 pet attack 动作名。'
}

$pvpShadowBgHandoffPatch = Join-Path $repoRoot 'patches\0030-playerbot-pvp-shadow-and-bg-handoff.patch'
if (-not (Test-Path -LiteralPath $pvpShadowBgHandoffPatch)) {
    throw '缺少 Playerbot PvP 暗牧循环与战场交接补丁。'
}
$pvpShadowBgHandoffPatchText = Get-Content -LiteralPath $pvpShadowBgHandoffPatch -Raw
if ($pvpShadowBgHandoffPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 暗牧循环与战场交接补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'PvpShadowDebuffTrigger',
    'target->IsPlayer() && IsPvpTacticalContextEnabled(bot)',
    'NextAction("shadow word: death", ACTION_DEFAULT + 0.2f)',
    'NextAction("mind flay", ACTION_DEFAULT + 0.1f)',
    'ActionableContactKeepsOwnershipButAStaleCoreFlagDoesNot',
    'if (bot->InBattleground() && IsPvpBattlegroundCombatOwned(botAI))',
    'botAI->ChangeEngine(BOT_STATE_NON_COMBAT)',
    'current != target',
    'bg-travel-resume'
)) {
    if ($pvpShadowBgHandoffPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 暗牧循环与战场交接补丁缺少标记：$requiredMarker"
    }
}
if ($pvpShadowBgHandoffPatchText -match '(?m)^\+.*NextAction\("mind flay", ACTION_DEFAULT \+ 0\.2f\)') {
    throw '精神鞭打必须只高于魔杖，不能重新高于暗言术：灭。'
}
if ($pvpShadowBgHandoffPatchText -match '(?m)^\+.*ShouldKeepPvpBattlegroundCombat\(bool targetValid, bool coreCombat') {
    throw '战场战斗所有权不能由可能残留的核心战斗标记续住。'
}

$pvpBattlegroundPressurePatch = Join-Path $repoRoot 'patches\0031-playerbot-pvp-battleground-pressure-and-setup.patch'
if (-not (Test-Path -LiteralPath $pvpBattlegroundPressurePatch)) {
    throw '缺少 Playerbot PvP 战场进攻与配置补丁。'
}
$pvpBattlegroundPressurePatchText = Get-Content -LiteralPath $pvpBattlegroundPressurePatch -Raw
if ($pvpBattlegroundPressurePatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 战场进攻与配置补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'RemoteTargetsAdvanceIntoTheUsefulBandWithoutPressure',
    'prepared PvP spec',
    'HasActivePvpAuraOwnedByBot',
    'bg-rogue-prestealth',
    'bg-rogue-stealth-opener',
    'GetTargetName() override { return "self target"; }',
    'RandomGearLoweringChance = 0.35',
    'NeedsSlow(botAI, "chains of ice", owner)',
    'getName() == "reach spell"'
)) {
    if ($pvpBattlegroundPressurePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 战场进攻与配置补丁缺少标记：$requiredMarker"
    }
}
if ([double]$defaults.randomGearLoweringChance -lt 0.0 -or
    [double]$defaults.randomGearLoweringChance -gt 1.0) {
    throw 'randomGearLoweringChance 必须在 0 到 1 之间。'
}
$installerText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\install.ps1') -Raw
if ($installerText -notmatch [regex]::Escape("Set-ConfigValue `$playerbots 'AiPlayerbot.RandomGearLoweringChance'")) {
    throw '安装脚本没有写入随机机器人装备差异配置。'
}

$pvpCasterFlowPatch = Join-Path $repoRoot 'patches\0032-playerbot-pvp-control-cadence-caster-flow.patch'
if (-not (Test-Path -LiteralPath $pvpCasterFlowPatch)) {
    throw '缺少 Playerbot PvP 控制节流与施法连续性补丁。'
}
$pvpCasterFlowPatchText = Get-Content -LiteralPath $pvpCasterFlowPatch -Raw
if ($pvpCasterFlowPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 控制节流与施法连续性补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'PvpControlPurpose',
    'MarkPvpControlAttempt',
    'PvpTacticalCasterPressureAction',
    'vampiric touch',
    'PvpArchetype::ArcaneMage',
    'PvpArchetype::BalanceDruid',
    'ShouldDeployPvpTotems',
    'ShouldLeavePvpDamageForm',
    'pvpOriginalSpecNo',
    'GetTemplatePrimaryTab',
    'explicitDefensiveImmunity',
    'alternateTargetAvailable'
)) {
    if ($pvpCasterFlowPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 控制节流与施法连续性补丁缺少标记：$requiredMarker"
    }
}
if ($pvpCasterFlowPatchText -match '(?m)^\+\s*int32 firstPvpSpec') {
    throw 'PvP 天赋模板不能继续依赖固定下标偏移。'
}
if ($pvpCasterFlowPatchText -match '(?m)^\+.*ShouldUsePvpImmunityRecovery\(snapshot\.targetControlState') {
    throw '控制免伤不能再直接触发对手防御免疫恢复逻辑。'
}

$pvpInstantFlowPatch = Join-Path $repoRoot 'patches\0033-playerbot-pvp-instant-flow-and-arcane-cycle.patch'
if (-not (Test-Path -LiteralPath $pvpInstantFlowPatch)) {
    throw '缺少 Playerbot PvP 瞬发移动与奥法循环补丁。'
}
$pvpInstantFlowPatchText = Get-Content -LiteralPath $pvpInstantFlowPatch -Raw
if ($pvpInstantFlowPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 瞬发移动补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'every zero-cast-time class spell (shields included)',
    'ContinuePvpKiteAfterInstant',
    'instantKiteThreatGuid',
    'InstantDisplacementContinuesUntilTheStableBand',
    'control-window-pressure',
    'control-window-evocation',
    'ShouldRepeatPvpControl',
    'ShouldUsePvpPrimaryControlWindow',
    'stacks < 3',
    'HasAura("deep freeze", target, false, true)',
    'anti-magic shell'
)) {
    if ($pvpInstantFlowPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 瞬发移动与奥法循环补丁缺少标记：$requiredMarker"
    }
}
if ($pvpInstantFlowPatchText -match '(?m)^\+\s*return moved && !cooperativeRangeMove') {
    throw '战术距离移动不能继续占用瞬发技能的动作选择位。'
}

$pvpSpecPolicyPatch = Join-Path $repoRoot 'patches\0034-playerbot-pvp-spec-policies.patch'
if (-not (Test-Path -LiteralPath $pvpSpecPolicyPatch)) {
    throw '缺少 Playerbot PvP 专精策略补丁。'
}
$pvpSpecPolicyPatchText = Get-Content -LiteralPath $pvpSpecPolicyPatch -Raw
if ($pvpSpecPolicyPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 专精策略补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'PvpSpecPhase',
    'PvpSpecPlan',
    'ObservedPvpCooldownLedger',
    'ClassifyObservedPvpCooldown',
    'ShouldCommitPvpPrimaryBurst',
    'ShouldSpendPvpMobility',
    'ShouldReserveSurvivalTrap',
    'SelectPvpProcUse',
    'pvp tactical spec policy',
    'PvpArchetype::FuryWarrior',
    'PvpArchetype::ProtectionWarrior',
    'PvpArchetype::HolyPaladin',
    'PvpArchetype::ProtectionPaladin',
    'PvpArchetype::BloodDeathKnight',
    'PvpArchetype::FrostDeathKnight',
    'PvpArchetype::BeastMasteryHunter',
    'PvpArchetype::SurvivalHunter',
    'PvpArchetype::AssassinationRogue',
    'PvpArchetype::CombatRogue',
    'PvpArchetype::HolyPriest',
    'PvpArchetype::EnhancementShaman',
    'PvpArchetype::RestorationShaman',
    'PvpArchetype::FireMage',
    'PvpArchetype::DemonologyWarlock',
    'PvpArchetype::FeralDruid',
    'BurstRequiresARealConnectedCommitWindow'
)) {
    if ($pvpSpecPolicyPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 专精策略补丁缺少标记：$requiredMarker"
    }
}
if ($pvpSpecPolicyPatchText -match '(?m)^\+.*target->HasSpellCooldown') {
    throw '专精策略不能读取敌方隐藏技能冷却。'
}

$pvpPolicyMemoryPatch = Join-Path $repoRoot 'patches\0035-playerbot-pvp-policy-memory-and-scoring.patch'
if (-not (Test-Path -LiteralPath $pvpPolicyMemoryPatch)) {
    throw '缺少 Playerbot PvP 策略记忆与评分补丁。'
}
$pvpPolicyMemoryPatchText = Get-Content -LiteralPath $pvpPolicyMemoryPatch -Raw
if ($pvpPolicyMemoryPatchText -match '(?m)^diff --git a/(?!modules/mod-playerbots/)') {
    throw 'Playerbot PvP 策略记忆补丁必须使用 AzerothCore 根目录下的模块路径。'
}
foreach ($requiredMarker in @(
    'EnemyPvpMemory',
    'enemyMemory',
    'PvpObservationSource',
    'PvpObservationConfidence',
    'SpatialDisplacement',
    'EFFECT_MOTION_TYPE',
    'PvpBurstResource',
    'ShouldSequencePvpBurst',
    'PvpProcScores',
    'ScorePvpProcUse',
    'PvpSpecPolicyProfile',
    'GetPvpSpecPolicyProfile',
    'ResolvePvpSupportTarget(botAI, 0.20f)',
    'controlCandidateIsHealer',
    'ProcScoresPreferLethalDamageUnlessHealingIsActuallyCritical',
    'CompatibleBurstResourcesCanFormOneCommitBundle',
    'EnemyMemoryExpiresOnlyAfterItsOwnTtl'
)) {
    if ($pvpPolicyMemoryPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 策略记忆与评分补丁缺少标记：$requiredMarker"
    }
}
if ($pvpPolicyMemoryPatchText -match '(?m)^\+.*target->HasSpellCooldown') {
    throw '策略记忆不能读取敌方隐藏技能冷却。'
}
foreach ($removedSingleTargetField in @(
    'observedMobilityAtMs',
    'observedDefensiveAtMs',
    'observedImmunityAtMs',
    'observedPolicyTargetGuid'
)) {
    if ($pvpPolicyMemoryPatchText -match "(?m)^\+.*$([regex]::Escape($removedSingleTargetField))") {
        throw "策略记忆不能重新引入单目标观察字段：$removedSingleTargetField"
    }
}

$pvpRecoveryContextPatch = Join-Path $repoRoot 'patches\0036-playerbot-pvp-recovery-context-fix.patch'
if (-not (Test-Path -LiteralPath $pvpRecoveryContextPatch)) {
    throw '缺少 Playerbot PvP 恢复物品上下文修复补丁。'
}
$pvpRecoveryContextPatchText = Get-Content -LiteralPath $pvpRecoveryContextPatch -Raw
foreach ($requiredMarker in @(
    'HasUsablePvpHealthRecoveryItem',
    'GetAiObjectContext()',
    'GetValue<std::vector<Item*>>("inventory items", "healthstone")'
)) {
    if ($pvpRecoveryContextPatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 恢复物品上下文修复补丁缺少标记：$requiredMarker"
    }
}
if ($pvpRecoveryContextPatchText -match '(?m)^\+.*AI_VALUE2') {
    throw '命名空间辅助函数不能使用依赖 Action::context 的 AI_VALUE2 宏。'
}

$pvpBattlegroundLifecyclePatch = Join-Path $repoRoot 'patches\0037-playerbot-pvp-battleground-lifecycle.patch'
if (-not (Test-Path -LiteralPath $pvpBattlegroundLifecyclePatch)) {
    throw '缺少 Playerbot PvP 战场生命周期保护补丁。'
}
$pvpBattlegroundLifecyclePatchText = Get-Content -LiteralPath $pvpBattlegroundLifecyclePatch -Raw
foreach ($requiredMarker in @(
    'PVP_LIFETIME_EXTENSION',
    'InBattlegroundQueue()',
    'IsInvitedForBattlegroundInstance()',
    'defer random-bot expiry while PvP is active'
)) {
    if ($pvpBattlegroundLifecyclePatchText -notmatch [regex]::Escape($requiredMarker)) {
        throw "Playerbot PvP 战场生命周期保护补丁缺少标记：$requiredMarker"
    }
}
if ($pvpBattlegroundLifecyclePatchText -notmatch '(?s)if \(!isValid\).{0,1000}InBattleground\(\).{0,1000}SetEventValue\(bot, "add", 1, PVP_LIFETIME_EXTENSION\)') {
    throw '随机机器人生命周期到期时必须先保护正在参与 PvP 的机器人。'
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
