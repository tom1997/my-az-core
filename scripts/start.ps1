[CmdletBinding()]
param([string]$SettingsPath)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$releasePath = (Get-Content -LiteralPath (Join-Path $paths.State 'current-release.txt') -Raw).Trim()
$bin = Get-ReleaseBinPath -ReleasePath $releasePath
if (-not (Test-Path -LiteralPath (Join-Path $paths.Data 'dbc'))) { throw '尚未提取客户端数据，请先运行 extract-client-data.ps1。' }

$mysqlPid = Join-Path $paths.State 'mysql.pid'
try { Wait-TcpPort -Port $settings.mysqlPort -TimeoutSeconds 1 } catch {
    $p = Start-Process -FilePath (Join-Path $paths.MySqlBin 'mysqld.exe') -ArgumentList "--defaults-file=$($paths.MyCnf)", '--console' -PassThru -WindowStyle Hidden
    [IO.File]::WriteAllText($mysqlPid, [string]$p.Id)
    Wait-TcpPort -Port $settings.mysqlPort -TimeoutSeconds 90
}

$authArgs = @('-c', (Join-Path $paths.Configs 'authserver.conf'))
$worldArgs = @('-c', (Join-Path $paths.Configs 'worldserver.conf'))
$auth = Start-Process -FilePath (Join-Path $bin 'authserver.exe') -ArgumentList $authArgs -WorkingDirectory $bin -PassThru -WindowStyle Hidden
[IO.File]::WriteAllText((Join-Path $paths.State 'authserver.pid'), [string]$auth.Id)
$world = Start-Process -FilePath (Join-Path $bin 'worldserver.exe') -ArgumentList $worldArgs -WorkingDirectory $bin -PassThru -WindowStyle Hidden
[IO.File]::WriteAllText((Join-Path $paths.State 'worldserver.pid'), [string]$world.Id)
Write-Host "服务已启动：MySQL $($settings.mysqlPort)，Auth $($settings.authPort)，World $($settings.worldPort)。"
Write-Host '首次启动会自动导入数据库，请在 worldserver 窗口中等待启动完成。'
