# AHBot 使用说明

`mod-ah-bot` 是独立的拍卖行做市机器人，不是 2000 个 Playerbot 中的某一个。它可以持续上架物品，也可以购买价格合理的玩家拍卖。

## 首次启用

1. 使用 `create-account.ps1` 创建一个普通账号（不要设 GM，也不要使用 Playerbot 账号）。
2. 用客户端登录该账号，创建一个专用角色，例如 `Marketbot`，进入世界一次后退出。
3. 保持 MySQL 运行，执行：

```powershell
.\scripts\configure-ahbot.ps1 -CharacterName Marketbot
```

4. 重启 worldserver。

安装脚本不会自动启用 AHBot，因为模块必须先绑定一个真实存在的专用角色。默认配置禁止商店货和任务/拾取绑定物品，限制同一物品最多三个重复堆栈，降低刷钱和拍卖行灌水风险。

不要用 AHBot 角色正常登录或浏览拍卖行；模块运行期间该角色由服务端专用。
