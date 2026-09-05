[CmdletBinding()]
param(
    [string]$SettingsPath,
    [switch]$VisibleWorld
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$releasePath = (Get-Content -LiteralPath (Join-Path $paths.State 'current-release.txt') -Raw).Trim()
$bin = Get-ReleaseBinPath -ReleasePath $releasePath
if (-not (Test-Path -LiteralPath (Join-Path $paths.Data 'dbc'))) { throw '尚未提取客户端数据，请先运行 extract-client-data.ps1。' }

function Find-ManagedProcess {
    param([string]$Name, [string]$Executable, [string]$PidFile)

    if (Test-Path -LiteralPath $PidFile) {
        $savedId = 0
        if ([int]::TryParse((Get-Content -LiteralPath $PidFile -Raw).Trim(), [ref]$savedId)) {
            $saved = Get-Process -Id $savedId -ErrorAction SilentlyContinue
            if ($saved -and $saved.ProcessName -ieq $Name -and $saved.Path -ieq $Executable) { return $saved }
        }
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    }

    $running = Get-Process -Name $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -ieq $Executable } |
        Select-Object -First 1
    if ($running) {
        [IO.File]::WriteAllText($PidFile, [string]$running.Id)
        return $running
    }
    return $null
}

function Test-LocalPort([int]$Port) {
    try { Wait-TcpPort -Port $Port -TimeoutSeconds 1; return $true } catch { return $false }
}

$mysqlPid = Join-Path $paths.State 'mysql.pid'
if (-not (Test-LocalPort -Port $settings.mysqlPort)) {
    $p = Start-Process -FilePath (Join-Path $paths.MySqlBin 'mysqld.exe') -ArgumentList "--defaults-file=$($paths.MyCnf)", '--console' -PassThru -WindowStyle Hidden
    [IO.File]::WriteAllText($mysqlPid, [string]$p.Id)
    Wait-TcpPort -Port $settings.mysqlPort -TimeoutSeconds 90
}

$authArgs = @('-c', (Join-Path $paths.Configs 'authserver.conf'))
$worldArgs = @('-c', (Join-Path $paths.Configs 'worldserver.conf'))
$authExe = Join-Path $bin 'authserver.exe'
$worldExe = Join-Path $bin 'worldserver.exe'
$authPid = Join-Path $paths.State 'authserver.pid'
$worldPid = Join-Path $paths.State 'worldserver.pid'
$auth = Find-ManagedProcess -Name 'authserver' -Executable $authExe -PidFile $authPid
$world = Find-ManagedProcess -Name 'worldserver' -Executable $worldExe -PidFile $worldPid
$started = [Collections.Generic.List[string]]::new()

if (-not $auth) {
    if (Test-LocalPort -Port $settings.authPort) { throw "Auth 端口 $($settings.authPort) 已被其他程序占用。" }
    $auth = Start-Process -FilePath $authExe -ArgumentList $authArgs -WorkingDirectory $paths.Runtime -PassThru -WindowStyle Hidden
    [IO.File]::WriteAllText($authPid, [string]$auth.Id)
    $started.Add('Auth')
}
if (-not $world) {
    if (Test-LocalPort -Port $settings.worldPort) { throw "World 端口 $($settings.worldPort) 已被其他程序占用。" }
    $worldStart = @{
        FilePath = $worldExe
        ArgumentList = $worldArgs
        WorkingDirectory = $paths.Runtime
        PassThru = $true
    }
    if ($VisibleWorld) { $worldStart.NoNewWindow = $true }
    else { $worldStart.WindowStyle = 'Hidden' }
    $world = Start-Process @worldStart
    [IO.File]::WriteAllText($worldPid, [string]$world.Id)
    $started.Add('World')
}

if ($started.Count) {
    Write-Host "已启动：$($started -join '、')。MySQL $($settings.mysqlPort)，Auth $($settings.authPort)，World $($settings.worldPort)。"
} else {
    Write-Host "服务端已经在运行，未重复启动。MySQL $($settings.mysqlPort)，Auth $($settings.authPort)，World $($settings.worldPort)。"
}
Write-Host '首次启动会自动导入数据库；进度可查看 D:\AzerothCore\runtime\Server.log。'

if ($VisibleWorld -and $started -contains 'World') {
    Write-Host '当前窗口已连接 WorldServer；可直接输入服务端命令。'
    Wait-Process -Id $world.Id
    if ((Test-Path -LiteralPath $worldPid) -and ((Get-Content -LiteralPath $worldPid -Raw).Trim() -eq [string]$world.Id)) {
        Remove-Item -LiteralPath $worldPid -Force
    }
}
