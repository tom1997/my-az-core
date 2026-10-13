# 补丁目录

这里仅存放无法通过独立模块实现的 Core 或第三方模块补丁。补丁按文件名排序应用：

```text
0001-description.patch
0002-description.patch
```

补丁必须能在 `upstreams.lock.json` 锁定的版本上通过 `git apply --check`。个人玩法功能应优先放到 `modules/custom/`。

`0038` 修复决斗受控停火后的重新接战，并把 PvP 缠绕限制为近身近战脱困用途；不改变 PvE 缠绕。
`0039` 隔离 PvP Life 决斗区的日常游荡，自动校验/调整可决斗场地，并优先选择等级接近的参与者。它仅适用于 Enhanced 的 PvP Life 模块。源码准备只会跳过明确不属于当前构建 profile 的独立模块补丁，其他缺失目标仍报错。
