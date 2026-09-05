# RDF Expansion 使用说明

3.3.5a 客户端会根据角色等级隐藏旧资料片的随机地下城分类。`mod-rdf-expansion` 不修改客户端界面，而是在服务端收到随机队列请求后将资料片 ID 改写。

本发行版默认使用 WotLK，保证 80 级角色直接排随机普通/英雄地下城。切换命令：

```powershell
.\scripts\set-rdf-expansion.ps1 -Expansion Classic
.\scripts\set-rdf-expansion.ps1 -Expansion TBC
.\scripts\set-rdf-expansion.ps1 -Expansion WotLK
```

切换后重启 worldserver。80 级角色选择 Classic 或 TBC 模式时，客户端里仍然点击显示为 WotLK 的随机地下城入口；服务端会把请求重定向。Classic/TBC 的怪物等级由 AutoBalance 动态提升。

如果“随机英雄地下城”呈灰色，先检查角色平均装备等级；可使用随机普通地下城验证队列本身。Dungeon Clear 的即时补位开启后，会为真实玩家补齐缺少的坦克、治疗和 DPS。
