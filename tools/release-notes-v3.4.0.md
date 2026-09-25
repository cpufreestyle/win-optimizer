# PC-Optimizer v3.4.0

> 本次发布集成 PR #8（P1-1 定时体检 + 趋势报告），并包含 v3.3.0 发布后的 P0-3/P0-4 工程收口与 CI 修复。

## 新增：定时体检 + 趋势报告

- **每日自动体检**：`scripts/15-HealthCheck.ps1 -InstallSchedule [-Time 09:00]` 注册 schtasks 计划任务；
  非管理员自动降级为「登录时触发」并给出警告；`-UninstallSchedule` 可随时卸载。
  注册失败（虚拟机/域控环境）仅提示不报错，不影响主流程。
- **趋势可见**：`Get-HealthTrend [-Days 30]` 读取 `backups/health/` 历史报告，
  输出分数 / 内存可用% / 可清理 MB / 启动项数序列；
  - WebUI：体检页新增「体检趋势」卡片（内联 SVG 折线，**零外链依赖，离线可用**）+ 最近 10 次表格
  - CLI：`-Trend` 字符 sparkline；每次体检后附带一行趋势
  - GUI：体检页关键指标区追加迷你趋势行
  - MCP：`health_trend` 工具（SSE / stdio 均可用）

## 修复

- **`-WhatIf` 预演零副作用**：`Invoke-Profile -WhatIf` 不再落盘备份与 `startup_items` 目录，
  兑现「预览不动系统」契约。
- **GitHub Actions 四个环境相关失败**：CI runner 无活动网卡 / `$env:TEMP` 为 8.3 短路径，
  现已通过测试隔离（伪网卡 / 路径归一化）修复。

## 验证

- Pester：`tests/Optimize.Core.Tests.ps1` **156 / 156 通过**（本地 + GitHub Actions）。
- 三端冒烟：CLI `-Trend` / `-InstallSchedule -Time bogus`、WebUI `-Action trend`、GUI 无头构建 + 点击体检均通过。

## 升级建议

- 版本号已置为 `3.4.0`（`config/optimization.json`，单一来源）。
- 重新打包：`.\Build-EXE.ps1`；发布：`git tag -a v3.4.0 -m "v3.4.0"` 后推送 tag。
