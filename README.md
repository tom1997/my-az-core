# my-az-core

可复现构建、运行和二次开发 AzerothCore 3.3.5a Playerbots 的个人发行仓库。

## 当前组合

- Playerbots 专用 AzerothCore Core
- Playerbots
- AutoBalance 动态等级/人数缩放
- RDF Expansion（默认 WotLK，可一键切换 Classic/TBC）
- AOE Loot
- Transmog
- Dungeon Clear（机器人坦克自主路线、拉怪、开门和清理 Boss）
- AHBot（独立拍卖行做市，可自动出售和收购）
- Mythic Plus（钥石、限时、词缀、层数与奖励）
- Random Enchants（仅 enhanced 包，默认关闭）

上游版本全部固定在 [`upstreams.lock.json`](upstreams.lock.json)，不会在生产构建中静默追随 master。

## 快速开始

1. 从 Releases 下载 `stable-runtime.zip` 或 `enhanced-runtime.zip`。
2. 自行准备合法的简体中文 WoW 3.3.5a Build 12340 客户端，放在 `D:\AzerothCore\client-zhCN`。
3. 复制 `runtime.defaults.json` 为不提交的 `runtime.settings.json`，填写 Realm 名称和公网地址。
4. 在 PowerShell 中运行：

```powershell
.\scripts\install.ps1 -PackagePath D:\Downloads\stable-runtime.zip
.\scripts\extract-client-data.ps1
.\scripts\start.ps1
.\scripts\configure-realm.ps1
```

首次启动会由 AzerothCore 数据库更新器导入基础库和模块 SQL，耗时较长。随后使用 `create-account.ps1` 创建账号。

Windows 下也可直接双击仓库根目录的 `启动服务端.cmd` 和 `关闭服务端.cmd`。关闭入口会按 World、Auth、MySQL 的顺序停止服务，并让 MySQL 安全刷盘退出。

## 开发模块

```powershell
.\scripts\new-module.ps1 -Name MyFeature
```

生成的模块位于 `modules/custom/mod-my-feature`。提交并推送后，GitHub Actions 会在 Windows 上同时验证 stable 和 enhanced 构建。详细说明见 [`CONTRIBUTING.md`](CONTRIBUTING.md) 和 [`docs/development.zh-CN.md`](docs/development.zh-CN.md)。

Dungeon Clear 的启用条件、命令和默认安全设置见 [`docs/dungeon-clear.zh-CN.md`](docs/dungeon-clear.zh-CN.md)。

拍卖行机器人和大秘境的启用步骤分别见 [`docs/ahbot.zh-CN.md`](docs/ahbot.zh-CN.md) 与 [`docs/mythic-plus.zh-CN.md`](docs/mythic-plus.zh-CN.md)。RDF 资料片切换见 [`docs/rdf-expansion.zh-CN.md`](docs/rdf-expansion.zh-CN.md)。

## 重要边界

- 仓库不包含游戏客户端、数据库、密码或正式服配置。
- 本机运行不依赖 Docker。
- 默认数据库仅监听 `127.0.0.1:3307`。
- 只应向公网转发 3724/TCP 与 8085/TCP。
