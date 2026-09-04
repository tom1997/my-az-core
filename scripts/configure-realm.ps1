[CmdletBinding()]
param([string]$SettingsPath)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$secrets = Get-Secrets -Paths $paths
$name = ([string]$settings.realmName).Replace("'", "''")
$address = ([string]$settings.realmAddress).Replace("'", "''")
$local = ([string]$settings.realmLocalAddress).Replace("'", "''")
$sql = "UPDATE realmlist SET name='$name', address='$address', localAddress='$local', port=$($settings.worldPort), gamebuild=12340 WHERE id=1;"
Invoke-MySql -Paths $paths -Port $settings.mysqlPort -User acore -Password $secrets.acorePassword -Database acore_auth -Sql $sql
Write-Host "Realm 已配置为 $name (${address}:$($settings.worldPort))。"
