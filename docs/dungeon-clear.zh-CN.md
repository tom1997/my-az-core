# Dungeon Clear 使用说明

`mod-dungeon-clear` 让队伍中的 Playerbot 坦克负责副本路线、拉怪、Boss 顺序、开门、恢复、拾取和战后复活。模块已固定在 `upstreams.lock.json`，stable 与 enhanced 都会编译。

## 使用前提

- `dbc`、`maps`、`vmaps`、`mmaps` 已完整提取。
- 真人与至少一个坦克机器人在同一队伍。
- 真人已经进入五人副本。
- 真人不要亲自担任坦克；启用后路线由机器人坦克控制。

## 常用命令

```text
.dc on       开始自主清理
.dc pause    暂停或继续
.dc skip     跳过当前卡住的目标
.dc bosses   显示 Boss 列表
.dc status   显示当前状态
.dc off      结束并恢复普通跟随
```

也可以在队伍聊天中使用 `dc on`、`dc pause`、`dc skip` 和 `dc off`。

## 本项目默认值

- 模块启用，但必须由真人主动开始一次清理。
- 机器人地下城队列自动填充保持关闭。
- 全自动测试计划保持关闭。
- 最低拾取品质为绿色（Uncommon）。
- 开启更合理的装备 Roll 与智能休息。
- Dynamic 模式最多直接冲入 4 只预计会进入战斗的怪物；更大的怪群采用谨慎拉回。
- 战斗后存在可复活职业时等待机器人复活队友。

## 与大秘境的关系

当前版本只用于普通副本自主清理。以后接入 Legion M+ 时，Dungeon Clear 负责路线和拉怪，M+ 模块负责钥匙、计时、敌方部队、强度、词缀与奖励。完成敌方部队适配前，不把普通 `.dc on` 的最短 Boss 路线视为一次有效的大秘境路线。

