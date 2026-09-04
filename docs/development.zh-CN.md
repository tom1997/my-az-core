# 二次开发指南

## 默认开发方式

在 `D:\code\my-az-core` 使用 VS Code 编辑，通过 GitHub Actions 的 Windows runner 编译。这样不需要在当前 C 盘只剩少量空间时安装 Visual Studio。

运行 `scripts/new-module.ps1 -Name MyFeature` 会从 AzerothCore 官方 skeleton-module 创建模块，再补齐示例和三个数据库迁移目录。`examples/` 中的代码不会参与编译，可按需复制进 `src/`。

## 本地编译（以后可选）

先保证 C 盘至少有 20 GB 可用空间，再安装 Visual Studio 2022 的“使用 C++ 的桌面开发”。Boost、MySQL SDK、源码和构建目录仍应放在 D 盘。CI 使用的依赖版本与构建参数记录在工作流中，可据此复现。

## 调试

开发构建采用 `RelWithDebInfo`。下载对应的 `debug-symbols`，确保它与 `source-manifest.json` 的提交完全一致，再用 Visual Studio 附加到 `worldserver.exe`。

## 更新上游

运行 `scripts/check-upstreams.ps1` 只查看是否有更新，不会修改锁定文件。确认后使用 `scripts/update-upstream-lock.ps1` 在专用分支更新锁定值，再交由 CI 完整验证。
