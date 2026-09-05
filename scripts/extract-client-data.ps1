[CmdletBinding()]
param([string]$SettingsPath, [switch]$SkipMMaps)

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
$settings = Get-RuntimeSettings -SettingsPath $SettingsPath
$paths = Get-AzPaths -Settings $settings
$releasePath = (Get-Content -LiteralPath (Join-Path $paths.State 'current-release.txt') -Raw).Trim()
$dist = Join-Path $releasePath 'dist'
$wowExe = Join-Path $paths.Client 'Wow.exe'
if (-not (Test-Path -LiteralPath $wowExe)) { throw "找不到客户端：$wowExe" }
$version = (Get-Item -LiteralPath $wowExe).VersionInfo
if ("$($version.FileVersion) $($version.ProductVersion)" -notmatch '12340') { throw '客户端不是 Build 12340。' }

$toolNames = @('map_extractor.exe', 'vmap4_extractor.exe', 'vmap4_assembler.exe', 'mmaps_generator.exe', 'mmaps-config.yaml')
foreach ($name in $toolNames) {
    $tool = Get-ChildItem -LiteralPath $dist -Filter $name -File -Recurse | Select-Object -First 1
    if (-not $tool -and ($name -ne 'mmaps-config.yaml')) { throw "运行包缺少提取器：$name" }
    if ($tool) { Copy-Item -LiteralPath $tool.FullName -Destination (Join-Path $paths.Client $name) -Force }
}
Get-ChildItem -LiteralPath $dist -Filter '*.dll' -File -Recurse | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $paths.Client $_.Name) -Force
}

Push-Location $paths.Client
try {
    & .\map_extractor.exe
    if ($LASTEXITCODE -ne 0) { throw 'mapextractor 执行失败。' }
    New-Item -ItemType Directory -Path 'Buildings','vmaps' -Force | Out-Null
    & .\vmap4_extractor.exe
    if ($LASTEXITCODE -ne 0) { throw 'vmap4extractor 执行失败。' }
    & .\vmap4_assembler.exe Buildings vmaps
    if ($LASTEXITCODE -ne 0) { throw 'vmap4assembler 执行失败。' }
    if (-not $SkipMMaps) {
        New-Item -ItemType Directory -Path 'mmaps' -Force | Out-Null
        & .\mmaps_generator.exe
        if ($LASTEXITCODE -ne 0) { throw 'mmaps_generator 执行失败。' }
    }
} finally {
    Pop-Location
}

foreach ($folder in @('dbc', 'maps', 'vmaps', 'mmaps', 'Cameras')) {
    $source = Join-Path $paths.Client $folder
    if (-not (Test-Path -LiteralPath $source)) {
        if ($folder -eq 'mmaps' -and $SkipMMaps) { continue }
        if ($folder -eq 'Cameras') { continue }
        throw "提取结果缺少 $folder。"
    }
    $destination = Join-Path $paths.Data $folder
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    & robocopy $source $destination /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -gt 7) { throw "复制 $folder 失败，robocopy 退出码 $LASTEXITCODE。" }
}
Write-Host "客户端数据已放入 $($paths.Data)。"
