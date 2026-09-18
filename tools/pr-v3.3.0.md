## 说明

把交接文档（`docs/HANDOFF.md`）里挂着的两个 PR 合并进 `main`，并顺手收掉 §7.1 的遗留决策。

- 合并 **PR #5**（CLI 错误隔离 + 版本收口）→ **PR #6**（维护性优化合集 + 一键体检），顺序与 HANDOFF §8.1 一致。
- 远端原 `sync/v3.3.0-main` 是 09-15 的**陈旧快照**（只合到 `f8a8f2f`，缺 network / disk / health / 交接文档四个提交），本分支已重建为完整版本。
- 版本：`3.2.1` → `3.3.0`（含行为变更，走 minor）。当前最新 tag 为 `v3.2.0`，`3.2.1` 从未发布，故直接跳到 3.3.0。

## 主要变更

- **CompactOS 统一为「显式开关、默认关闭」**（HANDOFF §7.1）
  - 此前 CLI 无条件 `Compact.exe /CompactOS:always`，GUI/WebUI 默认关闭，三端不一致。
  - 新增 `Get-CompactOSDefault()`，默认值单一来源 = `config/optimization.json` 的 `disk.compact_os_default`（false）。
  - CLI 新增 `-CompactOS` 开关；一键全面优化不再压缩系统文件。
- CLI 错误隔离与失败汇总；版本号单一来源（`Optimize.ps1`）。
- 五域（启动项 / 视觉效果 / 电源 / 网络 / 磁盘）逻辑下沉 `lib/Optimize.Core.ps1`，三端统一并修复备份丢失、对 SSD 碎片整理等真实缺陷。
- 一键体检（只读）接入 CLI / GUI / WebUI。
- `Get-FolderSize` 只枚举文件；GUI 清理进度与取消；WebUI 长任务超时与 SSE。
- 文档：`docs/HANDOFF.md` 新增；`docs/DEVELOPMENT.md` 版本章节改为单一来源描述。

## 验证

- `Invoke-Pester tests/Optimize.Core.Tests.ps1` → **87 / 87 通过**
- 新增 6 条契约用例：CompactOS 默认 false、默认不压缩、显式开启才压缩、CLI 调用必须受 `if` 保护（AST）、三端默认值同源。
- 改动 `*.ps1` 均为 UTF-8 BOM；PowerShell 解析 0 错误。

## 合并后

1. 本 PR 合并后，PR #5 / #6 会被 GitHub 自动关闭（其提交已全部可达）。
2. 打 tag 触发 Release：`git tag -a v3.3.0 -m "v3.3.0" && git push origin v3.3.0`
3. 仍需在真机验收 GUI 体检页渲染（HANDOFF §7.2，本环境无法自动验证 WinForms）。
