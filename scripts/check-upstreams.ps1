[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lock = Get-Content -LiteralPath (Join-Path $repoRoot 'upstreams.lock.json') -Raw | ConvertFrom-Json
$entries = @($lock.core) + @($lock.modules)

$rows = foreach ($entry in $entries) {
    $remote = git ls-remote $entry.repository "refs/heads/$($entry.branch)"
    if ($LASTEXITCODE -ne 0 -or -not $remote) { throw "无法读取 $($entry.name) 的远程分支。" }
    $latest = ($remote -split '\s+')[0]
    [pscustomobject]@{
        Name    = $entry.name
        Branch  = $entry.branch
        Locked  = $entry.commit.Substring(0, 12)
        Latest  = $latest.Substring(0, 12)
        Update  = $latest -ne $entry.commit
    }
}
$rows | Format-Table -AutoSize
