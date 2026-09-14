# PC-Optimizer v3.3.0

> 合并 CLI 稳定性修复与性能/架构重构，统一版本来源与错误隔离。

## CLI 稳定性修复
- `Optimize.ps1` 的 `Invoke-ScriptModule` 增加 `try/catch`，单模块失败不再直接中断整条链路。
- 一键全面优化会汇总失败模块，并在控制台与 `optimize.log` 中输出失败清单。
- 版本号统一收口到 `config/optimization.json`，CLI 启动与构建流程优先读取同一来源。
- `README.md` 与 `Start.bat` 补充版本来源说明，减少多份版本号硬编码导致的显示偏差。

## 性能与架构重构
- 文件夹大小统计改为只枚举文件，显著降低大目录扫描开销。
- 统一 `Write-OptLog` 日志输出与 `pause` 兼容性，改善长期运行脚本可观测性。
- 启动项逻辑下沉到 `lib/Optimize.Core.ps1`，统一字段与备份 CSV 列名，修复 GUI/WebUI 备份无法恢复的问题。
- 视觉效果逻辑下沉到 `lib/Optimize.Core.ps1`，新增 profile/toggle/state 抽象，GUI/WebUI 补全备份与完整设置项。
- 电源计划逻辑下沉到 `lib/Optimize.Core.ps1`，新增计划目录、激活计划查询、备份与 CPU 节流参数设置。
- GUI 清理页面增加进度与取消能力，Build-EXE 使用 `#region GUI-PAGE-LOADER` 标记稳定剥离加载段。
- WebUI 增加长任务超时与 SSE 流式输出，提升大任务交互体验。
- 测试覆盖扩展到文件夹统计、日志、启动项、视觉效果、电源计划，验证新抽象与回退逻辑。

## 升级建议
- 更新 `config/optimization.json` 中的 `version` 到 `3.3.0`（已同步）。
- 若重新打包 EXE，请运行 `.\Build-EXE.ps1`。
- 若使用 Git 子模块/工作树同步，请确保 `lib/Optimize.Core.ps1` 的新函数被正确加载。
