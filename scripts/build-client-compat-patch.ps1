[CmdletBinding()]
param(
    [string]$ClientPath = 'D:\AzerothCore\client-zhCN',
    [string]$WorldConfig = 'D:\AzerothCore\runtime\configs\worldserver.conf',
    [string]$MpqCli = 'C:\Users\Administrator\AppData\Local\Temp\azcore-mpqtools\mpqcli.exe',
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $OutputPath = Join-Path $ClientPath 'Data\zhCN\patch-zhCN-7.MPQ'
}

$dataPath = Join-Path $ClientPath 'Data'
$localePath = Join-Path $dataPath 'zhCN'
$workRoot = Join-Path $ClientPath ('PatchCompatWork-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$staging = Join-Path $workRoot 'staging'
New-Item -ItemType Directory -Path $staging -Force | Out-Null

if (-not (Test-Path -LiteralPath $MpqCli -PathType Leaf)) {
    throw "找不到 mpqcli：$MpqCli"
}

function Copy-ArchiveFile([string]$archive, [string]$file) {
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw "找不到补丁包：$archive"
    }
    & $MpqCli extract -o $staging -k -f $file $archive | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "无法从 $archive 提取 $file"
    }
}

# Re-apply Project Reforged's effective DBC files after the legacy zhCN patch set.
$sources = [ordered]@{
    (Join-Path $localePath 'patch-zhCN-5.MPQ') = @('DBFilesClient\Item.dbc')
    (Join-Path $dataPath 'patch-A.mpq') = @(
        'DBFilesClient\CharacterFacialHairStyles.dbc',
        'DBFilesClient\CharHairGeosets.dbc',
        'DBFilesClient\CharSections.dbc',
        'DBFilesClient\CreatureDisplayInfoExtra.dbc',
        'DBFilesClient\EmotesTextSound.dbc',
        'DBFilesClient\HelmetGeosetVisData.dbc'
    )
    (Join-Path $dataPath 'patch-C.mpq') = @(
        'DBFilesClient\CreatureDisplayInfo.dbc',
        'DBFilesClient\CreatureFamily.dbc',
        'DBFilesClient\CreatureModelData.dbc'
    )
    (Join-Path $dataPath 'patch-E.mpq') = @(
        'DBFilesClient\Light.dbc',
        'DBFilesClient\LightFloatBand.dbc',
        'DBFilesClient\LightIntBand.dbc',
        'DBFilesClient\LightParams.dbc',
        'DBFilesClient\LightSkybox.dbc'
    )
    (Join-Path $dataPath 'patch-G.mpq') = @('DBFilesClient\ItemDisplayInfo.dbc')
    (Join-Path $dataPath 'patch-S.mpq') = @(
        'DBFilesClient\AreaTable.dbc',
        'DBFilesClient\DungeonMap.dbc',
        'DBFilesClient\DungeonMapChunk.dbc',
        'DBFilesClient\SoundEntries.dbc',
        'DBFilesClient\SpellChainEffects.dbc',
        'DBFilesClient\SpellMissile.dbc',
        'DBFilesClient\SpellMissileMotion.dbc',
        'DBFilesClient\SpellVisual.dbc',
        'DBFilesClient\SpellVisualEffectName.dbc',
        'DBFilesClient\SpellVisualKit.dbc',
        'DBFilesClient\SpellVisualKitModelAttach.dbc',
        'DBFilesClient\WMOAreaTable.dbc',
        'DBFilesClient\WorldMapArea.dbc',
        'DBFilesClient\WorldMapTransforms.dbc',
        'DBFilesClient\ZoneMusic.dbc'
    )
}

foreach ($source in $sources.GetEnumerator()) {
    foreach ($file in $source.Value) {
        Copy-ArchiveFile $source.Key $file
    }
}

$configLine = Get-Content -LiteralPath $WorldConfig |
    Where-Object { $_ -match '^WorldDatabaseInfo\s*=' } |
    Select-Object -First 1
