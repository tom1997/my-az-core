[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9-]{1,40}$')][string]$Name
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$slug = ($Name -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLowerInvariant()
if (-not $slug.StartsWith('mod-')) { $slug = "mod-$slug" }
$target = Join-Path $repoRoot "modules\custom\$slug"
if (Test-Path -LiteralPath $target) { throw "模块已存在：$target" }

git clone --depth 1 https://github.com/azerothcore/skeleton-module.git $target
if ($LASTEXITCODE -ne 0) { throw '下载 AzerothCore skeleton-module 失败。' }
$gitDir = Join-Path $target '.git'
if (Test-Path -LiteralPath $gitDir) { Remove-Item -LiteralPath $gitDir -Recurse -Force }

$readme = Join-Path $target 'README.md'
[IO.File]::WriteAllText($readme, "# $slug`n`n由 my-az-core 模组脚手架创建。`n", [Text.UTF8Encoding]::new($false))
$examples = Join-Path $target 'examples'
New-Item -ItemType Directory -Path $examples | Out-Null
$exampleText = @'
// 示例文件，不参与编译。按需将片段复制到 src/ 并根据当前 AzerothCore Hook 签名调整。
#include "Chat.h"
#include "Creature.h"
#include "Player.h"
#include "ScriptMgr.h"

// 可从以下脚本类型开始：
// class MyWorldScript : public WorldScript { ... };
// class MyPlayerScript : public PlayerScript { ... };
// class MyCreatureScript : public CreatureScript { ... };
// class MyCommandScript : public CommandScript { ... };

// 玩家可见文字应通过 acore_string 或数据库本地化表提供，不要硬编码单一语言。
'@
[IO.File]::WriteAllText((Join-Path $examples 'ScriptTypes.cpp.example'), $exampleText, [Text.UTF8Encoding]::new($false))

foreach ($db in @('db-auth', 'db-characters', 'db-world')) {
    $dir = Join-Path $target "data\sql\$db"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $keep = Join-Path $dir '.gitkeep'
    if (-not (Test-Path -LiteralPath $keep)) { New-Item -ItemType File -Path $keep | Out-Null }
}

Write-Host "已创建 $target"
Write-Host '下一步：修改 README、conf 和 src，然后运行 scripts/check.ps1。'
