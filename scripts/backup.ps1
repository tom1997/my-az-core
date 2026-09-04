[CmdletBinding()]
param([string]$SettingsPath, [ValidateSet('daily','weekly')][string]$Kind = 'daily')

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$secrets = Get-Secrets -Paths $paths
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $paths.Backups ".stage-$timestamp"
$destinationDir = Join-Path $paths.Backups $Kind
New-Item -ItemType Directory -Path $stage,$destinationDir -Force | Out-Null
$dump = Join-Path $paths.MySqlBin 'mysqldump.exe'
$old = $env:MYSQL_PWD
try {
    $env:MYSQL_PWD = $secrets.acorePassword
    foreach ($db in @('acore_auth','acore_world','acore_characters','acore_playerbots')) {
        & $dump --protocol=tcp --host=127.0.0.1 "--port=$($settings.mysqlPort)" --user=acore --single-transaction --routines --events --hex-blob "--result-file=$(Join-Path $stage "$db.sql")" $db
        if ($LASTEXITCODE -ne 0) { throw "备份 $db 失败。" }
    }
} finally { $env:MYSQL_PWD = $old }
Copy-Item -LiteralPath $paths.Configs -Destination (Join-Path $stage 'configs') -Recurse
$current = (Get-Content -LiteralPath (Join-Path $paths.State 'current-release.txt') -Raw).Trim()
Copy-Item -LiteralPath (Join-Path $current 'source-manifest.json') -Destination $stage
$zip = Join-Path $destinationDir "azerothcore-$Kind-$timestamp.zip"
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force

$keep = if ($Kind -eq 'daily') { [int]$settings.backupDailyRetention } else { [int]$settings.backupWeeklyRetention }
Get-ChildItem -LiteralPath $destinationDir -Filter '*.zip' -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip $keep | Remove-Item -Force
Write-Host "备份完成：$zip"
