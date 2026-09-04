[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [string]$SettingsPath
)

& (Join-Path $PSScriptRoot 'backup.ps1') -SettingsPath $SettingsPath -Kind daily
& (Join-Path $PSScriptRoot 'stop.ps1') -SettingsPath $SettingsPath
& (Join-Path $PSScriptRoot 'install.ps1') -PackagePath $PackagePath -SettingsPath $SettingsPath -SkipMySqlSetup
Write-Host '版本已切换。运行 start.ps1，让数据库更新器完成新版本迁移。'
