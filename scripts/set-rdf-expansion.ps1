[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Classic', 'TBC', 'WotLK')][string]$Expansion,
    [string]$SettingsPath
)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$config = Get-ChildItem -LiteralPath $paths.Configs -Filter 'mod-rdf-expansion.conf' -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
if (-not $config) { throw '找不到 mod-rdf-expansion.conf；请先安装包含 RDF Expansion 的运行包。' }

$value = switch ($Expansion) {
    'Classic' { 0 }
    'TBC'     { 1 }
    'WotLK'   { 2 }
}
Set-ConfigValue -Path $config -Key 'RDF.Expansion' -Value ([string]$value)
Write-Host "RDF 已切换为 $Expansion（RDF.Expansion = $value）。重启 worldserver 后生效。"
if ($Expansion -ne 'WotLK') {
    Write-Host '80 级客户端仍应点击 WotLK 的随机地下城入口；模块会在服务端把请求改写到所选资料片。'
}
