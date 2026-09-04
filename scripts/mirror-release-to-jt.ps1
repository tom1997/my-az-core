[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })][string]$ReleaseDirectory,
    [string]$SshTarget = 'jt'
)

$name = Split-Path -Leaf (Resolve-Path $ReleaseDirectory)
$remote = "/data/tom/my-az-core/releases/$name"
ssh $SshTarget "mkdir -p '$remote'"
if ($LASTEXITCODE -ne 0) { throw '无法创建 jt 归档目录。' }
scp -r "$ReleaseDirectory\*" "$SshTarget`:$remote/"
if ($LASTEXITCODE -ne 0) { throw '上传 jt 归档失败。' }
Write-Host "已归档到 $SshTarget`:$remote"
