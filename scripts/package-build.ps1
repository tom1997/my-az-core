[CmdletBinding()]
param(
    [ValidateSet('stable', 'enhanced')][string]$Profile,
    [string]$WorkingRoot = 'C:\azbuild',
    [string]$ArtifactRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path $WorkingRoot 'source'
$distRoot = Join-Path $sourceRoot 'env\dist'
if (-not (Test-Path -LiteralPath $distRoot)) { throw "找不到构建输出：$distRoot" }
$auth = Get-ChildItem -LiteralPath $distRoot -Filter 'authserver.exe' -File -Recurse | Select-Object -First 1
$world = Get-ChildItem -LiteralPath $distRoot -Filter 'worldserver.exe' -File -Recurse | Select-Object -First 1
if (-not $auth -or -not $world) { throw '构建输出缺少 authserver.exe 或 worldserver.exe。' }

New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
$stage = Join-Path $WorkingRoot "package-$Profile"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath $distRoot -Destination (Join-Path $stage 'dist') -Recurse

$sourceData = Join-Path $stage 'source-data'
New-Item -ItemType Directory -Path $sourceData | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRoot 'data') -Destination (Join-Path $sourceData 'data') -Recurse
foreach ($module in Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'modules') -Directory) {
    $sql = Join-Path $module.FullName 'data\sql'
    if (Test-Path -LiteralPath $sql) {
        $destination = Join-Path $sourceData "modules\$($module.Name)\data\sql"
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $sql -Destination $destination -Recurse
    }
}

$lock = Get-Content -LiteralPath (Join-Path $WorkingRoot 'upstreams.lock.json') -Raw | ConvertFrom-Json
$manifest = [ordered]@{
    schemaVersion = 1
    profile = $Profile
    builtAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    core = $lock.core
    modules = @($lock.modules | Where-Object { $_.profiles -contains $Profile })
}
[IO.File]::WriteAllText((Join-Path $stage 'source-manifest.json'), (($manifest | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))

$symbolsStage = Join-Path $WorkingRoot "symbols-$Profile"
if (Test-Path -LiteralPath $symbolsStage) { Remove-Item -LiteralPath $symbolsStage -Recurse -Force }
New-Item -ItemType Directory -Path $symbolsStage | Out-Null
$runtimeDist = Join-Path $stage 'dist'
$symbolSources = @(
    [pscustomobject]@{ Root = $runtimeDist; Prefix = 'dist'; RemoveFromRuntime = $true },
    [pscustomobject]@{ Root = (Join-Path $sourceRoot 'var\build\obj'); Prefix = 'build'; RemoveFromRuntime = $false }
)
$symbolCount = 0
foreach ($symbolSource in $symbolSources) {
    foreach ($pdb in Get-ChildItem -LiteralPath $symbolSource.Root -Filter '*.pdb' -File -Recurse -ErrorAction SilentlyContinue) {
        $relative = [IO.Path]::GetRelativePath($symbolSource.Root, $pdb.FullName)
        $destination = Join-Path $symbolsStage (Join-Path $symbolSource.Prefix $relative)
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $pdb.FullName -Destination $destination -Force
        $symbolCount++
        if ($symbolSource.RemoveFromRuntime) { Remove-Item -LiteralPath $pdb.FullName -Force }
    }
}
if ($symbolCount -eq 0) { throw '构建成功，但没有找到任何 PDB 调试符号。' }
Copy-Item -LiteralPath (Join-Path $stage 'source-manifest.json') -Destination $symbolsStage
Copy-Item -LiteralPath (Join-Path $stage 'source-manifest.json') -Destination (Join-Path $ArtifactRoot "$Profile-source-manifest.json") -Force

$runtimeZip = Join-Path $ArtifactRoot "$Profile-runtime.zip"
$symbolsZip = Join-Path $ArtifactRoot "$Profile-debug-symbols.zip"
Remove-Item -LiteralPath $runtimeZip,$symbolsZip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $runtimeZip -CompressionLevel Optimal
Compress-Archive -Path (Join-Path $symbolsStage '*') -DestinationPath $symbolsZip -CompressionLevel Optimal

$hashes = @($runtimeZip, $symbolsZip) | ForEach-Object {
    $hash = Get-FileHash -LiteralPath $_ -Algorithm SHA256
    "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_))"
}
[IO.File]::WriteAllLines((Join-Path $ArtifactRoot "$Profile-SHA256SUMS.txt"), $hashes, [Text.UTF8Encoding]::new($false))
Write-Host "已生成 $runtimeZip 和 $symbolsZip"
