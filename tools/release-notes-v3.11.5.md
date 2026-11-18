## PC-Optimizer v3.11.5

- StartGUI.vbs / StartGUI.bat 优先 PowerShell 7，缺失时回退 5.1；桌面启动不再显示黑色控制台窗口。
- 修复「按方案执行优化」的 MessageBoxButtons 枚举错误。
- 修复管理员提权时 Shell.Application 被覆盖导致的 ShellExecute 错误。
- 合入网络、遥测任务和 DPI 初始化的 PS7 兼容与启动性能优化。
- 回归：Pester 305/305、pytest 3/3、PSScriptAnalyzer 0 Error、布局审计 FINDINGS=0。