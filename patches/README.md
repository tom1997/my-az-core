# 补丁目录

这里仅存放无法通过独立模块实现的 Core 或第三方模块补丁。补丁按文件名排序应用：

```text
0001-description.patch
0002-description.patch
```

补丁必须能在 `upstreams.lock.json` 锁定的版本上通过 `git apply --check`。个人玩法功能应优先放到 `modules/custom/`。
