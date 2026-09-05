[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{3,16}$')][string]$Username,
    [ValidateRange(0,3)][int]$GmLevel = 0,
    [string]$SettingsPath
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
if (Get-Process worldserver -ErrorAction SilentlyContinue) { throw '请先停止正在运行的 worldserver。' }
try { Wait-TcpPort -Port $settings.mysqlPort -TimeoutSeconds 1 } catch { throw 'MySQL 未运行，请先执行 start.ps1，再停止 worldserver/authserver 或单独启动 MySQL。' }
$secure = Read-Host "输入账号 $Username 的密码（3-16 位）" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ($password.Length -lt 3 -or $password.Length -gt 16 -or $password -match '\s') { throw '密码必须为 3-16 位且不能包含空白字符。' }

$releasePath = (Get-Content -LiteralPath (Join-Path $paths.State 'current-release.txt') -Raw).Trim()
$bin = Get-ReleaseBinPath -ReleasePath $releasePath
$world = Join-Path $bin 'worldserver.exe'
$commands = @("account create $Username $password", "account set gmlevel $Username $GmLevel -1", 'server shutdown 1')
Push-Location $bin
try {
    $commands | & $world -c (Join-Path $paths.Configs 'worldserver.conf')
    if ($LASTEXITCODE -ne 0) { throw "worldserver 维护模式退出码：$LASTEXITCODE" }
} finally {
    Pop-Location
    $password = $null
}
Write-Host "账号 $Username 已创建，GM 等级 $GmLevel。"
