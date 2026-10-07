# 运行维护指南

- `install.ps1`：安装一个 release、准备便携 MySQL 和本地配置。
- `extract-client-data.ps1`：从 zhCN Build 12340 客户端提取地图数据。
- `start.ps1` / `stop.ps1`：启动或停止 MySQL、authserver、worldserver。
- `create-account.ps1`：通过 worldserver 控制台创建普通或 GM 账号。
- `configure-realm.ps1`：首次数据库导入完成后写入 Realm 名称、公网地址和 Build 12340。
- `backup.ps1` / `restore.ps1`：备份或恢复四个数据库和配置。
- `update.ps1`：先备份，再安装并切换到新的 release。
- `update-from-github.ps1`：自动下载 GitHub 的最新成功构建或正式 Release，校验后执行完整更新并重新启动。

## 一键自动更新

日常测试当前开发分支的新构建，等 GitHub Actions 的 stable/enhanced 两项均成功后，双击仓库根目录的：

```text
自动更新测试版.cmd
```

脚本会自动沿用本机当前的 stable 或 enhanced 配置，执行：

```text
确认最新构建已成功
→ 下载对应运行包
→ SHA-256 校验
→ 检查是否已经安装
→ 每日备份
→ 安全停止 World/Auth
→ 安装并切换 release
→ 自动执行数据库更新并启动 WorldServer 前台窗口
```

正式发布版本使用 `自动更新正式版.cmd`。测试版下载依赖已经登录的 GitHub CLI；如果更换电脑，先运行一次 `gh auth login`。

也可以从 PowerShell 指定分支、包类型或更新通道：

```powershell
.\scripts\update-from-github.ps1 -Channel dev -Branch codex/playerbot-pvp-tactical -Profile enhanced -VisibleWorld
.\scripts\update-from-github.ps1 -Channel release -Profile stable -VisibleWorld
```

下载目录位于安装盘并会在完成后自动清理。新 release 的目录名包含构建 commit，因此同一天的多次 Playerbot 修改不会互相覆盖。若最新构建仍在运行或失败，脚本会停止并保留当前服务端版本。

数据库只监听 127.0.0.1:3307。公网仅转发 3724/TCP 和 8085/TCP。首次 worldserver 启动会导入大量 SQL，不要强制结束进程。

首次安装前复制 `runtime.defaults.json` 为 `runtime.settings.json`，在副本中设置 `realmName`、`realmAddress` 和 `realmLocalAddress`。该副本已被 Git 忽略。

机器人首次生成按 100、500、2000 三阶段进行。达到 2000 后通过 `.server info` 观察延迟，并使用 `.ab mapstat`、`.ab creaturestat` 验证旧副本缩放。
