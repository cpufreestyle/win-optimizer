# PC-Optimizer 7th Gen v3.0.0

## 重大结构重构

### 统一三套实现核心逻辑
- 新增 `lib/Optimize.Core.ps1` 共享库（服务列表、遥测任务、备份/恢复等），CLI、WebUI、GUI 全部复用同一份代码，消除重复与功能漂移
- 配置驱动：`config/optimization.json` 的服务列表、DNS 选项等真正生效，不再依赖硬编码

### GUI 拆分
- 原 2400+ 行的 `OptimizeGUI.ps1` 拆分为 `gui/pages/*.ps1`（11 个页面函数）+ `gui/UpdateCheck.ps1`
- 主窗体仅保留头部、UI 辅助、页面实例化与加载器，可维护性大幅提升
- `Build-EXE.ps1` 改为拼接 `lib + gui/pages + 主体` 后编译单体 EXE

### 中文乱码修复
- 编译前将源文件转 UTF-16 LE 并配合 `-UNICODEEncoding`，彻底解决 ps2exe 按 ANSI 读取导致的中文损坏

### 其他
- 清理开发残留（临时脚本归入 `_scratch/`），消除零 BOM / 双 BOM 隐患
- 统一全部版本号为 `3.0.0`

## 下载
- `PC-Optimizer.exe`：双击即用的图形界面（需以管理员身份运行以生效大部分优化项）
