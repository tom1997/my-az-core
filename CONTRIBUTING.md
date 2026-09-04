# 开发约定

## 修改原则

1. 新功能优先写入 `modules/custom/`，不要直接修改上游 Core。
2. 必须修改上游时，将最小补丁放入 `patches/`，并解释为什么现有脚本钩子不足。
3. 配置项必须提供 `.conf.dist`、默认值和注释；机密值不得提交。
4. 数据库修改放入模块自己的 `data/sql/db-auth`、`db-characters` 或 `db-world`，SQL 必须可重复执行。
5. 玩家可见文本应走 AzerothCore 的本地化字符串系统。

## 工作流

1. 从主分支建立功能分支。
2. 使用 `scripts/new-module.ps1` 创建模块，或修改已有自定义模块。
3. 运行 `scripts/check.ps1`。
4. 推送分支，等待 stable/enhanced Windows 构建。
5. 合并后以 `vYYYY.MM.DD.N` 标签触发正式发布。

## 验收要求

- 不提交客户端、构建产物、PDB、数据库或密码。
- stable 与 enhanced 均能编译。
- 新 SQL 能对同一数据库安全重复执行。
- 新模块至少记录登录、命令或目标玩法的手工验证步骤。
