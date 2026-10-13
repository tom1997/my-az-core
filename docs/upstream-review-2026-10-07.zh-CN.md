# 上游核查：2026-10-07

通过各仓库 Git 分支及 GitHub compare API，对比本项目锁定版本。此次只核查，不修改版本锁、不升级运行中的数据库。

| 项目 | 当前锁定 | 上游最新 | 增量 |
| --- | --- | --- | --- |
| Playerbot Core / Playerbot | `7f12e89e` | `f19a1879` | 62 个提交 |
| mod-playerbots / master | `7bae1b5c` | `037c0141` | 34 个提交 |
| mod-dungeon-clear / master | `805b909c` | `60f3d98b` | 26 个提交 |

Core 与 Playerbots 包含 headless session、脚本接口清理及异步模块数据库配套改动，应一起迁移并重新验证全部本地补丁与 Life/DC 模块，不适合只替换其中一个版本。Playerbots 还修复死亡后被传出战场、施法时间倍率、无限采集，并增加 BWL/Joust 等策略。

- [Core 差异](https://github.com/mod-playerbots/azerothcore-wotlk/compare/7f12e89ee5f467a50e62eba1d525eac7dc953d03...f19a18799a35f7c24bdcdc9ea399c601f166259b)
- [Playerbots 差异](https://github.com/mod-playerbots/mod-playerbots/compare/7bae1b5c58c76a0aa20381155edc08096d1485b2...037c01418b5d01506917a3db9b44fd56ac5f965c)

DC 增加卡拉赞路线、门/事件/国际象棋处理，修复楼层导航和来回移动，并增加战场即时补队、黑石塔/黑石深渊分区。建议跟随上述配套升级后测试；新补队功能须先检查与现有战场队列设置是否重叠，不能直接全开。

- [DC 差异](https://github.com/jrad7/mod-dungeon-clear/compare/805b909c7286348e75d0561f8cc259750e6ae62b...60f3d98b83143714041df4120abd45f0e3c3ebd7)

其余锁定模块（AutoBalance、RDF Expansion、AOE Loot、Transmog、Random Enchants、AHBot、Mythic Plus、PvP Life、City Life）对应分支未发现新的 HEAD。此结论只覆盖项目锁定的仓库/分支，不代表其他 fork 没有更新。

建议先体验本轮决斗修复，再单独做 Core + Playerbots + DC 的配套升级，保留数据库备份；二进制回退本身不保证已执行的数据库迁移也可以回退。
