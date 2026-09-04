[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$BackupPath,
    [string]$SettingsPath
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$secrets = Get-Secrets -Paths $paths
if (-not $PSCmdlet.ShouldProcess($paths.Root, "从 $BackupPath 恢复四个数据库与配置")) { return }
& (Join-Path $PSScriptRoot 'stop.ps1') -SettingsPath $SettingsPath
$stage = Join-Path $paths.Backups '.restore-stage'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
Expand-Archive -LiteralPath $BackupPath -DestinationPath $stage
$mysql = Join-Path $paths.MySqlBin 'mysql.exe'
$old = $env:MYSQL_PWD
try {
    $env:MYSQL_PWD = $secrets.acorePassword
    foreach ($db in @('acore_auth','acore_world','acore_characters','acore_playerbots')) {
        $sqlFile = Join-Path $stage "$db.sql"
        if (-not (Test-Path -LiteralPath $sqlFile)) { throw "备份缺少 $db.sql。" }
        Invoke-MySql -Paths $paths -Port $settings.mysqlPort -User acore -Password $secrets.acorePassword -Sql "DROP DATABASE IF EXISTS $db; CREATE DATABASE $db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        $process = Start-Process -FilePath $mysql -ArgumentList '--protocol=tcp','--host=127.0.0.1',"--port=$($settings.mysqlPort)",'--user=acore',$db -RedirectStandardInput $sqlFile -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { throw "恢复 $db 失败。" }
    }
} finally { $env:MYSQL_PWD = $old }
if (Test-Path -LiteralPath (Join-Path $stage 'configs')) {
    Copy-Item -LiteralPath (Join-Path $stage 'configs\*') -Destination $paths.Configs -Recurse -Force
}
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host '恢复完成。请确认对应 release 已安装后再启动服务。'
