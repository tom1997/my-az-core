[CmdletBinding()]
param([string]$SettingsPath)

$script = (Resolve-Path (Join-Path $PSScriptRoot 'backup.ps1')).Path
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
if ($SettingsPath) { $argument += " -SettingsPath `"$SettingsPath`"" }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
$trigger = New-ScheduledTaskTrigger -Daily -At '04:00'
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'MyAzerothCore-DailyBackup' -Action $action -Trigger $trigger -Principal $principal -Description 'AzerothCore 四库与配置每日备份' -Force | Out-Null
Write-Host '已注册每日 04:00 备份任务（仅在当前用户登录时运行）。'