if (-not $configLine) {
    throw 'worldserver.conf 缺少 WorldDatabaseInfo。'
}
$dsn = (($configLine -split '=', 2)[1]).Trim().Trim('"').Split(';')
$mysql = Get-ChildItem 'D:\AzerothCore\mysql' -Filter mysql.exe -File -Recurse |
    Select-Object -First 1
if (-not $mysql) {
    throw '找不到便携 MySQL 客户端。'
}

$env:MYSQL_PWD = $dsn[3]
try {
    $pairs = @(& $mysql.FullName --protocol=tcp -h $dsn[0] -P $dsn[1] -u $dsn[2] -N -B `
        -e 'SELECT item_entry, source_entry FROM mod_mythic_rewards_item_pool ORDER BY item_entry' $dsn[4])
    if ($LASTEXITCODE -ne 0 -or $pairs.Count -eq 0) {
        throw '无法读取大秘境装备映射。'
    }
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}

$itemDbc = Join-Path $staging 'DBFilesClient\Item.dbc'
$bytes = [IO.File]::ReadAllBytes($itemDbc)
if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'WDBC') {
    throw 'Item.dbc 文件头无效。'
}
$recordCount = [BitConverter]::ToUInt32($bytes, 4)
$fieldCount = [BitConverter]::ToUInt32($bytes, 8)
$recordSize = [BitConverter]::ToUInt32($bytes, 12)
$stringSize = [BitConverter]::ToUInt32($bytes, 16)
if ($fieldCount -ne 8 -or $recordSize -ne 32) {
    throw "Item.dbc 结构不符合 WotLK 3.3.5：fields=$fieldCount, recordSize=$recordSize"
}

$records = @{}
for ($index = 0; $index -lt $recordCount; $index++) {
    $offset = 20 + ($index * $recordSize)
    $id = [BitConverter]::ToUInt32($bytes, $offset)
    $record = [byte[]]::new($recordSize)
    [Array]::Copy($bytes, $offset, $record, 0, $recordSize)
    $records[$id] = $record
}

$added = 0
foreach ($pair in $pairs) {
    $columns = $pair -split "`t"
    $customId = [uint32]$columns[0]
    $sourceId = [uint32]$columns[1]
    if (-not $records.ContainsKey($sourceId)) {
        throw "Item.dbc 缺少源装备 $sourceId，无法生成 $customId。"
    }
    $clone = [byte[]]$records[$sourceId].Clone()
    [Array]::Copy([BitConverter]::GetBytes($customId), 0, $clone, 0, 4)
    if (-not $records.ContainsKey($customId)) {
        $added++
    }
    $records[$customId] = $clone
}

$stringOffset = 20 + ($recordCount * $recordSize)
$stringBlock = [byte[]]::new($stringSize)
[Array]::Copy($bytes, $stringOffset, $stringBlock, 0, $stringSize)
$orderedIds = @($records.Keys | Sort-Object)
$stream = [IO.File]::Open($itemDbc, [IO.FileMode]::Create, [IO.FileAccess]::Write)
$writer = [IO.BinaryWriter]::new($stream)
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WDBC'))
    $writer.Write([uint32]$orderedIds.Count)
    $writer.Write([uint32]$fieldCount)
    $writer.Write([uint32]$recordSize)
    $writer.Write([uint32]$stringSize)
    foreach ($id in $orderedIds) {
        $writer.Write([byte[]]$records[$id])
    }
    $writer.Write($stringBlock)
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

if (Test-Path -LiteralPath $OutputPath) {
    throw "输出补丁已经存在，请先备份：$OutputPath"
}
& $MpqCli create -g wow-wotlk -o $OutputPath $staging | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw '创建客户端兼容补丁失败。'
}

Write-Host "已创建 $OutputPath"
Write-Host "Item.dbc 新增 $added 条大秘境装备记录，总记录数 $($orderedIds.Count)。"
Write-Host "工作目录：$workRoot"
