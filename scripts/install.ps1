[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$PackagePath,
    [string]$SettingsPath,
    [switch]$SkipMySqlSetup
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
Assert-SafeInstallRoot -Path $paths.Root

$wowExe = Join-Path $paths.Client 'Wow.exe'
if (-not (Test-Path -LiteralPath $wowExe)) {
    throw "请先把合法的 zhCN WoW 3.3.5a 客户端放到 $($paths.Client)，当前找不到 Wow.exe。"
}
$wowVersion = (Get-Item -LiteralPath $wowExe).VersionInfo
$versionText = "$($wowVersion.FileVersion) $($wowVersion.ProductVersion)"
if ($versionText -notmatch '3\s*[,\.]\s*3\s*[,\.]\s*5' -or $versionText -notmatch '12340') {
    throw "客户端版本不是 3.3.5a Build 12340：$versionText"
}

$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($paths.Root).TrimEnd(':\'))
if ($drive.Free -lt 45GB) { throw "安装盘可用空间不足 45 GB：$([math]::Round($drive.Free / 1GB, 1)) GB" }

foreach ($dir in @($paths.Root, $paths.Releases, $paths.Runtime, $paths.Configs, $paths.Data, $paths.Logs, $paths.State, $paths.Backups, $paths.MySql)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$tempRoot = Join-Path $paths.Root '.install-temp'
if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
try {
    $env:TEMP = $tempRoot
    $env:TMP = $tempRoot
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $tempRoot -Force
    $manifestPath = Join-Path $tempRoot 'source-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw '运行包缺少 source-manifest.json。' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $releaseDate = ([DateTime]$manifest.builtAt).ToUniversalTime().ToString('yyyyMMdd')
    $releaseName = "$releaseDate.$($manifest.profile).$($manifest.core.commit.Substring(0,8))"
    $releasePath = Join-Path $paths.Releases $releaseName
    if (Test-Path -LiteralPath $releasePath) { Remove-Item -LiteralPath $releasePath -Recurse -Force }
    Move-Item -LiteralPath $tempRoot -Destination $releasePath
    [IO.File]::WriteAllText((Join-Path $paths.State 'current-release.txt'), $releasePath, [Text.UTF8Encoding]::new($false))

    $distConfigs = Join-Path $releasePath 'dist\configs'
    if (-not (Test-Path -LiteralPath $distConfigs)) { $distConfigs = Join-Path $releasePath 'dist\etc' }
    if (-not (Test-Path -LiteralPath $distConfigs)) { throw '运行包中找不到 configs 或 etc。' }
    Get-ChildItem -LiteralPath $distConfigs -Filter '*.conf.dist' -File -Recurse | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($distConfigs, $_.FullName)
        $targetDist = Join-Path $paths.Configs $relative
        New-Item -ItemType Directory -Path (Split-Path $targetDist -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $targetDist -Force
        $target = $targetDist -replace '\.dist$', ''
        if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $_.FullName -Destination $target }
    }
    $packagedSource = Join-Path $releasePath 'source-data'
    if (Test-Path -LiteralPath $paths.SourceData) { Remove-Item -LiteralPath $paths.SourceData -Recurse -Force }
    Copy-Item -LiteralPath $packagedSource -Destination $paths.SourceData -Recurse
} finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}

if (-not $SkipMySqlSetup -and -not (Test-Path -LiteralPath (Join-Path $paths.MySqlBin 'mysqld.exe'))) {
    $mysqlZip = Join-Path $paths.Root 'mysql-8.4.9-winx64.zip'
    Invoke-WebRequest -Uri 'https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.9-winx64.zip' -OutFile $mysqlZip -UserAgent 'Mozilla/5.0'
    if ((Get-Item -LiteralPath $mysqlZip).Length -lt 50MB) { throw 'MySQL 下载文件异常。' }
    $mysqlExtract = Join-Path $paths.MySql 'extract'
    Expand-Archive -LiteralPath $mysqlZip -DestinationPath $mysqlExtract -Force
    Move-Item -LiteralPath (Join-Path $mysqlExtract 'mysql-8.4.9-winx64') -Destination (Join-Path $paths.MySql 'server')
    Remove-Item -LiteralPath $mysqlExtract -Recurse -Force
    Remove-Item -LiteralPath $mysqlZip -Force
}

if (-not (Test-Path -LiteralPath (Join-Path $paths.MySqlBin 'mysqld.exe'))) {
    throw '找不到便携 MySQL。首次安装请不要使用 -SkipMySqlSetup。'
}

$slashRoot = $paths.MySql.Replace('\', '/')
$slashData = $paths.MySqlData.Replace('\', '/')
$myIni = @"
[mysqld]
basedir=$slashRoot/server
datadir=$slashData
port=$($settings.mysqlPort)
bind-address=127.0.0.1
skip-log-bin
innodb_buffer_pool_size=8G
innodb_io_capacity=500
innodb_io_capacity_max=2500
transaction-isolation=READ-COMMITTED
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
max_allowed_packet=1G
[client]
port=$($settings.mysqlPort)
host=127.0.0.1
default-character-set=utf8mb4
"@
[IO.File]::WriteAllText($paths.MyCnf, $myIni, [Text.UTF8Encoding]::new($false))

if (-not (Test-Path -LiteralPath $paths.Secrets)) {
    New-Item -ItemType Directory -Path $paths.MySqlData -Force | Out-Null
    & (Join-Path $paths.MySqlBin 'mysqld.exe') "--defaults-file=$($paths.MyCnf)" --initialize-insecure --console
    if ($LASTEXITCODE -ne 0) { throw 'MySQL 初始化失败。' }
    $mysqlProcess = Start-Process -FilePath (Join-Path $paths.MySqlBin 'mysqld.exe') -ArgumentList "--defaults-file=$($paths.MyCnf)", '--console' -PassThru -WindowStyle Hidden
    Wait-TcpPort -Port ([int]$settings.mysqlPort) -TimeoutSeconds 90
    $rootPassword = New-RandomPassword
    $acorePassword = New-RandomPassword
    Invoke-MySql -Paths $paths -Port $settings.mysqlPort -User root -Password '' -Sql "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPassword';"
    $sql = @"
CREATE DATABASE IF NOT EXISTS acore_auth CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS acore_world CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS acore_characters CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS acore_playerbots CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'acore'@'127.0.0.1' IDENTIFIED BY '$acorePassword';
CREATE USER IF NOT EXISTS 'acore'@'localhost' IDENTIFIED BY '$acorePassword';
GRANT ALL PRIVILEGES ON acore_auth.* TO 'acore'@'127.0.0.1';
GRANT ALL PRIVILEGES ON acore_world.* TO 'acore'@'127.0.0.1';
GRANT ALL PRIVILEGES ON acore_characters.* TO 'acore'@'127.0.0.1';
GRANT ALL PRIVILEGES ON acore_playerbots.* TO 'acore'@'127.0.0.1';
GRANT ALL PRIVILEGES ON acore_auth.* TO 'acore'@'localhost';
GRANT ALL PRIVILEGES ON acore_world.* TO 'acore'@'localhost';
GRANT ALL PRIVILEGES ON acore_characters.* TO 'acore'@'localhost';
GRANT ALL PRIVILEGES ON acore_playerbots.* TO 'acore'@'localhost';
FLUSH PRIVILEGES;
"@
    Invoke-MySql -Paths $paths -Port $settings.mysqlPort -User root -Password $rootPassword -Sql $sql
    $secrets = @{ rootPassword = $rootPassword; acorePassword = $acorePassword }
    [IO.File]::WriteAllText($paths.Secrets, (($secrets | ConvertTo-Json) + "`n"), [Text.UTF8Encoding]::new($false))
    & icacls $paths.Secrets /inheritance:r /grant:r "$env:USERNAME`:(F)" | Out-Null
    $oldPassword = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $rootPassword
        & (Join-Path $paths.MySqlBin 'mysqladmin.exe') --protocol=tcp --host=127.0.0.1 "--port=$($settings.mysqlPort)" --user=root shutdown
    } finally { $env:MYSQL_PWD = $oldPassword }
    Wait-Process -Id $mysqlProcess.Id -Timeout 30 -ErrorAction SilentlyContinue
}

$secrets = Get-Secrets -Paths $paths
$worldConf = Join-Path $paths.Configs 'worldserver.conf'
$authConf = Join-Path $paths.Configs 'authserver.conf'
if (-not (Test-Path -LiteralPath $worldConf) -or -not (Test-Path -LiteralPath $authConf)) { throw '缺少 worldserver.conf 或 authserver.conf。' }
$db = "127.0.0.1;$($settings.mysqlPort);acore;$($secrets.acorePassword)"
Set-ConfigValue $worldConf 'LoginDatabaseInfo' "`"$db;acore_auth`""
Set-ConfigValue $worldConf 'WorldDatabaseInfo' "`"$db;acore_world`""
Set-ConfigValue $worldConf 'CharacterDatabaseInfo' "`"$db;acore_characters`""
Set-ConfigValue $worldConf 'PlayerbotsDatabaseInfo' "`"$db;acore_playerbots`""
Set-ConfigValue $worldConf 'Playerbots.Updates.EnableDatabases' '1'
Set-ConfigValue $authConf 'LoginDatabaseInfo' "`"$db;acore_auth`""
Set-ConfigValue $authConf 'RealmServerPort' ([string]$settings.authPort)
Set-ConfigValue $worldConf 'WorldServerPort' ([string]$settings.worldPort)
Set-ConfigValue $worldConf 'DataDir' "`"$($paths.Data.Replace('\','/'))`""
Set-ConfigValue $worldConf 'SourceDirectory' "`"$($paths.SourceData.Replace('\','/'))`""
Set-ConfigValue $worldConf 'MySQLExecutable' "`"$((Join-Path $paths.MySqlBin 'mysql.exe').Replace('\','/'))`""
Set-ConfigValue $authConf 'SourceDirectory' "`"$($paths.SourceData.Replace('\','/'))`""
Set-ConfigValue $authConf 'MySQLExecutable' "`"$((Join-Path $paths.MySqlBin 'mysql.exe').Replace('\','/'))`""
Set-ConfigValue $worldConf 'MapUpdate.Threads' ([string]$settings.mapUpdateThreads)
foreach ($key in @('Rate.XP.Kill','Rate.XP.Quest','Rate.XP.Explore','Rate.Drop.Item.Poor','Rate.Drop.Item.Normal','Rate.Drop.Item.Uncommon','Rate.Drop.Item.Rare','Rate.Drop.Item.Epic','Rate.Drop.Money','Rate.Reputation.Gain')) {
    Set-ConfigValue $worldConf $key '1'
}

function Find-ModuleConfig([string]$Name) {
    return Get-ChildItem -LiteralPath $paths.Configs -Filter $Name -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
}
$playerbots = Find-ModuleConfig 'playerbots.conf'
if (-not $playerbots) { throw '找不到 playerbots.conf。' }
Set-ConfigValue $playerbots 'PlayerbotsDatabaseInfo' "`"$db;acore_playerbots`""
Set-ConfigValue $playerbots 'AiPlayerbot.MinRandomBots' ([string]$settings.randomBots)
Set-ConfigValue $playerbots 'AiPlayerbot.MaxRandomBots' ([string]$settings.randomBots)
Set-ConfigValue $playerbots 'AiPlayerbot.DisabledWithoutRealPlayer' $(if ($settings.disableBotsWithoutPlayers) {'1'} else {'0'})
Set-ConfigValue $playerbots 'AiPlayerbot.BotActiveAlone' ([string]$settings.botActiveAlonePercent)
Set-ConfigValue $playerbots 'AiPlayerbot.botActiveAloneSmartScale' '1'
Set-ConfigValue $playerbots 'AiPlayerbot.CommandServerPort' '0'
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Enable' $(if (Get-SettingValue $settings 'pvpTacticalEnabled' $true) {'1'} else {'0'})
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Duel' $(if (Get-SettingValue $settings 'pvpTacticalDuel' $true) {'1'} else {'0'})
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Arena' $(if (Get-SettingValue $settings 'pvpTacticalArena' $true) {'1'} else {'0'})
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Battleground' $(if (Get-SettingValue $settings 'pvpTacticalBattleground' $true) {'1'} else {'0'})
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.OpenWorld' $(if (Get-SettingValue $settings 'pvpTacticalOpenWorld' $false) {'1'} else {'0'})
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.DecisionInterval' ([string](Get-SettingValue $settings 'pvpTacticalDecisionInterval' 250))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Hunter.MinDistance' ([string](Get-SettingValue $settings 'pvpTacticalHunterMinDistance' 24.0))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Caster.MinDistance' ([string](Get-SettingValue $settings 'pvpTacticalCasterMinDistance' 18.0))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Healer.MinDistance' ([string](Get-SettingValue $settings 'pvpTacticalHealerMinDistance' 22.0))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.RetreatStep' ([string](Get-SettingValue $settings 'pvpTacticalRetreatStep' 7.0))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.TargetLeashDistance' ([string](Get-SettingValue $settings 'pvpTacticalTargetLeashDistance' 55.0))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Melee.Enable' $(if (Get-SettingValue $settings 'pvpTacticalMeleeEnabled' $true) {'1'} else {'0'})
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Melee.DecisionInterval' ([string](Get-SettingValue $settings 'pvpTacticalMeleeDecisionInterval' 600))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Melee.FlankDistance' ([string](Get-SettingValue $settings 'pvpTacticalMeleeFlankDistance' 1.5))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Melee.MinAngle' ([string](Get-SettingValue $settings 'pvpTacticalMeleeMinAngle' 100.0))
Set-ConfigValue $playerbots 'AiPlayerbot.PvPTactical.Melee.MaxAngle' ([string](Get-SettingValue $settings 'pvpTacticalMeleeMaxAngle' 145.0))

$autoBalance = Find-ModuleConfig 'AutoBalance.conf'
if ($autoBalance) {
    Set-ConfigValue $autoBalance 'AutoBalance.LevelScaling' '1'
    Set-ConfigValue $autoBalance 'AutoBalance.LevelScaling.Method' '"dynamic"'
    Set-ConfigValue $autoBalance 'AutoBalance.MinPlayers' '1'
    Set-ConfigValue $autoBalance 'AutoBalance.MinPlayers.Heroic' '1'
    Set-ConfigValue $autoBalance 'AutoBalance.LevelScaling.DynamicLevel.Ceiling.Dungeons' '1'
    Set-ConfigValue $autoBalance 'AutoBalance.LevelScaling.DynamicLevel.Floor.Dungeons' '5'
    # Mythic Plus owns scaling in its WotLK heroic pool. Disabling AutoBalance
    # there prevents health and damage from being multiplied twice.
    Set-ConfigValue $autoBalance 'AutoBalance.Disable.PerInstance' ('"' + [string](Get-SettingValue $settings 'autoBalanceDisabledInstanceIds' '574,575,576,578,599,600,601,602,604,619,632,658') + '"')
}
$rdf = Find-ModuleConfig 'mod-rdf-expansion.conf'
if ($rdf) { Set-ConfigValue $rdf 'RDF.Expansion' ([string]$settings.rdfExpansion) }
$ahbot = Find-ModuleConfig 'mod_ahbot.conf'
if ($ahbot) {
    # Account/GUID are deliberately left at zero until configure-ahbot.ps1
    # binds a dedicated, normal character to the market maker.
    Set-ConfigValue $ahbot 'AuctionHouseBot.EnableSeller' $(if (Get-SettingValue $settings 'auctionHouseBotSellerEnabled' $false) {'1'} else {'0'})
    Set-ConfigValue $ahbot 'AuctionHouseBot.EnableBuyer' $(if (Get-SettingValue $settings 'auctionHouseBotBuyerEnabled' $false) {'1'} else {'0'})
}
$mythicPlus = Find-ModuleConfig 'mod_mythic_plus.conf'
if ($mythicPlus) {
    Set-ConfigValue $mythicPlus 'MythicPlus.Enable' $(if (Get-SettingValue $settings 'mythicPlusEnabled' $true) {'1'} else {'0'})
    Set-ConfigValue $mythicPlus 'MythicPlus.Penalty.OnDeath' ([string](Get-SettingValue $settings 'mythicPlusPenaltyOnDeathSeconds' 5))
    Set-ConfigValue $mythicPlus 'MythicPlus.KeystoneBuyTimer' ([string](Get-SettingValue $settings 'mythicPlusKeystoneBuyTimerMinutes' 0))
    Set-ConfigValue $mythicPlus 'MythicPlus.DropKeystoneOnDungeonComplete' '1'
}
$mythicRewards = Find-ModuleConfig 'mod_mythic_rewards.conf'
if ($mythicRewards) {
    Set-ConfigValue $mythicRewards 'MythicRewards.Enable' $(if (Get-SettingValue $settings 'mythicRewardsEnabled' $true) {'1'} else {'0'})
    Set-ConfigValue $mythicRewards 'MythicRewards.ChancePct' ([string](Get-SettingValue $settings 'mythicRewardsChancePct' 100))
    Set-ConfigValue $mythicRewards 'MythicRewards.MailOnFull' $(if (Get-SettingValue $settings 'mythicRewardsMailOnFull' $true) {'1'} else {'0'})
    Set-ConfigValue $mythicRewards 'MythicRewards.IncludeWeapons' $(if (Get-SettingValue $settings 'mythicRewardsIncludeWeapons' $true) {'1'} else {'0'})
    Set-ConfigValue $mythicRewards 'MythicRewards.CandidateWindowPct' ([string](Get-SettingValue $settings 'mythicRewardsCandidateWindowPct' 20))
    Set-ConfigValue $mythicRewards 'MythicRewards.TimedPartyItems' ([string](Get-SettingValue $settings 'mythicRewardsTimedPartyItems' 3))
    Set-ConfigValue $mythicRewards 'MythicRewards.OvertimePartyItems' ([string](Get-SettingValue $settings 'mythicRewardsOvertimePartyItems' 2))
    Set-ConfigValue $mythicRewards 'MythicRewards.Weekly.Enable' $(if (Get-SettingValue $settings 'mythicRewardsWeeklyEnabled' $true) {'1'} else {'0'})
}
$dungeonClear = Find-ModuleConfig 'mod_dungeon_clear.conf'
if ($dungeonClear) {
    Set-ConfigValue $dungeonClear 'DungeonClear.Enable' $(if ($settings.dungeonClearEnabled) {'1'} else {'0'})
    Set-ConfigValue $dungeonClear 'DungeonClear.LootMinQuality' ([string]$settings.dungeonClearLootMinQuality)
    Set-ConfigValue $dungeonClear 'DungeonClear.BetterLootRolling' $(if ($settings.dungeonClearBetterLootRolling) {'1'} else {'0'})
    Set-ConfigValue $dungeonClear 'DungeonClear.SmartRest' $(if ($settings.dungeonClearSmartRest) {'1'} else {'0'})
    Set-ConfigValue $dungeonClear 'DungeonClear.PullDynamicMaxLeeroyMobs' ([string]$settings.dungeonClearPullDynamicMaxLeeroyMobs)
    Set-ConfigValue $dungeonClear 'DungeonClear.DungeonQueueFill.Enable' $(if ($settings.dungeonClearQueueFillEnabled) {'1'} else {'0'})
    Set-ConfigValue $dungeonClear 'DungeonClear.DungeonQueueFill.AutoClear' '0'
}
$randomEnchants = Find-ModuleConfig 'random_enchants.conf'
if ($randomEnchants) {
    Set-ConfigValue $randomEnchants 'RandomEnchants.Enable' $(if ($settings.randomEnchantsEnabled) {'1'} else {'0'})
    Set-ConfigValue $randomEnchants 'RandomEnchants.EnchantChance1' ([string]$settings.randomEnchantChance1)
    Set-ConfigValue $randomEnchants 'RandomEnchants.EnchantChance2' ([string]$settings.randomEnchantChance2)
    Set-ConfigValue $randomEnchants 'RandomEnchants.EnchantChance3' ([string]$settings.randomEnchantChance3)
}

Write-Host "安装完成。当前 release：$releasePath"
Write-Host '下一步运行 scripts/extract-client-data.ps1，然后运行 scripts/start.ps1。'
