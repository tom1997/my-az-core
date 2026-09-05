[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CharacterName,
    [bool]$EnableSeller = $true,
    [bool]$EnableBuyer = $true,
    [string]$SettingsPath
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$secrets = Get-Secrets -Paths $paths
$config = Get-ChildItem -LiteralPath $paths.Configs -Filter 'mod_ahbot.conf' -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
if (-not $config) { throw '找不到 mod_ahbot.conf；请先安装包含 mod-ah-bot 的运行包。' }

$escapedName = $CharacterName.Replace("'", "''")
$mysql = Join-Path $paths.MySqlBin 'mysql.exe'
$oldPassword = $env:MYSQL_PWD
try {
    $env:MYSQL_PWD = $secrets.acorePassword
    $result = & $mysql --protocol=tcp --host=127.0.0.1 "--port=$($settings.mysqlPort)" --user=acore --batch --skip-column-names acore_characters --execute "SELECT account, guid FROM characters WHERE name = '$escapedName' LIMIT 2;"
    if ($LASTEXITCODE -ne 0) { throw '查询 AHBot 角色失败；请确认 MySQL 正在运行。' }
} finally {
    $env:MYSQL_PWD = $oldPassword
}

$rows = @($result | Where-Object { $_ -match '^\d+\s+\d+$' })
if ($rows.Count -ne 1) { throw "找不到唯一角色 '$CharacterName'。请先用普通玩家账号创建一个专用角色，并确保服务端数据库已保存。" }
$parts = $rows[0] -split '\s+'
Set-ConfigValue $config 'AuctionHouseBot.Account' $parts[0]
Set-ConfigValue $config 'AuctionHouseBot.GUID' $parts[1]
Set-ConfigValue $config 'AuctionHouseBot.EnableSeller' $(if ($EnableSeller) {'1'} else {'0'})
Set-ConfigValue $config 'AuctionHouseBot.EnableBuyer' $(if ($EnableBuyer) {'1'} else {'0'})
Set-ConfigValue $config 'AuctionHouseBot.VendorItems' '0'
Set-ConfigValue $config 'AuctionHouseBot.VendorTradeGoods' '0'
Set-ConfigValue $config 'AuctionHouseBot.LootItems' '1'
Set-ConfigValue $config 'AuctionHouseBot.LootTradeGoods' '1'
Set-ConfigValue $config 'AuctionHouseBot.DisableBOP_Or_Quest_NoReqLevel' '1'
Set-ConfigValue $config 'AuctionHouseBot.DuplicatesCount' '3'
Write-Host "AHBot 已绑定角色 $CharacterName（Account=$($parts[0]), GUID=$($parts[1])）。重启 worldserver 后生效。"
