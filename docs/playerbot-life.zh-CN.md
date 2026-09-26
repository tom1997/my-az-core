# Playerbot PvP Life 与 City Life

Enhanced 构建额外包含 `mod-playerbots-pvp-life` 和 `mod-playerbots-city-life`。前者把少量空闲随机机器人投放到决斗区和野外 PvP 热点，后者让部分空闲机器人出现在主城。Stable 构建不包含这两个实验模块。

它们负责“机器人在哪里活动”，现有 Playerbots 和 PvP Tactical 仍负责实际战斗、职业循环与走位。模块默认尊重 Playerbots 自己的活动状态，不会接管已组队、排队、处于战场/副本或正在执行其他活动的机器人；活动结束后机器人会回归原有调度。

## 本项目默认范围

- PvP Life 启用，但双方最多各投放 12 个机器人，同时只激活 1 个野外热点。
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
