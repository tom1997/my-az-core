[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "my-az-core-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $config = Join-Path $testRoot 'test.conf'
    [IO.File]::WriteAllText($config, "Alpha = 1`r`nBeta.Value = old`r`n", [Text.UTF8Encoding]::new($false))
    Set-ConfigValue -Path $config -Key 'Beta.Value' -Value 'new'
    Set-ConfigValue -Path $config -Key 'Gamma' -Value '"text"'
    $result = Get-Content -LiteralPath $config -Raw
    if ($result -notmatch '(?m)^Beta\.Value = new\r?$') { throw 'Set-ConfigValue 更新测试失败。' }
    if ($result -notmatch '(?m)^Gamma = "text"\r?$') { throw 'Set-ConfigValue 插入测试失败。' }

    $a = New-RandomPassword
    $b = New-RandomPassword
    if ($a.Length -lt 32 -or $a -eq $b) { throw '随机密码测试失败。' }

    $rejected = $false
    try { Assert-SafeInstallRoot -Path 'D:\' } catch { $rejected = $true }
    if (-not $rejected) { throw '安装根目录安全检查测试失败。' }
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
Write-Host '辅助函数自测通过。'
