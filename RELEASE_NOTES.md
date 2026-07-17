# v2.1.2 一键优化与 Release 乱码修复

## 更新内容
- **GUI 一键全面优化真正生效**：抽出 7 个 `Invoke-*` 公共函数，一键按钮依次执行 垃圾清理 → 服务 → 启动项 → 视觉效果 → 电源计划 → 磁盘优化 → 网络优化，带分步进度与汇总报告。
- **统一横幅与配置数据源**：新增 `scripts/Common.ps1` 公共模块（Show-ModuleBanner / Show-ModuleFooter / Get-OptimizationConfig），9 个脚本复用；03 服务列表与 08 DNS 列表改读 `config/optimization.json`（单一数据源）。
- **修复 BOM 与脚本健壮性**：解决中文 PowerShell 5.1 下运行时乱码、注释块提前闭合等问题。
- **根除全部 Release 面向文件乱码**：移除 13 个文件（config/optimization.json、Optimize.ps1、OptimizeGUI.ps1、Build-EXE.ps1、Launcher.cs、scripts/01-09 全部脚本、tools 下的 README）的 UTF-8 BOM，GitHub Release 页面不再显示 `ï»¿` 乱码；CI 增加全文件 BOM 守卫。
- **仓库远程改用 SSH**，README 注明 SSH 公钥与 clone 示例。

## 使用说明
1. 以管理员身份运行 `Start.bat`（或 `StartGUI.bat` 打开图形界面）。
2. 图形界面可逐个点击左侧功能页面执行优化，或使用「一键全面优化」一次性完成。
3. 优化前建议先备份（GUI 各页面会自动生成备份到 `backups/` 目录）。
