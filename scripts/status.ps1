[CmdletBinding()]
param([string]$SettingsPath)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings

function Test-StatusPort([int]$Port) {
    try { Wait-TcpPort -Port $Port -TimeoutSeconds 1; return $true } catch { return $false }
}

$release = if (Test-Path -LiteralPath (Join-Path $paths.State 'current-release.txt')) {
    (Get-Content -LiteralPath (Join-Path $paths.State 'current-release.txt') -Raw).Trim()
} else { '未安装' }
$mysql = Test-StatusPort -Port $settings.mysqlPort
$auth = Test-StatusPort -Port $settings.authPort
$world = Test-StatusPort -Port $settings.worldPort

Write-Host "当前版本：$release"
Write-Host ("便携 MySQL {0}  127.0.0.1:{1}" -f $(if ($mysql) {'运行中'} else {'已停止'}), $settings.mysqlPort)
Write-Host ("Auth Server {0}  0.0.0.0:{1}" -f $(if ($auth) {'运行中'} else {'已停止'}), $settings.authPort)
Write-Host ("World Server {0}  0.0.0.0:{1}" -f $(if ($world) {'运行中'} else {'已停止'}), $settings.worldPort)

if (-not ($mysql -and $auth -and $world)) { exit 1 }
