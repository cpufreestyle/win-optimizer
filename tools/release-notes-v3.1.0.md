# PC-Optimizer v3.1.0

## 改动
- **架构去重**：临时文件清理目标清单改为配置驱动（`config/optimization.json` 的 `clean_targets`），核心库新增 `Get-CleanTargets`，CLI 与 WebUI 共用同一数据源，消除两边重复维护。
- **CI 门禁**：新增 GitHub Actions（`validate`），提交即跑 Pester 测试（硬门槛）+ PSScriptAnalyzer 错误级报告，防回归。
- **测试**：新增 `Get-CleanTargets` 的 Pester 用例，固化共享契约。
- **自动发布**：新增 `release.yml`，推送 `v*` tag 时自动构建 `PC-Optimizer.exe` 并发布 GitHub Release。
- **版本**：四处版本号统一至 3.1.0，重新编译 `PC-Optimizer.exe`。

## 下载
- `PC-Optimizer.exe`：双击运行（自动请求管理员权限）。

> 向后兼容，无破坏性变更。
