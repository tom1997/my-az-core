# Mythic Plus 使用说明

本发行版集成 `silviu20092/mod-mythic-plus`：纯 C++、无需 Eluna 或客户端补丁，适合现有 Playerbot 与 Dungeon Clear 队伍。它提供钥石、层数、计时、死亡罚时、词缀、排行榜记录和通关奖励。

## 首次使用

数据库更新器首次启动新版本时会自动导入模块表。随后用 GM 角色在希望放置入口的位置执行：

```text
.npc add 200005
```

与 Mythic Plus NPC 对话选择层数并购买钥石，组成 5 人队，进入支持的地下城后由队长使用钥石。测试阶段钥石购买没有冷却，死亡罚时为 5 秒。

本发行版将入口限制为 12 个 WotLK 英雄五人本。层数与奖励由世界数据库中的 `mythic_plus_level`、`mythic_plus_affix` 和 `mythic_plus_level_rewards` 控制。它接管大秘境中的怪物等级、生命和伤害；这 12 张地图已经加入 `AutoBalance.Disable.PerInstance`，避免生命与伤害双重缩放。Classic/TBC RDF 的其他地图仍由 AutoBalance 负责。

这套模块接近 7.x 的“钥石＋限时＋词缀”核心循环，但没有官方客户端的敌方部队 UI、每周宝库和完整评分界面。Playerbot 不理解所有现代词缀，首轮建议从 +1 到 +3 验证走位与生存，再逐步提高。
