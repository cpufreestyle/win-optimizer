# PC-Optimizer v3.3.0

## 说明
- 本 PR 合并 `fix/cli-error-isolation-version` 与 `perf/folder-size-and-logging` 到 `main`。
- 版本已统一升到 `3.3.0`，变更来源单一为 `config/optimization.json`。

## 主要变更
- CLI 错误隔离与汇总：`Optimize.ps1`
- 版本统一读取：`lib/Optimize.Core.ps1`、`Build-EXE.ps1`、`Start.bat`
- 性能与架构重构：`lib/Optimize.Core.ps1`、`scripts/04-06`、`gui/pages/*`、`webui/ps/*`
- GUI 清理进度/取消：`gui/pages/Clean.ps1`
- WebUI 长任务超时与 SSE：`webui/app.py`
- 构建稳定性：`Build-EXE.ps1`
- 测试扩展：`tests/Optimize.Core.Tests.ps1`
- 发布说明：`tools/release-notes-v3.3.0.md`

## 验证
- 已运行 `tests/Optimize.Core.Tests.ps1`，44/44 通过
- 已检查 `git diff --check`
- 已验证 `Start.bat` 版本解析输出 `3.3.0`

## 后续
- 合入后请重新编译 `PC-Optimizer.exe`
- 本地更新 `main` 可执行：`git pull origin main`
