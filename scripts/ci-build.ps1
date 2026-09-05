[CmdletBinding()]
param(
    [ValidateSet('stable', 'enhanced')][string]$Profile = 'stable',
    [ValidateSet('Release', 'RelWithDebInfo')][string]$BuildType = 'RelWithDebInfo',
    [string]$WorkingRoot = 'C:\azbuild',
    [string]$ArtifactRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $ArtifactRoot) { $ArtifactRoot = Join-Path $repoRoot 'artifacts' }

& (Join-Path $PSScriptRoot 'prepare-source.ps1') -Profile $Profile -WorkingRoot $WorkingRoot
$sourceRoot = Join-Path $WorkingRoot 'source'

if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    choco install ninja -y --no-progress
    if ($LASTEXITCODE -ne 0) { throw '安装 Ninja 失败。' }
}

$boostRoot = 'C:\local\boost_1_87_0'
if (-not (Test-Path -LiteralPath (Join-Path $boostRoot 'boost\version.hpp'))) {
    $boostExe = Join-Path $env:RUNNER_TEMP 'boost_1_87_0.exe'
    Invoke-WebRequest -Uri 'https://archives.boost.io/release/1.87.0/binaries/boost_1_87_0-msvc-14.3-64.exe' -OutFile $boostExe
    if ((Get-Item -LiteralPath $boostExe).Length -lt 50MB) { throw 'Boost 下载文件异常。' }
    $process = Start-Process -FilePath $boostExe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$boostRoot" -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Boost 安装失败：$($process.ExitCode)" }
}

$mysqlRoot = 'C:\tools\mysql\current'
if (-not (Test-Path -LiteralPath (Join-Path $mysqlRoot 'lib\mysqlclient.lib'))) {
    $mysqlZip = Join-Path $env:RUNNER_TEMP 'mysql-8.4.9-winx64.zip'
    Invoke-WebRequest -Uri 'https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.9-winx64.zip' -OutFile $mysqlZip -UserAgent 'Mozilla/5.0'
    if ((Get-Item -LiteralPath $mysqlZip).Length -lt 50MB) { throw 'MySQL 下载文件异常。' }
    New-Item -ItemType Directory -Path 'C:\tools\mysql' -Force | Out-Null
    Expand-Archive -LiteralPath $mysqlZip -DestinationPath 'C:\tools\mysql' -Force
    if (Test-Path -LiteralPath $mysqlRoot) { Remove-Item -LiteralPath $mysqlRoot -Recurse -Force }
    Rename-Item -LiteralPath 'C:\tools\mysql\mysql-8.4.9-winx64' -NewName 'current'
}

$opensslRoot = @($env:OPENSSL_ROOT_DIR, 'C:\Program Files\OpenSSL', 'C:\Program Files\OpenSSL-Win64') |
    Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'include\openssl\opensslv.h')) } |
    Select-Object -First 1
if (-not $opensslRoot) { throw 'Windows runner 上未找到 OpenSSL 开发文件。' }
if (Test-Path -LiteralPath 'C:\openssl') { Remove-Item -LiteralPath 'C:\openssl' -Force }
New-Item -ItemType Junction -Path 'C:\openssl' -Target $opensslRoot | Out-Null

$configDir = Join-Path $sourceRoot 'conf'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$cmakeOptions = "-DBOOST_ROOT=C:/local/boost_1_87_0 -DMYSQL_ROOT_DIR=C:/tools/mysql/current -DOPENSSL_ROOT_DIR=C:/openssl -DOPENSSL_USE_STATIC_LIBS=FALSE -DCMAKE_RC_COMPILER=rc -DCMAKE_NINJA_FORCE_RESPONSE_FILE=ON -DCMAKE_NINJA_CMCLDEPS_RC=OFF -DCMAKE_C_USE_RESPONSE_FILE_FOR_OBJECTS=ON -DCMAKE_CXX_USE_RESPONSE_FILE_FOR_OBJECTS=ON -DCMAKE_C_USE_RESPONSE_FILE_FOR_INCLUDES=ON -DCMAKE_CXX_USE_RESPONSE_FILE_FOR_INCLUDES=ON -DCMAKE_C_USE_RESPONSE_FILE_FOR_LIBRARIES=ON -DCMAKE_CXX_USE_RESPONSE_FILE_FOR_LIBRARIES=ON"
$config = @"
CCOMPILERC="cl"
CCOMPILERCXX="cl"
CTYPE="$BuildType"
CSCRIPTS="static"
CMODULES="static"
CTOOLS_BUILD="all"
CCUSTOMOPTIONS="$cmakeOptions"
"@
[IO.File]::WriteAllText((Join-Path $configDir 'config.sh'), $config, [Text.UTF8Encoding]::new($false))

$env:BOOST_ROOT = $boostRoot
$env:MYSQL_ROOT_DIR = $mysqlRoot
$env:OPENSSL_ROOT_DIR = 'C:\openssl'
$env:CTOOLS_BUILD = 'all'
$env:CMAKE_GENERATOR = 'Ninja'
$env:CC = 'cl'
$env:CXX = 'cl'
$env:RC = 'rc'
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { throw "找不到 Git Bash：$bash" }
& $bash -lc "cd /c/azbuild/source && ./acore.sh compiler build"
if ($LASTEXITCODE -ne 0) { throw "AzerothCore $Profile 构建失败。" }

$buildRoot = Join-Path $sourceRoot 'var\build\obj'
& cmake --install $buildRoot --config $BuildType
if ($LASTEXITCODE -ne 0) { throw "AzerothCore $Profile 安装到发布目录失败。" }

$distRoot = Join-Path $sourceRoot 'env\dist'
$runtimeBin = (Get-ChildItem -LiteralPath $distRoot -Filter 'authserver.exe' -File -Recurse | Select-Object -First 1).DirectoryName
if (-not $runtimeBin) { throw '安装后找不到 authserver.exe。' }
$runtimeDependencies = @(
    (Join-Path $mysqlRoot 'lib\libmysql.dll')
) + @(Get-ChildItem -LiteralPath $opensslRoot -Filter 'libcrypto-3*.dll' -File -Recurse | Select-Object -ExpandProperty FullName) +
    @(Get-ChildItem -LiteralPath $opensslRoot -Filter 'libssl-3*.dll' -File -Recurse | Select-Object -ExpandProperty FullName) +
    @(Get-ChildItem -LiteralPath $opensslRoot -Filter 'legacy.dll' -File -Recurse | Select-Object -ExpandProperty FullName)
if (-not ($runtimeDependencies | Where-Object { [IO.Path]::GetFileName($_) -ieq 'legacy.dll' })) {
    throw "OpenSSL 运行时中找不到 legacy.dll：$opensslRoot"
}
foreach ($dependency in $runtimeDependencies | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $dependency)) { throw "缺少运行时依赖：$dependency" }
    Copy-Item -LiteralPath $dependency -Destination $runtimeBin -Force
}

& (Join-Path $PSScriptRoot 'package-build.ps1') -Profile $Profile -WorkingRoot $WorkingRoot -ArtifactRoot $ArtifactRoot
