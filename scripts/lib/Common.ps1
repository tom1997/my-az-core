Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepositoryRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-RuntimeSettings {
    param([string]$SettingsPath)

    $repoRoot = Get-RepositoryRoot
    if (-not $SettingsPath) {
        $local = Join-Path $repoRoot 'runtime.settings.json'
        $SettingsPath = if (Test-Path -LiteralPath $local) { $local } else { Join-Path $repoRoot 'runtime.defaults.json' }
    }
    return Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
}

function Get-AzPaths {
    param([object]$Settings)

    $root = [IO.Path]::GetFullPath([string]$Settings.installRoot)
    return [pscustomobject]@{
        Root       = $root
        Client     = [IO.Path]::GetFullPath([string]$Settings.clientPath)
        Releases   = Join-Path $root 'releases'
        Runtime    = Join-Path $root 'runtime'
        Bin        = Join-Path $root 'runtime\bin'
        Configs    = Join-Path $root 'runtime\configs'
        Data       = Join-Path $root 'runtime\data'
        SourceData = Join-Path $root 'runtime\source-data'
        Logs       = Join-Path $root 'runtime\logs'
        MySql      = Join-Path $root 'mysql'
        MySqlBin   = Join-Path $root 'mysql\server\bin'
        MySqlData  = Join-Path $root 'mysql\data'
        MyCnf      = Join-Path $root 'mysql\my.ini'
        Backups    = Join-Path $root 'backups'
        State      = Join-Path $root 'runtime\state'
        Secrets    = Join-Path $root 'runtime\state\secrets.json'
    }
}

function Get-ReleaseBinPath {
    param([Parameter(Mandatory)][string]$ReleasePath)

    foreach ($candidate in @(
        (Join-Path $ReleasePath 'dist\bin'),
        (Join-Path $ReleasePath 'dist')
    )) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'worldserver.exe')) {
            return $candidate
        }
    }
    throw "当前 release 中找不到 worldserver.exe：$ReleasePath"
}

function Assert-SafeInstallRoot {
    param([string]$Path)

    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $driveRoot = [IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($full -eq $driveRoot -or $full.Length -lt 6) {
        throw "拒绝使用过于宽泛的安装目录：$full"
    }
}

function Set-ConfigValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    $escaped = [regex]::Escape($Key)
    $content = Get-Content -LiteralPath $Path -Raw
    $line = "$Key = $Value"
    if ($content -match "(?m)^\s*$escaped\s*=") {
        $content = [regex]::Replace($content, "(?m)^\s*$escaped\s*=.*$", $line, 1)
    } else {
        $content = $content.TrimEnd() + "`r`n$line`r`n"
    }
    [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
}

function Get-Secrets {
    param([object]$Paths)
    if (-not (Test-Path -LiteralPath $Paths.Secrets)) {
        throw "找不到密钥文件：$($Paths.Secrets)。请先运行 install.ps1。"
    }
    return Get-Content -LiteralPath $Paths.Secrets -Raw | ConvertFrom-Json
}

function New-RandomPassword {
    param([int]$Length = 32)
    $bytes = [byte[]]::new($Length)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('/', '_').Replace('+', '-')
}

function Wait-TcpPort {
    param([string]$HostName = '127.0.0.1', [int]$Port, [int]$TimeoutSeconds = 60)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $task = $client.ConnectAsync($HostName, $Port)
            if ($task.Wait(500) -and $client.Connected) { return }
        } catch { } finally { $client.Dispose() }
        Start-Sleep -Milliseconds 500
    }
    throw "等待 $HostName`:$Port 超时。"
}

function Invoke-MySql {
    param(
        [object]$Paths,
        [int]$Port,
        [string]$User,
        [string]$Password,
        [string]$Sql,
        [string]$Database
    )
    $mysql = Join-Path $Paths.MySqlBin 'mysql.exe'
    if (-not (Test-Path -LiteralPath $mysql)) { throw "找不到 mysql.exe：$mysql" }
    $old = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $Password
        $args = @('--protocol=tcp', '--host=127.0.0.1', "--port=$Port", "--user=$User", '--default-character-set=utf8mb4')
        if ($Database) { $args += $Database }
        $args += @('--execute', $Sql)
        & $mysql @args
        if ($LASTEXITCODE -ne 0) { throw "MySQL 命令执行失败，退出码 $LASTEXITCODE。" }
    } finally {
        $env:MYSQL_PWD = $old
    }
}

function Stop-ProcessFromPidFile {
    param([string]$PidFile, [string]$Name)
    if (-not (Test-Path -LiteralPath $PidFile)) { return }
    $processId = [int](Get-Content -LiteralPath $PidFile -Raw).Trim()
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $processId
        try {
            Wait-Process -Id $processId -Timeout 30 -ErrorAction Stop
        } catch {
            if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
                Stop-Process -Id $processId -Force
            }
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Write-Host "$Name 已停止。"
}
