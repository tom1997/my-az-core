[CmdletBinding()]
param([string]$SettingsPath, [switch]$IncludeMySql)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
Stop-ProcessFromPidFile -PidFile (Join-Path $paths.State 'worldserver.pid') -Name 'worldserver'
Stop-ProcessFromPidFile -PidFile (Join-Path $paths.State 'authserver.pid') -Name 'authserver'
if ($IncludeMySql) { Stop-ProcessFromPidFile -PidFile (Join-Path $paths.State 'mysql.pid') -Name 'MySQL' }
