[CmdletBinding(SupportsShouldProcess)]
param([string[]]$Name)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$path = Join-Path $repoRoot 'upstreams.lock.json'
$lock = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$entries = @($lock.core) + @($lock.modules)

foreach ($entry in $entries) {
    if ($Name -and $entry.name -notin $Name) { continue }
    $remote = git ls-remote $entry.repository "refs/heads/$($entry.branch)"
    if ($LASTEXITCODE -ne 0 -or -not $remote) { throw "无法读取 $($entry.name)。" }
    $latest = ($remote -split '\s+')[0]
    if ($latest -ne $entry.commit -and $PSCmdlet.ShouldProcess($entry.name, "锁定到 $latest")) {
        $entry.commit = $latest
    }
}
$lock.generatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
[IO.File]::WriteAllText($path, (($lock | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
