# PC-Optimizer v3.3.0

> 本次把 PR #5（CLI 稳定性）与 PR #6（维护性优化合集 + 一键体检）合并进 main，
> 并收口交接文档中遗留的 CompactOS 默认行为问题（见 `docs/HANDOFF.md` §7.1）。

## 行为变更（请注意）

- **CompactOS 改为「显式开关、默认关闭」**
  - 此前 CLI 的磁盘优化**无条件**执行 `Compact.exe /CompactOS:always`（压缩系统文件耗时长、
    回滚还要再跑一次 `Compact.exe /CompactOS:never`），而 GUI / WebUI 默认关闭 —— 三端不一致。
  - 现在三端统一：默认值来自 `config/optimization.json` 的 `disk.compact_os_default`（**false**）。
  - 需要压缩时：
    - CLI：`.\scripts\07-DiskOptimize.ps1 -CompactOS`
    - GUI：勾选「压缩系统文件 (CompactOS)」后点优化
    - WebUI：勾选 CompactOS 后提交
  - 一键全面优化（CLI `[9]`）**不再**压缩系统文件。

## CLI 稳定性（PR #5）

- `Invoke-ScriptModule` 增加 `try/catch`，单个模块失败不再中断整条链路。
- 一键全面优化会汇总失败模块，并在控制台与 `optimize.log` 输出失败清单。
- 版本号统一收口到 `config/optimization.json`（CLI / GUI / WebUI / 构建 / `Start.bat` 同源读取）。
- 日志轮转：超过 5MB 自动归档为 `.old`。

## 性能与架构（PR #6）

- **五域逻辑下沉 `lib/Optimize.Core.ps1`**，三端统一为同一实现，修复的真实缺陷：
  - 启动项：GUI/WebUI 备份 CSV 列名与还原逻辑不一致 → 备份**无法被恢复**
  - 视觉效果：GUI 备份是死变量（从未真备份）、「最佳性能」设置不彻底
  - 电源计划：GUI/WebUI 无备份、无法解锁/回退卓越性能
  - 网络：GUI/WebUI 改 DNS **完全没有备份**；WebUI 把适配器数组直接传给 `-Name`
  - 磁盘：WebUI 用 Storage 模块（**Win7 不存在**）；GUI/WebUI 对 SSD 也做碎片整理
- `Get-FolderSize` 只枚举文件，显著降低大目录扫描开销；统一 `Write-OptLog` 与 `pause` 兼容性。
- GUI 清理页新增进度显示与取消；`Build-EXE` 改用 `#region GUI-PAGE-LOADER` 标记稳定剥离加载段。
- WebUI 长任务超时与 SSE 流式输出。

## 新增：一键体检（只读）

- CLI `[15]` / GUI「系统体检」/ WebUI 体检页，共用 lib 体检引擎。
- 只读取系统状态，**不修改任何设置**；报告存 `backups/health/`，再次运行可与上一份对比。

## 网络：无活动网卡不再返回空结果

- `Invoke-NetworkOptimization` 在没有活动网卡时，此前返回 `details = @()`，而三端只渲染 `details`、
  从不看 `error` 字段 —— 用户（以及 GitHub Actions runner）看到的是一片空白。
- 现在该分支返回结构一致的 `details`（「未检测到活动网络适配器，已跳过网络优化」），
  且 CLI / WebUI 会把 `error` 一并显示/回传。

## 文档

- 新增 `docs/HANDOFF.md`（当前状态 / 待合并 PR / 踩坑 / 三端文件地图）。
- `docs/DEVELOPMENT.md` 版本章节改为「单一来源」描述（旧的「4 处必须一致 + 构建校验」已不适用）。

## 验证

- Pester：`tests/Optimize.Core.Tests.ps1` **88 / 88 通过**（81 基线 + 6 条 CompactOS 契约用例 + 1 条无网卡分支用例），本地与 GitHub Actions 双绿。
- 新增回归用例：CLI 磁盘脚本中 `Set-CompactOSState` 必须受 `if` 保护（AST 断言），
  防止「无条件压缩系统文件」再次回归；并断言三端默认值同源。

## 升级建议

- 版本号已置为 `3.3.0`（`config/optimization.json`）。
- 重新打包：`.\Build-EXE.ps1`；发布：`git tag -a v3.3.0 -m "v3.3.0"` 后推送 tag。
