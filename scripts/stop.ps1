[CmdletBinding()]
param([string]$SettingsPath, [switch]$IncludeMySql)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
Stop-ProcessFromPidFile -PidFile (Join-Path $paths.State 'worldserver.pid') -Name 'worldserver'
Stop-ProcessFromPidFile -PidFile (Join-Path $paths.State 'authserver.pid') -Name 'authserver'
if ($IncludeMySql) {
    $mysqlPidFile = Join-Path $paths.State 'mysql.pid'
    $mysqlListening = $false
    try {
        Wait-TcpPort -Port ([int]$settings.mysqlPort) -TimeoutSeconds 1
        $mysqlListening = $true
    } catch { }

    if ($mysqlListening) {
        $secrets = Get-Secrets -Paths $paths
        $oldPassword = $env:MYSQL_PWD
        try {
            $env:MYSQL_PWD = $secrets.rootPassword
            & (Join-Path $paths.MySqlBin 'mysqladmin.exe') --protocol=tcp --host=127.0.0.1 "--port=$($settings.mysqlPort)" --user=root shutdown
            if ($LASTEXITCODE -ne 0) { throw "MySQL 安全关闭失败，退出码 $LASTEXITCODE。" }
        } finally {
            $env:MYSQL_PWD = $oldPassword
        }
    }

    if (Test-Path -LiteralPath $mysqlPidFile) {
        $mysqlProcessId = [int](Get-Content -LiteralPath $mysqlPidFile -Raw).Trim()
        $mysqlProcess = Get-Process -Id $mysqlProcessId -ErrorAction SilentlyContinue
        if ($mysqlProcess -and $mysqlProcess.ProcessName -ieq 'mysqld') {
            try { Wait-Process -Id $mysqlProcessId -Timeout 30 -ErrorAction Stop } catch {
                throw "MySQL 已收到关闭命令，但 30 秒内未退出；未强制终止。"
            }
        }
        Remove-Item -LiteralPath $mysqlPidFile -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'MySQL 已安全关闭。'
}
