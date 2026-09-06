# Playerbot PvP Tactical：空间控制第一阶段

本发行版通过 `patches/0004-playerbot-pvp-tactical-ranged.patch` 增加共享 PvP 空间控制器。它不是需要逐个机器人添加的游戏内策略；是否启用、在哪些场景启用以及距离参数全部由 `playerbots.conf` 决定。

## 行为范围

首版覆盖当前天赋定位为远程或治疗的机器人：猎人、法师、术士、牧师、元素/恢复萨满、平衡/恢复德鲁伊和神圣圣骑士。增强只在当前目标确实是玩家时工作，不改变 PvE 副本战斗。

近战机器人同时启用轻量抓背机制。进入近战范围后，如果机器人仍在目标的正面半区，会选择碰撞检测通过且距离较短的一侧移动到目标侧后方；当对方重新转身面对机器人时才再次计算。这样可以形成左右压迫和抓背，而不是原地站桩或无休止高速绕圈。

默认启用决斗、竞技场和战场，关闭野外 PvP。这样 2000 个随机机器人不会在日常活动中持续执行额外的 PvP 位置判断。

控制器每次决策会完成以下工作：

1. 根据当前天赋判断机器人属于猎人、施法者还是治疗者。
2. 目标正在攻击机器人并进入理想距离下限时，先尝试本职业的脱离技能。
3. 没有学会对应技能、技能冷却或无法施放时，自动退化为碰撞检测后的侧向/后向拉距。
4. 安全距离内正在读条时允许完成施法；敌人已经进入近战危险距离时允许中断读条保命。
5. 非决斗目标超过追击上限时放弃目标，避免机器人跨地图追逐玩家。

## 等级与技能降级

技能是否可用以角色当前真正学会的法术为准，不按满级模板假定：

- 猎人优先尝试冰冻陷阱、摔绊、逃脱和震荡射击；低等级缺少其中某项时继续尝试下一项。
- 法师尝试冰霜新星、闪现和冰锥术。
- 术士尝试死亡缠绕、疲劳诅咒和恐惧。
- 牧师尝试心灵尖啸。
- 萨满尝试雷霆风暴、冰霜震击和地缚图腾。
- 德鲁伊尝试纠缠根须和旋风。
- 神圣圣骑士在减速或定身时尝试自由之手，并可用制裁之锤脱离。

因此一级或低等级机器人仍能使用基础移动，不会因为缺少高级技能而停止决策。机器人升级和学习法术后，新选项会自动进入技能选择，无需修改配置或重新编译。

## 默认配置

```ini
AiPlayerbot.PvPTactical.Enable = 1
AiPlayerbot.PvPTactical.Duel = 1
AiPlayerbot.PvPTactical.Arena = 1
AiPlayerbot.PvPTactical.Battleground = 1
AiPlayerbot.PvPTactical.OpenWorld = 0

AiPlayerbot.PvPTactical.DecisionInterval = 250
AiPlayerbot.PvPTactical.Hunter.MinDistance = 24.0
AiPlayerbot.PvPTactical.Caster.MinDistance = 18.0
AiPlayerbot.PvPTactical.Healer.MinDistance = 22.0
AiPlayerbot.PvPTactical.RetreatStep = 7.0
AiPlayerbot.PvPTactical.TargetLeashDistance = 55.0

AiPlayerbot.PvPTactical.Melee.Enable = 1
AiPlayerbot.PvPTactical.Melee.DecisionInterval = 600
AiPlayerbot.PvPTactical.Melee.FlankDistance = 1.5
AiPlayerbot.PvPTactical.Melee.MinAngle = 100.0
AiPlayerbot.PvPTactical.Melee.MaxAngle = 145.0
```

这些值由 `runtime.defaults.json` 和安装脚本写入正式配置。修改距离或判断频率只需要编辑配置并重启 worldserver，不需要重新编译。

## botduel 验收

建议先在开阔区域使用装备和等级接近的机器人测试：

1. 猎人对战近战，确认贴近前开始减速并主动拉距。
2. 分别用低等级和满级猎人测试，确认没有学会的技能不会造成停顿。
3. 法师对战近战，确认近距离冰环或闪现后继续拉距。
4. 术士、牧师、萨满和德鲁伊分别确认控制技能冷却时仍会移动。
5. 观察机器人不会在理想距离边界持续前后抖动，也不会追逐超过 55 码的非决斗目标。
6. 用盗贼、战士或死亡骑士对战，确认位于目标正面时会向较近的一侧移动，进入侧后方后停止重复绕圈。

后续阶段再增加防御性绕柱、控制递减、打断评分和竞技场团队协同；绕柱不会混入首版，以免在复杂地形中引入新的卡点。
