# 运行维护指南

- `install.ps1`：安装一个 release、准备便携 MySQL 和本地配置。
- `extract-client-data.ps1`：从 zhCN Build 12340 客户端提取地图数据。
- `start.ps1` / `stop.ps1`：启动或停止 MySQL、authserver、worldserver。
- `create-account.ps1`：通过 worldserver 控制台创建普通或 GM 账号。
- `configure-realm.ps1`：首次数据库导入完成后写入 Realm 名称、公网地址和 Build 12340。
- `backup.ps1` / `restore.ps1`：备份或恢复四个数据库和配置。
- `update.ps1`：先备份，再安装并切换到新的 release。

数据库只监听 127.0.0.1:3307。公网仅转发 3724/TCP 和 8085/TCP。首次 worldserver 启动会导入大量 SQL，不要强制结束进程。

首次安装前复制 `runtime.defaults.json` 为 `runtime.settings.json`，在副本中设置 `realmName`、`realmAddress` 和 `realmLocalAddress`。该副本已被 Git 忽略。

机器人首次生成按 100、500、2000 三阶段进行。达到 2000 后通过 `.server info` 观察延迟，并使用 `.ab mapstat`、`.ab creaturestat` 验证旧副本缩放。
