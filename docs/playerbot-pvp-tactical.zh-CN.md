# Playerbot PvP Tactical：空间控制第一阶段

本发行版在 `0004–0008` 的空间控制基础上，新增 `0009–0013` 五层 PvP 框架：共享战术状态、能力检查、控制递减、移动所有权、全部职业控制入口，以及野外/多人 PvP 协同。它不是需要逐个机器人添加的游戏内策略；是否启用、在哪些场景启用以及距离参数全部由 `playerbots.conf` 决定。

## 行为范围

首版覆盖当前天赋定位为远程或治疗的机器人：猎人、法师、术士、牧师、元素/恢复萨满、平衡/恢复德鲁伊和神圣圣骑士。增强只在当前目标确实是玩家时工作，不改变 PvE 副本战斗。

近战机器人同时启用轻量抓背机制。进入近战范围后，如果机器人仍在目标的正面半区，会选择碰撞检测通过且距离较短的一侧移动到目标侧后方；当对方重新转身面对机器人时才再次计算。这样可以形成左右压迫和抓背，而不是原地站桩或无休止高速绕圈。

默认启用决斗、竞技场、战场和野外 PvP。野外逻辑只在当前目标为敌对玩家且进入战斗后接管职业控制；近距离空间检测会选择最近敌对玩家作为走位威胁。

正式修复后，空间控制器只负责选择移动目的地，不再直接选择或施放职业技能：

1. 根据当前天赋判断机器人属于猎人、施法者还是治疗者。
2. 职业原有策略优先选择当前等级已经学会、当前可用的控制、减速、脱离和输出技能。
3. 本轮没有更高优先级技能可执行时，空间控制器才生成一次碰撞检测后的侧向/后向拉距或近战侧后方移动。
4. 移动样条会跨 AI tick 持续运行，后续 tick 仍能选择瞬发技能，因此移动和技能决策不再互相锁死。
5. 战术走位不会主动中断正在读条或引导的技能；需要站定的法术仍遵守 3.3.5a 的原版施法规则。
6. 已在执行的战斗点移动不会被每次判断重新下发，避免来回改目的地造成木讷和抖动。
7. 非决斗目标超过追击上限时放弃目标，避免机器人跨地图追逐玩家。
8. 远程进入危险半径后保持“正在拉距”状态，直到达到首选距离才结束，不会在危险边界每次只挪两三码。
9. 决斗中优先沿目标切线横向跑，目的地限制在决斗旗 38 码内；如果没有安全方向则先返回圈内。
10. 远程对远程不再执行完整拉距，仅在 8 码内紧急脱离到约 12 码；优势明显时法师可主动压进猎人的射击死区。
11. 开战倒计时中，盗贼准备潜行，战士预留冲锋距离，死亡骑士预留死亡之握距离，猎人和其他远程拉开起手距离。
12. 决斗对手处于冰箱等完全免疫状态时，优先攻击其镜像、宠物或召唤物；免疫结束后在下一次维护判断切回对手。

贴身时不会无条件逃跑。法师仍优先冰环，并只在 8 码内允许闪现；术士优先暗影之怒/暗影烈焰，牧师优先心灵尖啸，元素萨满优先雷暴，平衡德优先台风；猎人会优先尝试冰冻陷阱或原有伤害陷阱，并允许原职业策略在一对一被追击时使用逃脱。猎人会直接给当前 PvP 目标上震荡射击，法师会用减速/冰箭并在低血量时尝试变羊，术士会在贴近或血量受压时尝试恐惧。需要读条的控制会先停止战术移动，再在下一次决策施放。

## 等级与技能

技能仍完全由 Playerbots 各职业原有策略选择，所以天然依据当前等级、天赋、已学法术、冷却和施法条件降级。空间控制器不再复制一份固定职业技能表，避免它与职业轮转抢占同一个 AI tick。一级或低等级机器人仍可执行基础移动；升级学会新技能后，职业策略会自动使用，无需修改配置或重新编译。

## 默认配置

```ini
AiPlayerbot.PvPTactical.Enable = 1
AiPlayerbot.PvPTactical.Duel = 1
AiPlayerbot.PvPTactical.Arena = 1
AiPlayerbot.PvPTactical.Battleground = 1
AiPlayerbot.PvPTactical.OpenWorld = 1

AiPlayerbot.PvPTactical.DecisionInterval = 200
AiPlayerbot.PvPTactical.Hunter.MinDistance = 24.0
AiPlayerbot.PvPTactical.Caster.MinDistance = 18.0
AiPlayerbot.PvPTactical.Healer.MinDistance = 22.0
AiPlayerbot.PvPTactical.Hunter.PreferredDistance = 32.0
AiPlayerbot.PvPTactical.Caster.PreferredDistance = 26.0
AiPlayerbot.PvPTactical.Healer.PreferredDistance = 30.0
AiPlayerbot.PvPTactical.RangedOpponent.EmergencyDistance = 8.0
AiPlayerbot.PvPTactical.RangedOpponent.PreferredDistance = 12.0
AiPlayerbot.PvPTactical.Duel.SafeRadius = 38.0
AiPlayerbot.PvPTactical.RetreatStep = 14.0
AiPlayerbot.PvPTactical.TargetLeashDistance = 55.0

AiPlayerbot.PvPTactical.Melee.Enable = 1
AiPlayerbot.PvPTactical.Melee.DecisionInterval = 200
AiPlayerbot.PvPTactical.Melee.FlankDistance = 1.5
AiPlayerbot.PvPTactical.Melee.MinAngle = 100.0
AiPlayerbot.PvPTactical.Melee.MaxAngle = 145.0
```

这些值由 `runtime.defaults.json` 和安装脚本写入正式配置。`MinDistance` 是开始拉距的危险线，`PreferredDistance` 是本次拉距结束线；两条线形成迟滞区，避免反复启停。`RetreatStep` 是单段路径的最大长度，不是最终停止距离。200 ms 只用于刷新距离与战术状态，已有路径不会被重复下发；服务端最低钳制为 150 ms。修改距离或判断频率只需要编辑配置并重启 worldserver，不需要重新编译。

Dungeon Clear 在决斗、竞技场和战场中会让自己的动作失效，并立即释放它设置的 `passive`、`stay` 等站位钉住状态，避免副本自动清理逻辑混入 PvP。

## botduel 验收

建议先在开阔区域使用装备和等级接近的机器人测试：

1. 猎人对战近战，确认贴近前开始减速并主动拉距。
2. 分别用低等级和满级猎人测试，确认没有学会的技能不会造成停顿。
3. 法师对战近战，确认职业策略能使用冰环或闪现，随后继续拉距。
4. 术士、牧师、萨满和德鲁伊分别确认控制技能冷却时仍会移动。
5. 观察机器人不会在理想距离边界持续前后抖动，也不会追逐超过 55 码的非决斗目标。
6. 用盗贼、战士或死亡骑士对战，确认位于目标正面时会向较近的一侧移动，移动途中仍能使用瞬发技能，进入侧后方后停止重复绕圈。
7. 在允许决斗的区域使用 `.botduel`，确认聊天框收到候选数量或成功发起数量；纯文本 `botduel` 也可作为队伍聊天别名。

当前版本已经使用服务端控制递减状态避免对免疫目标重复控制，并在多人战斗中综合 15 码内敌人的方向选择退路。防御性绕柱和更精细的竞技场打断评分仍留作后续阶段，避免在复杂地形中引入新的卡点。
