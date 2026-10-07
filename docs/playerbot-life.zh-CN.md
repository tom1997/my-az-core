# Playerbot PvP Life 与 City Life

Enhanced 构建额外包含 `mod-playerbots-pvp-life` 和 `mod-playerbots-city-life`。前者把少量空闲随机机器人投放到决斗区和野外 PvP 热点，后者让部分空闲机器人出现在主城。Stable 构建不包含这两个实验模块。

它们负责“机器人在哪里活动”，现有 Playerbots 和 PvP Tactical 仍负责实际战斗、职业循环与走位。模块默认尊重 Playerbots 自己的活动状态，不会接管已组队、排队、处于战场/副本或正在执行其他活动的机器人；活动结束后机器人会回归原有调度。

## 本项目默认范围

- PvP Life 启用，每个活动双方最多各投放 12 个机器人，同时只激活 1 个野外热点；这不是所有活动合计的人数上限。
- 决斗区每次最多组织 6 对机器人，默认不主动挑战真人。
- 默认只开放暴风城决斗区、奥格瑞玛决斗区和古拉巴什竞技场。
- 其他漫游热点、冬拥湖、阵营进攻和机器人聊天默认关闭。
- City Life 启用，总人口上限 100，每个更新周期最多改变 2 个机器人。
- City Life 的冬拥湖据点默认关闭。

这组值用于先观察稳定性、地图负载和与 Dungeon Clear / 战场队列的交互。确认运行正常后，再逐项扩大范围，避免一次放开全部热点导致大量传送和活动争用。

## 管理员命令

在 GM 角色或 worldserver 控制台中使用：

```text
.pvplife
.citylife
```

命令的具体子项以对应模块返回的帮助信息为准。常用开关也可以直接修改安装目录下的：

```text
configs/modules/mod_playerbots_pvp_life.conf
configs/modules/mod_playerbots_city_life.conf
```

修改后重启 worldserver 生效。重新安装构建包时，安装脚本会根据 `runtime.settings.json` 再次写入本项目的受控默认值；希望长期保留的调整应写入该文件，而不是只改安装目录中的配置。

## 可调设置

`runtime.settings.json` 支持以下项目：

```json
{
  "pvpLifeEnabled": true,
  "pvpLifeRespectPlayerbotActivity": true,
  "pvpLifeMaxPerSide": 12,
  "pvpLifeMaxActiveHotspots": 1,
  "pvpLifeDuelPairLimit": 6,
  "pvpLifeChallengeRealPlayers": false,
  "pvpLifeGurubashiEnabled": true,
  "pvpLifeAdditionalHotspotsEnabled": false,
  "pvpLifeWintergraspEnabled": false,
  "pvpLifeFactionCampaignsEnabled": false,
  "pvpLifeBotChatEnabled": false,
  "cityLifeEnabled": true,
  "cityLifeRespectPlayerbotActivity": true,
  "cityLifeMaxTotalPopulation": 100,
  "cityLifeMaxChangesPerTick": 2,
  "cityLifeWintergraspEnabled": false
}
```

关闭模块时只需把对应的 `Enabled` 改为 `false`。如果出现机器人被反复调度、战场人数异常或地图负载突增，优先关闭两个模块并重启 worldserver，再保留日志排查。

## 数据库安装

两个上游模块把种子数据放在 `data/sql/manual`。Enhanced 打包过程会把副本放入标准的 `db-world` 更新目录，因此首次启动新构建时由 AzerothCore 数据库更新器自动导入，不需要手工执行 SQL。模块上游版本固定在 `upstreams.lock.json`，不会在构建时静默升级。

## 决斗区修复（2026-10-07）

旧日志记录了 578 次 `Duel request failed`，同时存在决斗区参与者被 `New RPG` 的脱困传送带走的记录。人数看起来少，不只是人数配置偏小。

`0039` 让已预留的决斗参与者暂停日常游荡、旅行、坐骑和额外自主决斗策略，活动结束仍由上游 `ResetStrategies()` 恢复。按等级从高到低挑选同阵营候选者，减少等级跨度过大而无法配对；不扩大人数、不抢占战场/副本/组队机器人。

场地第一次有人抵达后，检查中心及摆放边界是否允许决斗。必要时在附近 160 码内查找地面有效的合法位置，并同步等待点与尚未执行的移动队列；无法找到时每分钟重试，不再连续发送必然失败的请求。合法性检查按活动缓存，不逐机器人每 tick 搜索。实际决斗期间不强制锚定机器人。

验证新版本时重点看 `Validated duel area`、失败日志里的双方 area ID、实际同时开打的对数，以及是否仍出现参与者被日常逻辑传走。新地形位置仍需游戏内确认，尤其是坡面和建筑边缘。
