# 项目交接文档（HANDOFF）

> 生成日期：2026-09-16
> 最近复核：2026-09-26（实测：远端 `main` 与本地一致；PR #24（P4-1）已合并并随 v3.10.0 发布，见 §2 与 §3.14）
> 最近复核：2026-10-03（浅色苹果风 UI 真机收口：GUI 12 页窗口级像素渲染逐页核对、WebUI 桌面视口真实浏览器截图、
> 5 处既有布局撞车修复后七档窗口尺寸 0 重叠、测试套件 226/226 通过；见 §3.15 / §3.16 / §3.17 / §5.7 / §6）
> 更早：2026-09-28（GUI 体检页/首页无头 harness 断言 22/22 通过、WebUI 后端 tips 复核通过、测试套件 226/226 通过）
> 适用对象：接手 PC-Optimizer-7thGen 维护的开发者
> 配套文档：`README.md`（用户向）、`docs/DEVELOPMENT.md`（开发向，本文不重复其中的架构 / 配置 / 版本 / SSH 说明）

---

## 1. 一句话定位

为 **7 代及更老 CPU** 的 Windows 电脑（Win7 / 8 / 10 / 11，PowerShell 2.0+）提供一键系统优化。
三套前端（**CLI / GUI / WebUI**）**共享同一份核心逻辑库** `lib/Optimize.Core.ps1`，避免重复实现与功能漂移。

---

## 2. 当前分支与待合并 PR（最关键）

> ✅ **2026-09-25**：PR #7 已合并入 `main`（merge commit `bfc7b54`），残留分支已清理，已打 tag `v3.3.0` 并发布 Release。
> ✅ **2026-09-25**：P1-2（前后对比报告导出）已合并并随 v3.5.0 发布（见 §3.7）。
> ✅ **2026-09-26**：P1-3（优化前自动创建系统还原点）已合并（PR #12），并随 v3.6.0 发布（见 §3.8）。
> ✅ **2026-09-26**：PR #14 修复两类静默故障（弯引号误作字符串定界符 / `[PSCustomObject]` 漏写 `@`），并补源码静态检查（见 §3.10）。
> ✅ **2026-09-26**：P2 智能降级建议已合并（PR #15，见 §3.9）。
> ✅ **v3.8.0 已发布**：P2 三项全部落地——智能降级建议（§3.9，PR #15）、统一优化预览（§3.11，PR #16）、
> 开机性能基线 bench（§3.12，PR #18）。Roadmap 的 P0 / P1 / P2 全部收口。
> 当前 `main` = v3.8.0 发布态；本地 `main` 与远端一致（`git ls-remote` 核对）。

> ✅ **2026-09-26**：P3-1 智能建议一键应用闭环已合并（PR #21）并随 v3.9.0 发布（见 §3.13）。
> ✅ **2026-09-26**：P4-1 启动项建议签名厂商否决已落地（见 §3.14），当前 `main` 工作区为 v3.10.0 发布态。

> ✅ **2026-10-03 现状**：`main` @ `246ec51` = v3.10.0 发布态（PR #25 已合并）。Roadmap（FEATURE-IDEAS）
> 的 P0 / P1 / P2 / P3 / P4 已全部收口；`origin/main` 与本地一致。**当前无待合并 PR**。

- **UI 苹果风改动已入库到分支 `codex/ui-apple-style`**（浅色主题 + 5 处布局撞车修复 + 概览容错，见 §3.15 / §3.16 / §3.17 / §3.19）：
  `Build-EXE.ps1`、`OptimizeGUI.ps1`、`PC-Optimizer.exe`、`README.md`、`.gitignore`、`docs/HANDOFF.md`、
  `gui/pages/{About,Backup,Clean,Dashboard,Health,Services,Startup}.ps1`、`webui/ps/01_system_info.ps1`、`webui/templates/index.html`。
  真机验证已完成并推送，等待 PR 合并（`main` 受保护，需在 GitHub 手动点 Merge）。
- 入库时**不要用裸 `git add -A`**：本地还留着 `.codex-*` 临时脚本与截图。`.gitignore` 已补 `.codex-*`
  规则（§3.17），正常情况下会被忽略；但显式列举改动文件最稳妥。
- `main` **受保护**，所有改动必须经 PR 合入，且需在 GitHub 手动点「Merge」（当前账号无自动 merge 权限）。
- **判断远端真实 HEAD 一律以 `git ls-remote` 为准**（tracking ref 不一定反映真实远端状态）。

## 3. 近期完成的大块工作

### 3.1 B1：五个域的逻辑下沉到 lib

此前三端各写一份优化逻辑，已实际漂移到「改坏无法恢复 / 不区分介质 / 编号三套」等真实缺陷。现已把以下五个域下沉到 `lib/Optimize.Core.ps1`，三端改为 dot-source 调用：

| 域 | lib 关键函数 | 修复的真实缺陷 |
|----|--------------|----------------|
| 启动项 | `Get-StartupItems` / `Backup-StartupItems` / `Set-StartupItemState` | GUI/WebUI 备份 CSV 列名与还原逻辑不一致 → 备份**无法被恢复** |
| 视觉效果 | `Get-VisualEffectProfiles/Toggles/State` / `Backup-VisualEffects` / `Set-VisualEffectProfile` | GUI 备份是死变量（从未真备份）、「最佳性能」设置不彻底 |
| 电源计划 | `Get-ActivePowerPlan` / `Get-PowerPlanCatalog` / `Set-PowerPlan` / `Backup-PowerPlan` | GUI/WebUI 无备份、无法解锁/回退卓越性能 |
| 网络 | `Get-ActiveNetAdapters` / `Get-DnsOptions` / `Backup-NetworkSettings` / `Invoke-NetworkOptimization` | GUI/WebUI 改 DNS **完全没有备份**；DNS 选项三端三套；WebUI 把适配器数组直接传给 `-Name` |
| 磁盘 | `Get-PhysicalDiskInfo` / `Get-FixedVolumeList` / `Get-DriveMediaMap` / `Invoke-DiskOptimization` | WebUI 用 Storage 模块（**Win7 不存在**）；GUI/WebUI 对 SSD 也做碎片整理；SSD 判定失效 |

对应提交：`815b1bd`(启动项) `e111730`(视觉) `f8a8f2f`(电源) `23df87f`(网络) `36126d0`(磁盘)。

### 3.2 一键体检（只读）+ 优化前后对比

新增 `lib` 体检引擎 + 三端入口：
- **lib**：`Get-SystemHealthReport` / `Save-HealthReport` / `Get-PreviousHealthReport` / `Compare-HealthReports`
- **CLI**：`scripts/15-HealthCheck.ps1`（菜单 `[15] 一键体检`）
- **GUI**：`gui/pages/Health.ps1`（侧边栏「系统体检」，第 2 项）
- **WebUI**：`webui/ps/15_health.ps1` + `app.py` 路由 `/api/health` + MCP 工具 `health_scan` + 前端 `renderHealth()`

体检**只读取系统状态，不改任何设置**；报告存 `backups/health/`（已 gitignore），再次运行可与上一份对比（分数变化 / 已解决问题 / 新增问题 / 指标差值）。

### 3.2.1 体检自动修复 Auto-Remediation（2026-09-23）

体检此前只能"告诉用户该去点哪个菜单"，老电脑用户面对十几个菜单依然无从下手。现在把 issue
映射成具体动作并编排**已存在**的域函数一键修复：

| 层 | 内容 |
|----|------|
| lib | `Get-HealthRemediationCatalog`（唯一映射表：issue → 域 / 函数 / 是否可自动执行）、`Resolve-HealthRemediation`、`Get-HealthRemediationPlan`（只读预览）、`Invoke-HealthRemediation`（执行） |
| CLI | `scripts/15-HealthCheck.ps1` 报告后追加「自动修复预览」+ `Y` 确认执行 |
| GUI | `gui/pages/Health.ps1` 新增「自动修复预览」文本框与「一键修复」按钮（确认框 + 执行后自动重新体检） |
| WebUI | `webui/ps/15_health.ps1` 增加 `-Action plan|remediate`；路由 `/api/health/plan`、`/api/health/remediate`；MCP 工具 `health_plan` / `health_remediate`；前端 `renderHealth()` 渲染预览表格 + 两个修复按钮 |

安全约束（lib 强制，三端无法绕过）：
- **只读先行**：`Get-HealthRemediationPlan` 不碰系统，可随时预览；`-WhatIf` 完全零副作用（连备份都不写）。
- **修改必备份**：每步执行前自动调用对应域 `Backup-*`（服务 / 视觉 / 电源 / 网络 DNS）。
- **高危不放行**：`High` 级 issue 一律不自动执行，需 `-MaxSeverity High` 且 `-Force` 双确认（默认只放开 Medium/Low）。
- **仅建议不动手**：`startup.many` / `memory.low` / `disk.space` 只列清单，永不自动执行。
- **动作合并**：多个网卡同时命中 `network.dns.*` 时合并为一次网络优化，避免重复备份/重复改 DNS。

### 3.4 优化时间线 + 一键回滚向导（P0-4，2026-09-24）

此前每域各自备份到 `backups/`，恢复要逐域翻菜单，用户也无从知道「上周到底改了什么」。现已把备份元数据、
时间线与回滚全部下沉 lib，三端共用同一实现：

| 层 | 内容 |
|----|------|
| lib | `Write-BackupManifest`（每次 `Backup-*` 落一份 `<备份文件>.manifest.json`：version/domain/file/date/time/items/bytes/host/user/note，失败返回 `$null` 不影响备份本身）、`Get-BackupDomainFromName`（新命名 `services_backup_*` 与旧命名 `services_*`/`winupdate_block_*`/`manual_update_*` 都认）、`Get-BackupDomainLabel`、`New-BackupTimelineEntry`、`Get-OptimizationTimeline [-Max 200]`、`Get-RollbackPlan [-Since|-Last n] [-Domain] [-File]`、`Backup-DomainState`（回滚前的「后悔药」）、`Restore-DomainState`（按域分发，`health`/`unknown` 返回 `$null`）、`Format-RestoreDetails`、`Invoke-Rollback [-DryRun] [-SkipBackup] [-Force]` |
| 新增域还原 | `Restore-StartupItems` / `Restore-VisualEffects` / `Restore-PowerPlan` / `Restore-NetworkSettings` / `Restore-UpdateBackup`；`Restore-Services` 补充 `-File`（省略仍取最新，行为不变） |
| CLI | `scripts/09-BackupRestore.ps1` 重写：时间线（编号/时间/域/条目数/元数据缺失标记）→ 编号=单条恢复（先 `Backup-DomainState`）、`[A]`=每域最近备份、`[Z]`=一键回滚向导（1=时间点 / 2=回退 N 条，先只读预览再 `Y` 确认）、`[R]`=启动文件夹项、`[N]`=取消 |
| GUI | `gui/pages/Backup.ps1` 重写：时间线 `DataGridView` + 「一键回滚向导」（InputBox 选模式 → 计划预览 → 确认执行）+「恢复选中备份」；创建备份改为 6 个域全走 `Backup-DomainState` |
| WebUI | `webui/ps/09_backup.ps1` 增加 `-Action timeline|create|restore|rollback`（`-Since`/`-Last`/`-Domain`/`-File`/`-DryRun`/`-SkipBackup`）；`webui/app.py` 增加 `/api/backup/timeline`、`/api/backup/rollback` 与 MCP 工具 `backup_timeline` / `backup_rollback`；`webui/templates/index.html` 的 `renderBackup()` 渲染时间线表格 + 回滚预览卡片 + 确认执行 |

安全约束（lib 强制，三端无法绕过）：回滚顺序固定为 `services → startup → visual → power → network → telemetry → update`；
每个域还原前先 `Backup-DomainState` 备份当前状态（可再次反悔），该备份失败默认中止、`-Force` 才继续；
`-DryRun` 与 `Get-RollbackPlan` / `Get-OptimizationTimeline` 全程只读零副作用；不可回滚域进 `skipped` 并说明原因。

已知实现细节（改代码前先看）：`Backup-PowerPlan` 已从 `.txt` 改为结构化 `.json`（`activeGuid`/`activeName`/`query`），
旧 `.txt` 无法可靠解析，只给手动提示；`Restore-StartupItems` 只处理「启动文件夹」与「注册表」两类来源，
WMI「系统启动命令」行与它们重复，仅登记不动作。

### 3.5 优化组合包 Profiles（P0-3，2026-09-24）

完整优化原本要点 5~6 个菜单，不同场景（办公 / 游戏 / 省电）取舍也不同。现在把「按场景一键到位」下沉为 lib 编排层，三端共用同一份计划与同一套风险闸门：

| 层 | 内容 |
|----|------|
| lib | `Get-ProfileDefaults`（字段默认值）、`Get-BuiltinProfiles`（4 个内置兜底包）、`Get-Profiles`（config `profiles` 为唯一真源，缺失回退内置）、`Get-Profile`（按 name/title 查）、`Get-ProfilePowerGuid`（high/ultimate/balanced/power_saver + 裸 GUID，未知返回 `$null`）、`Get-ProfileSteps`（展开为步骤）、`Get-ProfilePlan [-Name]`（只读预览）、`Invoke-Profile [-Name] [-BackupDir] [-WhatIf] [-Force]` |
| config | `config/optimization.json` 新增 `profiles`（`old_balanced` / `gaming` / `quiet_saver` / `minimal`），`config/optimization.schema.json` 同步补 `profiles` 定义（含各字段 enum 与裸 GUID pattern） |
| CLI | `scripts/16-Profiles.ps1`，`Optimize.ps1` 菜单 `[16] 优化组合包`：列表（编号/标题/步骤数/高风险标记）→ `Show-ProfilePlan` 只读预览 → `[1]` 预演 / `[2]` 确认执行 / `[N]` 取消；含高风险需二次 `Y` 确认 |
| GUI | `gui/pages/Dashboard.ps1` 新增「优化组合包 Profiles」卡片 + `Show-ProfileReport`；InputBox 选编号 → 预览 → 确认执行 |
| WebUI | `webui/ps/16_profiles.ps1`（`-Action list|plan|apply` + `-Name`/`-DryRun`/`-Force`）；`webui/app.py` 增加 `/api/profile/list`、`/api/profile/plan`、`/api/profile/apply` 与 MCP 工具 `profile_list`/`profile_plan`/`profile_apply`；前端 `renderProfiles()` 渲染组合包卡片 + 步骤预览表 + 预演/执行 |

**`Invoke-Profile` 是纯编排**：只调用已存在的域函数（`Disable-Services`/`Disable-StartupItems`/`Set-VisualEffectProfile`/`Set-PowerPlan`/`Invoke-NetworkOptimization`/`Disable-TelemetryTasks`/`Invoke-DiskOptimization`），**没有新增任何系统操作面**，因此每个域天然继承既有备份与 Win7 兼容层。

**风险闸门（lib 强制）**：`Get-ProfileSteps` 为每步派生 `risk`（low/medium/high）与 `auto`。
默认只执行 `auto -eq $true` 且 `risk -ne 'high'` 的步骤；其余进 `skipped`（带 `id`/`domain`/`risk`/`reason`/`action`），必须显式 `-Force` 才放行。
当前 config 下 `auto=$false` 与 `risk=high` 完全等价，只出现在两处：
`startup=all` 的「禁用全部启动项」与 `disk` 磁盘优化（含 CompactOS）。执行顺序固定
`services → startup → visual → power → network → telemetry → disk`，单步失败续跑不中断，结果汇总 `results`/`skipped`/`ok`/`dryRun`/`forced`。

已知取舍：`startup` 只有 `list`（只读列出）与 `all`（全禁）两档，没有逐项交互；`disk`/`compact_os` 未在任何内置包里启用（磁盘优化仍走 07 页按需触发）；未知的 `dns`/`visual`/`power` 值只跳过对应步骤，不整包报错。
### 3.6 定时体检 + 趋势报告（P1-1，2026-09-25）

`Save-HealthReport` 早已把每次体检落盘 `backups/health/*.json`，但从未被自动执行、也没人看趋势。本轮把「无人看的数据」变成「每日自动沉淀 + 一眼可读的趋势」。

| 层 | 内容 |
|----|------|
| lib | `Get-HealthTrend [-BackupDir] [-Days 30] [-MaxPoints 60]`（读 `backups/health/*.json`，输出 time/score/freeRamPct/cleanableMB/startupCount/issueCount 升序序列；超过 MaxPoints 均匀抽样且保留最新点）、`Format-Sparkline`（纯 ASCII 字符 sparkline，Win7 控制台等宽字体稳定显示）、`Test-IsAdmin`、`Install-HealthSchedule [-Time] [-HealthScript]`（schtasks 注册每日任务；非管理员降级 ONLOGON 并 warning 说明；校验/注册失败只返回 error，绝不抛异常）、`Remove-HealthSchedule`（幂等删除） |
| CLI | `scripts/15-HealthCheck.ps1` 新增 `-InstallSchedule` / `-UninstallSchedule` / `-Trend [-TrendDays] [-Time]`；每次体检后附带一行分数 sparkline；交互结尾提示一键注册；非交互环境（计划任务自动运行）自动跳过修复提问与注册提示（`[Environment]::UserInteractive`） |
| GUI | `gui/pages/Health.ps1` 关键指标区追加一行迷你 sparkline（数据源与 CLI/WebUI 完全一致） |
| WebUI | `webui/ps/15_health.ps1` 新增 `-Action trend`（scan 响应附带 `trend`）；`/api/health/trend` 路由 + MCP 工具 `health_trend`；前端「体检趋势」卡片 = 内联 SVG 折线 + 面积 + 逐点 tooltip + 最近 10 次表格，**零外链依赖，离线可用** |

测试：`tests/Optimize.Core.Tests.ps1` 新增 5 个用例（sparkline 映射 / 趋势序列与 `-Days`、`-MaxPoints` 抽样 / 空历史 / 计划任务参数校验 / `Test-IsAdmin`），**156/156 通过**；另做 CLI `-Trend`、WebUI `trend` action、GUI 无头构建+点击冒烟验证。

### 3.3 CompactOS：显式开关、默认关闭（2026-09-18 收口，原 §7.1）

此前 CLI 的 `scripts/07-DiskOptimize.ps1` **无条件**执行 `Compact.exe /CompactOS:always`，
而 GUI / WebUI 默认关闭 —— 三端不一致，且压缩系统文件耗时长、回滚要再跑一次 `Compact.exe /CompactOS:never`。

现统一为：

| 端 | 行为 |
|----|------|
| lib | 新增 `Get-CompactOSDefault()`，读 `config/optimization.json` 的 `disk.compact_os_default`（默认 `false`）；`Invoke-DiskOptimization -Compact` 默认值随之 |
| CLI | 新增 `-CompactOS` 开关；不带开关时按 config 默认（关闭）并打印跳过提示 |
| GUI | `chkCompact.Checked = (Get-CompactOSDefault)` |
| WebUI | 未显式传 `compact=true` 时按 config 默认（关闭） |

**一键全面优化（CLI `[9]`）不再压缩系统文件。** 测试侧新增 AST 断言：
CLI 脚本里的 `Set-CompactOSState` 必须处于 `if` 保护之下，防止再次回归成无条件压缩。


### 3.7 前后对比报告导出（P1-2，2026-09-25）

`Compare-HealthReports` 之前只能在屏幕上看，发帖求助时要手动截图、手掉数据，证明不了「优化前后真的改善了」。

| 端 | 落点 |
|----|------|
| lib | `Export-HealthReport -From -To -Format Html|Markdown [-BackupDir] [-OutDir] [-FileName]`；`-From/-To` 接报告对象或 health JSON 路径，省略时自动取历史最新两份；默认输出到桌面（失败回退 `%USERPROFILE%`）。渲染由 `ConvertTo-HealthCompareHtml` / `ConvertTo-HealthCompareMarkdown` 完成，HTML 全内联 CSS + 暗色模式、零外部请求，全文本 `HtmlEncode` 转义。返回 `@{ok;error;file;format;comparison}`。 |
| CLI | `scripts/15-HealthCheck.ps1 -Export [-Format Html|Markdown] [-From 路径] [-To 路径]`；交互环境下对比区后询问“是否导出”。 |
| GUI | `gui/pages/Health.ps1` “导出对比报告”按钮：Yes=HTML / No=Markdown / Cancel=取消，弹窗给出文件路径。 |
| WebUI | `webui/ps/15_health.ps1` `-Action export [-Format html|md] [-From] [-To]`；`POST /api/health/export` + MCP `health_export`；健康页“导出对比报告”按钮 + 格式下拉。 |

测试：`tests/Optimize.Core.Tests.ps1` 新增 6 个用例（HTML 自包含断言 / Markdown 表格 / JSON 路径传参 / 自动取最新两份 / 缺报告安全失败 / HTML 转义），全量 **162/162** 通过。
已经过实测：CLI / WebUI 端到端导出成功，GUI 无头 harness 验证控件布局（14 控件）。



### 3.8 优化前自动创建系统还原点（P1-3，2026-09-26）

备份文件只覆盖自己动过的那些键值；系统还原点是整机快照，改坏了能整体退回去。

| 端 | 落点 |
|----|------|
| lib | `Get-RestorePointDefault`（config 的 `safety.create_restore_point`，**默认 false**）、`Test-SystemRestoreEnabled`（只读注册表）、`New-SystemRestorePoint [-Description] [-WhatIf]`：先 `Checkpoint-Computer`（Win8+），失败退 WMI `SystemRestore.CreateRestorePoint`（Win7 可用）。非管理员 / SR 关闭 / 24h 节流均返回 `@{ok=$false; error}`，**不弹异常、不阻塞**。 |
| lib | `Invoke-HealthRemediation` / `Invoke-Profile` 新增 `-CreateRestorePoint`；**懒创建**——真要动系统的第一步前才建，全部步骤被跳过时不默默硬建；`-WhatIf` 不建。结果对象新增 `restorePoint` 字段。 |
| CLI | `15-HealthCheck.ps1 -RestorePoint`；`16-Profiles.ps1` 确认执行前询问；两者都先检查管理员与 SR 开关并提示。 |
| GUI | `gui/pages/Health.ps1` 一键修复行增加复选框“执行前先建系统还原点”；执行后弹窗告知成功/失败。 |
| WebUI | `webui/ps/15_health.ps1` / `16_profiles.ps1` 参数 `-CreateRestorePoint`（**auto / true / false** 三态字符串，默认 auto）；`/api/health/remediate` 与 `/api/profile/apply` + MCP 同名参数；前端两处复选框（`cbHealthRp` / `cbProfRp`）。 |

**为什么默认关闭**：很多老机器本就关着 System Restore，感觉上打开会占掉几个 GB 磁盘；因此只做“请求创建”，不感觉开启 SR。

**坑**：`powershell -File` 调用时 `[bool]` 参数绑定不了字符串 `false`，所以 WebUI 侧用三态字符串；另外 lib 是在 `param()` 之后才 dot-source 的，**参数默认值里不能调 lib 函数**（会命令未找到）。

测试：`tests/Optimize.Core.Tests.ps1` 新增 9 个用例，全量 **171/171** 通过。

---

### 3.9 P2 智能降级建议（2026-09-26，待发布）

体检原来只回答「哪里有问题、去哪号菜单」，现在进一步回答「先动哪个最划算」。全程只读。

| 层 | 落点 | 说明 |
| --- | --- | --- |
| lib | `Get-StartupRiskScore` | 纯函数打分：僵尸项 +40、更新程序 +30、云同步 +25、后台助手 +20、预加载 +15、用户目录 +10；`RunOnce` −20；命中系统/硬件/安全黑名单直接 −1000（**宁可漏推荐，不可错关**）。 |
| lib | `Get-StartupTargetPath` | 从 `Value` 里解析目标路径（处理引号、参数、`%VAR%`），只用于「目标还在不在」判断与展示。 |
| lib | `Get-SmartRecommendations` | 门控：`memory.low`/`startup.many` → 启动项建议；`disk.space`/`disk.cleanable` → 清理建议；没命中就不瞎建议。清理体积**优先复用本次体检已量好的 `metrics.cleanTargets`**，不重复扫盘。 |
| lib | `Format-SmartRecommendations` | 三端共用渲染，保证 CLI / GUI / WebUI 文案零漂移。 |
| CLI | `scripts/15-HealthCheck.ps1` | 体检输出里「问题清单」之后新增「智能建议」段。 |
| GUI | `gui/pages/Health.ps1` | 新增「智能建议（先动哪个最划算）」面板（y=802，自动滚动区内）。 |
| WebUI | `webui/ps/15_health.ps1 -Action tips` + `GET /api/health/tips` + MCP `health_tips` | 体检页新增「智能建议」表格；`-Action scan` 的响应里也直接带 `tips`，少一次请求。 |

**边界**：`-StartupItems` 传空数组时必须判 `$null -ne $StartupItems`——PowerShell 里空数组求值为 `$false`，写成 `if ($StartupItems)` 会把「显式传空」误判成「没传」而去读真实注册表（测试里踩过）。

测试：新增 12 个用例（目标路径解析 / 黑名单 / 僵尸项 / 降权 / Top 与排序 / 报告门控 / 复用测量 / 渲染），全量 **188/188** 通过。

### 3.10 静默故障修复（2026-09-26，PR #14）

两类「语法检查通过、运行到那一行才炸」的问题，根因都是通过命令行写中文时被 GBK 转码损坏：

1. **弯引号被当成字符串定界符**（`“ ”` 取代 ASCII `"`）：`Install-HealthSchedule` 的三个 error 分支与管理员分支的 `$trigger`，以及 GUI 体检趋势那一行。中招后前者报 CommandNotFoundException，后者让 GUI 体检直接走 catch 显示「体检出错」。
2. **`[PSCustomObject]{ }` 漏写 `@`**：多行/单行写法都会被解析成「脚本块转型」，返回 `ScriptBlock` 而不是对象，调用方读 `.ok` / `.error` 全是空。命中 `lib` 的 schtasks 失败分支与 `webui/ps/15_health.ps1` 的 catch 分支。

防回归：新增 `Describe 'PowerShell source hygiene'`，静态检查所有 `.ps1` 语法零错误、无弯引号定界符、无漏 `@` 的 `[PSCustomObject]{`。

### 3.11 P2-1 统一优化预览（2026-09-26，待发布）

「一键全面优化」到底会动什么？新增只读 dry-run：**不碰系统**，只回答「点下去会发生什么」。

| 层 | 落点 | 说明 |
| --- | --- | --- |
| lib | `New-OptimizePlanStep` / `Get-OptimizePlan` / `Format-OptimizePlan` | plan 覆盖 [2]清理/[3]服务/[4]启动项/[5]视觉/[6]电源/[7]磁盘/[8]网络/[10]遥测/[16]组合包 9 类步骤；每步带 domain/title/menu/action/target/detail/impact/risk；返回 `@{ ok; version; generatedAt; powerPlan; dns; steps; summary }`，summary 按 low/medium/high 计数。 |
| CLI | `Optimize.ps1 -Plan [-Profile <name>] [-SkipCleanScan]`；菜单新增 `[P] 优化预览（只读）` | 分支放在管理员检查**之前**：只读预览不需要提权。默认带清理体积统计（扫盘约十几秒），`-SkipCleanScan` 可跳过。 |
| WebUI | `webui/ps/optimize_plan.ps1 -Action plan` + MCP `optimize_plan(profile, skip_clean_scan)` | 已登记 `LONG_TASK_SCRIPTS`，与 `health_scan` 并列。 |

**坑（本次新踩，见 §5）**：`param([switch]$Plan)` 会让脚本内所有 `$plan` 变量变成强类型 `SwitchParameter`，
`$plan = Get-OptimizePlan ...` 直接抛「Cannot convert PSCustomObject to SwitchParameter」，且错误栈只指向调用行，极难定位。
**给脚本加 `-Xxx` switch 参数前，先全文搜一遍 `$xxx` 小写同名变量**。本次已改名 `$planPreview` 并加注释。

测试：新增 6 个用例（步骤结构 / summary 与实际一致 / 电源与 DNS 标签解析 / 组合包与未知组合包 / 清理步可选 / 渲染契约），全量 **194/194** 通过。

### 3.12 开机性能基线 bench（P2-2，2026-09-26，待发布）

「优化有没有变快」终于可量化：体检报告新增 `bench` 段，随历史沉淀进趋势图。

| 层 | 落点 | 说明 |
| --- | --- | --- |
| lib | `Get-SystemBench` | `%TEMP%` 下落一块 64MB 临时文件，顺序写 + 顺序读回后立即删除（实测约 0.4-1s）；返回 `diskReadMBps / diskWriteMBps / startupCount / autoServices / totalRamMB / elapsedMs / error`。磁盘探测失败不拖垮整体（error 记录原因，磁盘项为 0）。 |
| lib | `Get-AutoOptimizableServices` | 「仍为自动启动的可优化服务」清单抽成共享 helper，体检与 bench 共用，不再两处各扫一遍 CIM。 |
| lib | `Get-SystemHealthReport -SkipBench` | `bench` 挂**报告顶层属性**（不放 metrics：不影响评分、不进 Compare-HealthReports 的差值遍历）。 |
| CLI | `scripts/15-HealthCheck.ps1` | 「关键指标」后新增「性能基线」段；`-Trend` 新增磁盘读 sparkline；新增 `-SkipBench`（计划任务夜间跑可省 ~1s）。 |
| GUI | `gui/pages/Health.ps1` | 关键指标文本框追加三行：磁盘顺序读/写、开机加载负担、探测耗时。 |
| WebUI | `webui/ps/15_health.ps1` + `index.html` | scan 响应随 report 带出 bench；关键指标表加「性能基线 / 开机负担」两行；趋势区新增磁盘读 SVG 折线（复用 score 折线的同款零依赖画法）。 |

**兼容性**：`Get-HealthTrend` 的每个点新增 `diskReadMBps`，旧报告（无 bench 段）按 0 处理，不抛异常；
WebUI 折线只在采样点 ≥2 且 >0 时渲染，老用户升级后第一篇带 bench 的报告落地才出线。

测试：新增 6 个用例（探测结构 / 复用计数 / 实扫计数 / 报告挂载 / `-SkipBench` / 旧报告趋势兼容），全量 **200/200** 通过。

### 3.13 P3-1 智能建议一键应用闭环 + 服务依赖护栏 + 真实开机耗时（2026-09-26，v3.9.0）

| 层 | 落点 | 说明 |
|----|------|------|
| lib | `Invoke-SmartRecommendations` | 智能建议从只读变可执行：只应用启动项类，先备份（一次覆盖全部选中项，失败即中止）再禁用；`-CreateRestorePoint` 懒创建；`-WhatIf` 零副作用；建议与现场不一致时安全失败（匹配不到不动手）。返回 `@{ ok; whatIf; applied; failed; backup; restorePoint; error }` |
| lib | `Get-ServiceDependents` + `Disable-Services -Force` | 正被运行中服务依赖的服务默认跳过并说明原因；WMI `Win32_DependentService`（Win7 兼容）；查询失败按空处理不阻碍流程 |
| lib | `Get-BootPerformanceSample` | 解析 Diagnostics-Performance Event 100 取最近一次真实开机耗时；bench 新增 `bootSeconds/bootAt/bootSource/bootError`，历史报告无数据按 null 兼容 |
| CLI | `15-HealthCheck.ps1` 智能建议段后交互应用；bench 段展示开机耗时；`03-DisableServices.ps1` 备份/禁用下沉 lib 并新增 `-Force` | 非交互环境自动跳过提问 |
| GUI | `gui/pages/Health.ps1`「应用智能建议」按钮（完成后自动重新体检）；`gui/pages/Services.ps1` 改走 lib 禁用（获得护栏 + manifest 备份） | 还原点复用体检页同一复选框 |
| WebUI | `15_health.ps1 -Action apply-tips` + `POST /api/health/apply-tips` + MCP `health_apply_tips` + 体检页按钮 | `-CreateRestorePoint` 沿用 auto/true/false 三态字符串 |

**边界**：清理类建议永远不自动执行（删文件不可逆性强）；WMI 来源启动项无法代码禁用，
`failed` 里给「需通过任务管理器手动禁用」的理由；开机耗时探测不到事件时只少一个指标，不报错。

测试：新增 16 个用例（应用闭环 / WhatIf 零副作用 / 还原点懒创建 / 建议消失安全失败 /
部分失败上报 / 依赖护栏默认跳过与 -Force 覆盖 / 开机耗时结构与趋势兼容），全量 **216/216** 通过。
CLI 03/15、WebUI `tips`、`apply-tips -WhatIf` 与首页渲染均实测通过。
---

### 3.14 P4-1 启动项建议「签名厂商否决」（2026-09-26）

P3-1 把「智能建议」变成一键可执行后，误关代价从「读一遍」变成「点一下」；而名字黑名单
（`Get-StartupRiskScore` 的关键词匹配）管不住改名 / 换目录 / 伪装名的系统组件与驱动。本节补上
最后一道准确性护栏：**数字签名**。

| 层 | 落点 | 说明 |
|----|------|------|
| lib | `Get-FilePublisher` | 取目标文件数字签名证书的 CN（`Get-AuthenticodeSignature`，PS2 可用）；任何失败返回空串（按未知处理），绝不抛异常 |
| lib | `Get-TrustedPublisherPatterns` / `Test-TrustedPublisher` | 受保护厂商特征列表，唯一真源 = `config/optimization.json` 的 `smart.trusted_publishers`（子串匹配、大小写不敏感），缺失回退内置默认（Microsoft/Intel/NVIDIA/AMD/Realtek/Synaptics/Dell/HP/Lenovo） |
| lib | `Get-SmartRecommendations` | 启动项打分前加否决：目标存在且签名命中受保护厂商 → 不进推荐，记入返回值新增的 `vetoed`（name/command/path/publisher/reason）；推荐项新增 `publisher` 字段 |
| lib | `Format-SmartRecommendations` | 统一渲染「签名:」行与「已保护」清单；CLI / GUI 零改动即得 |
| WebUI | `15_health.ps1 -Action tips` 带出 `vetoed`；`templates/index.html` 建议表下方展示被保护项与原因；`scan` 内嵌 `tips` 同步生效 | `app.py` 透传无需改动 |

**边界**：
- 「未知」不等于「信任」：未签名 / 取不到签名的启动项**不**否决，仍按既有打分规则参与推荐（不提高虚警）。
- 只影响「智能建议」链路（含 P3-1 一键应用 `Invoke-SmartRecommendations`，天然继承）；
  菜单 [4] 手动禁用启动项不受影响，高级用户仍可自行决定。
- 取签名为本地只读操作，无网络；每个候选启动项最多调用一次，失败静默降级为空串。

测试：新增 10 个用例（CN 解析与 `CN=` 前缀剥离 / 空路径与未签名 / 异常吞噬 / 厂商匹配大小写 /
config 回退 / 厂商签名项被否决并带原因 / 第三方签名项照常推荐且带 publisher / 未签名不否决 /
一键应用不碰签名项 / 「已保护」文案渲染），全量 **226/226** 通过。

### 3.15 UI 改版：浅色「苹果风」主题（WebUI + GUI 同源配色）

原 WebUI 是深色底 + 亮蓝，GUI 也是深色（`BgDark=(30,30,40)`）。本轮统一改成浅色苹果风。

| 层 | 落点 | 说明 |
|----|------|------|
| WebUI | `webui/templates/index.html` 的 `:root` | `--bg:#f5f5f7` / `--panel:#fff` / `--panel2:#f2f2f7` / `--text:#1d1d1f` / `--dim:#6e6e73` / `--accent:#007aff`；卡片白底 + 细边 + 轻投影，系统字体栈（`-apple-system` / `Segoe UI` / `Microsoft YaHei UI`），补齐 `:focus-visible` 焦点环与 `prefers-reduced-motion` 降级；语义色用 Apple 深色变体（绿 `#248a3d` / 黄 `#9a6700` / 红 `#d70015` / 橙 `#c93400`）保证白底可读 |
| GUI | `OptimizeGUI.ps1` 的 `$script:Theme` | 键名保持不变（只换配色语义，避免逐个改页面）：`BgDark`→窗口浅灰、`BgPanel`→次级面板浅灰、`BgCard`/`BgInput`→白、`Accent`→`#007AFF`、`TextMain`/`TextBright`→`#1D1D1F`、`TextDim`→`#6E6E73`、`Success/Warning/Error` 用上表同款深色变体 |
| GUI | `New-Button` / 导航按钮 / `New-Card` 标题 / `LogTextBox` | 新增 `ButtonText=(255,255,255)`：强调色与彩色按钮白字，浅色主题下不掉对比度；卡片标题改用 `TextMain`（浅底上 `TextBright` 等于正文色，语义重复）；日志框硬编码的 `FromArgb(25,25,35)` 改为 `$Theme.BgCard` |
| GUI | `gui/pages/{Services,Startup,Backup}.ps1` | DataGridView 选中行前景改 `ButtonText`（蓝底白字），表头前景改 `TextMain`（浅灰底深字） |
| GUI | `gui/pages/About.ps1` | 「检查更新」按钮硬编码的 `Color::White` 改 `$Theme.ButtonText` |
| 文档 | `README.md` | 「现代化深色主题」→ 浅色主题描述 |

**验证（2026-10-03 升级到真机像素级）**：

| 端 | 手段 | 结果 |
|----|------|------|
| WebUI | 真实浏览器桌面视口（1440×1000）headless 截图 | 浅色侧栏 + 白卡片 + `#007AFF` 强调色 + 系统字体，HTTP 200 / 57 KB |
| WebUI | 窄屏 CSS 复核 | 导航由纵向堆叠改为三列，横向滚动条消失 |
| GUI | **新增无头真机渲染 harness**（见 §3.16） | 12 个页面全部逐页出图并肉眼核对 |
| GUI | 像素探针 | 复选框底 `#F5F5F7`、列表底 `#FFFFFF`，无「深色压深色」 |
| EXE | `PC-Optimizer.exe` 重建（652 KB / v3.10.0） | 二进制内可检索到新主题与布局字符串 |

GUI 侧要点：harness dot-source 真实前导段 + 主窗体 UI 段构建**真实控件树**，`$MainForm.Show()` 让窗口真正 realize 后再
`DrawToBitmap` 逐页出图——窗口级渲染不再需要交互式桌面（原先「沙箱会杀掉窗口进程、只能验属性不能验像素」的限制已解除）。

---

### 3.16 GUI 布局撞车修复（2026-10-03）

浅色主题上线后做真机渲染时，发现 5 处**既有**控件重叠（与配色无关，属历史遗留）。同批一并修掉：

| 页面 | 症状 | 修复 |
|------|------|------|
| Clean | `CleanListBox` 同时锚定 `Top\|Bottom\|Left\|Right`。`Reposition-PageControls` 每次重排都会把「靠左且宽度 ≥ 400」的控件宽度改成 `$maxW`，WinForms 把这次**宽度**变化当成一次纵向缩放，`Height` 随之按帧累加（实测 830 → 1814 → 2552 px），最终吞掉下方 3 个复选框、`BtnClean`/`BtnCancelClean` 与进度标签 | 去掉 `Bottom` 锚（只留 `Top\|Left\|Right`），高度固定 182（底边 338）；操作区上移到 340/372/424 |
| Services | 表格底边 376 压住 `chkTelemetry`(y=366) 10 px | 表格高 280 → 240（底边 336） |
| Startup | 表格底边 456 压住两个按钮(y=446) 10 px | 表格高 360 → 312（底边 408） |
| Health | `BtnHealthExport`(x=350) 与 `chkHealthRp`(x=515)、右侧对比标签(x=340,w=440) 三方互相压字 | 操作行重排为 20/180/340/515，对比标签下移独占一行(y=762)，`lblTips` 772→796、`TxtHealthTips` 802→826、`BtnHealthApplyTips` 960→984 |
| Dashboard | `btnFull` 写死 `$yDisk + 112`，比系统信息卡片底边还高 4 px | 改成与「刷新信息」同源：`$yDisk + 4 + $cardSysHeight + 12` |

**教训（写进 §5）**：给控件加 `Anchor = Bottom` 之前，先确认它不会同时被 `Reposition-PageControls`
改宽度；两者叠加会产生「每次 Resize 长高一点」的正反馈。

**回归**：新增重叠审计（遍历每页顶层控件两两求交），窗口尺寸 900×640（MinSize）、1000×700、
1024×720、1280×880、1400×1000、1600×900、1920×1080 **七档全部 0 重叠**；
`Clean` 列表高度在连续 Resize 后稳定在 182（修复前一路涨到 2552）。测试套件 **226 例无回归**。

### 3.17 UI 苹果风复核与工程性加固（2026-10-03 续）

对 §3.15 / §3.16 同批改动做二次真机复核，并顺手补两处工程性隐患：

- **重叠审计复跑**：窗口 900×640、1000×700、1024×720、1280×880、1400×1000、1600×900、1920×1080
  七档**全部 0 重叠**（修复前为 11~12 处）。
- **12 页真机渲染复查**：逐张目视确认清洁页底部 3 个复选框与「开始清理 / 取消 / 就绪」全部可见、
  启动页表格不再压住两个按钮、仪表盘「一键全面优化」与系统信息卡不再叠字。
  日志面板左侧竖排那条「清空」是 `btnClearLog`（`OptimizeGUI.ps1:730`），**不是缺陷**。
- **换行归一**：13 个改动文件曾被编辑器混入裸 LF（`git diff` 会报 `LF will be replaced by CRLF`）。
  已统一回 `CRLF`，并逐文件与 `HEAD` 比对确认 BOM 状态未变；解析器 0 错误。
- **`.gitignore` 加固**：新增 `.codex-*` 规则。此前本地临时脚本/截图/日志只被 `_*.ps1`、`_*.png`
  间接覆盖一部分，是裸 `git add -A` 误入库的隐患；已用 `git check-ignore` 验证命中。
- **EXE 重建**：`PC-Optimizer.exe` 重新编译（667,648 字节），二进制 UTF-16LE 段确认含
  `FromArgb(0, 122, 255)`、`Reposition-PageControls`、`$yDisk + 4 + $cardSysHeight + 12` 等本次固化的配色与布局串。

**入库**：改动提交到分支 `codex/ui-apple-style` 并推送、开 PR；`main` 受保护，最终由维护者点 Merge。

**旁注（沙箱假故障）**：把 WebUI 放在 Codex 沙箱里跑时，`/api/overview` 会整页显示
「获取失败 拒绝访问」——因为沙箱内所有 `Get-CimInstance` 都被拒绝（`IsInRole(Administrator)=False`）。
在沙箱外以普通用户（medium 完整性）运行同一脚本一切正常，属**测试环境假象**，不是产品缺陷。

### 3.18 发布版 EXE 缺页修复：`Health.ps1` 从未被打进 `PC-Optimizer.exe`（2026-10-03 续）

**症状**：仓库里入库的 `PC-Optimizer.exe`（274,432 字节）双击运行后**没有「系统体检」页**，
且页面数是 11 个（README 写 11、About 页写 10，三处互相矛盾）。

**根因**：`Build-EXE.ps1` 的 `$pageFiles` 白名单漏了 `pages/Health.ps1`。
GUI 源码运行（`OptimizeGUI.ps1` 直接跑）走的是 `#region GUI-PAGE-LOADER` 里的 `$pageLoader`，
那份列表**有** Health，所以源码运行正常；但构建 EXE 时该 region 会被剥离，
真实页面清单以 `Build-EXE.ps1` 的 `$pageFiles` 为准 —— 于是「源码能看到的页，EXE 里没有」，
形成一条只在发布物上暴露的静默缺陷。

**证据**：对新旧 EXE 各做一次 UTF-16LE 解码后检索：

| 二进制 | 字节数 | `Build-HealthPage` | `系统体检` |
|--------|--------|--------------------|-----------|
| `HEAD:PC-Optimizer.exe`（旧） | 274,432 | ❌ | ❌ |
| 本次重建 | 667,648 | ✅ | ✅ |

**修复**：`Build-EXE.ps1` 的 `$pageFiles` 补上 `"pages/Health.ps1"`（一行改动），重新编译。
重建后 EXE 同时包含 `FromArgb(0, 122, 255)`、`FromArgb(245, 245, 247)`、`Reposition-PageControls`、
`$yDisk + 4 + $cardSysHeight + 12` 等本次固化的配色与布局串，且 `GUI-PAGE-LOADER` 的 dot-source
代码已按预期被剥离（EXE 内检索为空）。

**教训**：EXE 页面清单与 `#region GUI-PAGE-LOADER` 的 `$pageLoader` 是**两份手工维护的列表**，
必须同步。以后新增 GUI 页面，两处都要加；PR 前用「二进制检索页名」做一次交叉验证即可发现漏项。

**旁注**：`PC-Optimizer.exe` 是按「发布资产」入库的，但 `release.yml` 只在打 `v*` tag 时才重新构建。
也就是说**日常 push/PR 不会刷新仓库里那份 EXE** —— 本次这类漏页缺陷能长期存在而不被 CI 发现，正是这个原因。
若希望仓库内 EXE 始终可信，建议后续在 CI 里加一步「构建后与入库 EXE 比对/覆盖」。

---

### 3.19 WebUI 系统概览容错（2026-10-03 续）

**背景**：有用户截图显示 WebUI「系统概览」整页只剩一行红字「获取失败 拒绝访问」。

**定位**：webui/ps/01_system_info.ps1 原本把 OS / CPU / 磁盘 / 显卡四组查询塞在同一个外层
try/catch 里，任何一组抛异常都会走到 catch 分支，整页退回 ok=false + error=拒绝访问，
前端于是什么都不显示。这次截图正是沙箱环境（见 §3.17 旁注）触发；但产品侧同样存在：
某块磁盘被 BitLocker 锁定、显卡驱动异常等都可能让整页空白。

**修复**：

- 01_system_info.ps1 改为**分组容错**：OS/内存/运行时间、CPU、磁盘、显卡各自独立 try/catch，
  失败只清空本组或降级该字段，并把「分组: 原因」收进 errors 数组；ok 仅在 errors 为空时为 true。
  字段名/结构与旧版保持一致，向后兼容。
- webui/templates/index.html 的 renderOverview() 配合：完全失败（无 osName 且无磁盘）仍是红字
  「获取失败」并带上 errors 明细；部分失败则在顶部显示黄色「部分数据不可用 + 明细」，其余卡片照常渲染。

**验证**（真机 Chrome，非沙箱）：

| 场景 | 结果 |
|------|------|
| 正常 | ok=true，OS / CPU / 内存 / 5 块磁盘 / 4 个显卡全部显示 |
| 全部失败（沙箱内实例 :5055） | 红字「获取失败 os: 拒绝访问；cpu: …；disks: …；gpus: …」 |
| 仅磁盘失败（stub） | 黄字「部分数据不可用 disks: access-denied」，其余卡片正常 |

**顺带**：01_system_info.ps1 原有的 3 处裸 LF 一并归一到 CRLF（BOM 保持）；全仓库 76 个 .ps1 解析 0 错误。


## 4. 三端文件地图（按域）

> 命名约定：CLI = `NN-Name.ps1`，GUI 页面 = `gui/pages/Name.ps1`，WebUI = `NN_name.ps1`。

| 域 | CLI | GUI 页面 | WebUI ps | 共享 lib |
|----|-----|----------|----------|----------|
| 系统信息 / 仪表盘 | 01-SystemInfo.ps1 | Dashboard.ps1 | 01_system_info.ps1 | `Get-SystemInfo` 等 |
| 临时文件清理 | 02-CleanTemp.ps1 | Clean.ps1 | 02_clean.ps1 | `Get-CleanTargets`/`Get-FolderSize` |
| 服务优化 | 03-DisableServices.ps1 | Services.ps1 | 03_services.ps1 | `Get-ServiceList`/`Set-ServiceMode` |
| 启动项 | 04-StartupOptimize.ps1 | Startup.ps1 | 04_startup.ps1 | `Get-StartupItems` 等 |
| 视觉效果 | 05-VisualEffects.ps1 | Visual.ps1 | 05_visual.ps1 | `Get-VisualEffect*` |
| 电源计划 | 06-PowerPlan.ps1 | Power.ps1 | 06_power.ps1 | `Get-ActivePowerPlan` 等 |
| 磁盘优化 | 07-DiskOptimize.ps1 | Disk.ps1 | 07_disk.ps1 | `Invoke-DiskOptimization` 等 |
| 网络优化 | 08-NetworkOptimize.ps1 | Network.ps1 | 08_network.ps1 | `Invoke-NetworkOptimization` 等 |
| 备份恢复 | 09-BackupRestore.ps1 | Backup.ps1 | 09_backup.ps1 | `Backup-*` / `Restore-*` / `Get-OptimizationTimeline` / `Invoke-Rollback` |
| 屏蔽 Win11 24H2 | 10-BlockWin1124H2.ps1 | Update.ps1 | 10_block_update.ps1 | — |
| 手动更新模式 | 11-ManualUpdateMode.ps1 | Update.ps1 | 11_manual_mode.ps1 | — |
| 隐藏更新 | 12-HideUpdates.ps1 | Update.ps1 | 12_hide_updates.ps1 | — |
| Windows 功能 | 13-WindowsFeatures.ps1 | Update.ps1 | 13_features.ps1 | — |
| 恢复自动更新 | 14-RestoreAutoUpdate.ps1 | Update.ps1 | 14_restore_autoupdate.ps1 | — |
| 一键体检 | 15-HealthCheck.ps1 | Health.ps1 | 15_health.ps1 | `Get-SystemHealthReport` 等 |
| 优化组合包 | 16-Profiles.ps1 | Dashboard.ps1（卡片） | 16_profiles.ps1 | `Get-Profiles` / `Get-ProfilePlan` / `Invoke-Profile` |

更新相关域（10–14）在 GUI 中统一归入 `Update.ps1` 一个页面。

---

## 5. 踩过的坑 / 维护时务必注意

1. **PowerShell 5.1 中文必须带 BOM（UTF-8 BOM）**。无 BOM 会被按 ANSI 读取，中文乱码，`ConvertFrom-Json` 后中文比对全部失败。所有 `*.ps1` 保存时一律 UTF-8 BOM。
   自检：`[System.IO.File]::ReadAllBytes($f)[0..2] -eq @(0xEF,0xBB,0xBF)`。
2. **磁盘域必须 Win7 兼容**：统一走 `WMI + defrag.exe + fsutil`，**禁止使用 Storage 模块**（`Get-PhysicalDisk`/`Optimize-Volume` 在 Win7 不存在）。
3. **SSD 检测是分级回退**：WMI 显式 SSD → `defrag /A`（需管理员）→ `fsutil` 全局 → 兜底 HDD。
   - 非管理员下 `defrag /A` 报 `0x89000024`，逐卷介质拿不到会退化到全局 `fsutil`；**生产环境（提权运行）不会出现**。
   - 兜底方向是「误判 SSD → 只 TRIM（空操作无害）」，而非「误判 HDD → 去整理 SSD（有害）」，安全。
   - `MSFT_PhysicalDisk.DeviceId` 与 `Win32_DiskDrive.Index` **一一对应**，必须按 DeviceId 匹配（按容量匹配会因 ~4MB 差异失败）。
4. **DNS 选项编号稳定**（1=Cloudflare / 2=Google / 3=阿里 / 4=114 / 5=腾讯）：WebUI 前端 `index.html` 硬编码了编号，**只能改地址不能改编号**。地址可在 `config/optimization.json` 的 `dns_options` 覆盖。
5. **网络适配器自动排除虚拟/隧道网卡**（Hyper-V、VPN、蓝牙等），避免误改导致断网。规则在 lib 网络段的 `$script:VirtualAdapterPatterns`。
6. **所有修改类操作前自动备份到 `backups/`**（已 gitignore，不入库）；GUI 的 `[B]` 恢复、CLI 备份恢复脚本依赖它。
7. **GUI 页面可以做窗口级像素渲染**（2026-10-03 更新，此前的「不可行」结论已推翻）。
   关键：不要用 `CopyFromScreen`（沙箱里报句柄无效），改用 `Form.Show()` 把窗口真正 realize 之后再
   `Form.DrawToBitmap()` —— 窗口可以放在屏外 `(-4000,-4000)` + `ShowInTaskbar=$false`，照样能出像素。
   完整配方见 §6「GUI 真机渲染 + 重叠审计」。
   ~~（旧结论：WinForms 需交互式桌面，沙箱会杀掉窗口进程，像素截图不可行）~~
   另外，**页面构建逻辑可以无头真机执行**：取 `OptimizeGUI.ps1` 前 366 行 prelude → dot-source `lib/Optimize.Core.ps1` 与 `gui/pages/Xxx.ps1` →
   自建 `$script:Pages` 与本地 `New-Page` → 调 `Build-XxxPage`，即可真实 render 出完整控件树；
   按钮事件用反射 `$btn.GetType().GetMethod('OnClick', 'Instance,NonPublic,Public').Invoke($btn, [object[]][System.EventArgs]::Empty)` 触发，
   **不要用 `PerformClick()`**（它依赖已创建的窗口句柄，无窗口时静默不触发，会误判成「功能坏了」）。
   新增/改动 GUI 页面后务必这样跑一遍；跑这类 harness 必须**前台执行**，原因见第 22 条。
8. **Pester 测试陷阱**：`{ $x = ... } | Should -Not -Throw` 的脚本块在子作用域执行，内部赋值**不会**回写父作用域，`$x` 一直是 `$null`。需断言结果时**直接调用**函数再断言。
9. **Build-EXE 依赖 region 标记**：`OptimizeGUI.ps1` 中 `#region GUI-PAGE-LOADER` / `#endregion` 包裹页面 dot-source 加载段，编译时会被剥离（函数已内联）。**不要改名 / 删除这两个标记**。
10. **CompactOS 默认必须关闭**：默认值唯一来源是 `config/optimization.json` 的 `disk.compact_os_default`（`false`）。**不要把任何一端改回无条件 `Compact.exe /CompactOS:always`** —— 压缩耗时长且回滚要再跑一次 `Compact.exe /CompactOS:never`。有 AST 用例守着 CLI，改动会让测试失败。
11. **版本号只改 config**：`config/optimization.json` 的 `version` 是唯一真源，其余（GUI 占位、`Start.bat` 初值、Build-EXE 回退）只是兜底，运行时/构建时会被覆盖（见 `docs/DEVELOPMENT.md`）。

12. **`Import-Csv` 的编码必须与写入端一致**：`Backup-StartupItems` 用 `Export-Csv -Encoding UTF8`（PS 5.1 会带 BOM），
    而测试/调试若用 `Set-Content` 手写 CSV（默认 ANSI），`Import-Csv -Encoding UTF8` 会把中文「注册表」读成乱码，
    导致 `-eq '注册表'` 判定失败。因此 `Restore-StartupItems` 的注册表来源判定**不要依赖中文 `Source` 列**，
    改用 `Path -like '?*:\*'` 做形态判断（中文列只作启动文件夹的补充判断）。
13. **别把 WMI `Win32_StartupCommand` 的 `Location` 当路径用**：它的值是 `Startup` / `Common Startup` 这类位置串，
    不是文件系统路径。早期版本按它 `New-Item` 在仓库根建出了 `Startup/`、`Common Startup/` 垃圾目录。
    现在这类行在 `Restore-StartupItems` 里一律只登记「跳过: 与注册表/启动文件夹条目重复」。
14. **时间线要防「同秒多份备份」**：manifest 的时间只到秒，同一秒连续备份会撞序，
    因此 `Get-OptimizationTimeline` 用「时间 + 文件名」做次级排序键，保证顺序确定。
15. **Python 改文件别踩通用换行陷阱**：`io.open(path,'r',encoding='utf-8-sig')` 默认 universal newlines 会把 `\r\n` 归一成 `\n`，
    写回时若 `newline=""` 又不再加回 `\r\n`，整份 CRLF 文件会变 LF。务必读完 `split`、写前 `replace("\n","\r\n")`。
    另外 `git show x | Set-Content y -NoNewline` 会把全文件拼成一行——取单行内容用 `Where-Object` 过滤后再写。

16. **`Invoke-Profile` 必须带 `[CmdletBinding()]`**：无 `CmdletBinding` 的简单函数会把**未匹配的命名参数静默吞进 `$args`**——
    既不报错也不生效。本次就因 `webui/ps/16_profiles.ps1` 把 `-DryRun:$DryRun` 传给参数名为 `-WhatIf` 的
    `Invoke-Profile`，导致预演静默变成真跑。排查方法：写个最小复现（`function F { param([string]$Name,[switch]$WhatIf) ... }`
    后 `F -Name x -DryRun:$true`），确认开关全为 `$false` 且 `$args` 里出现 `-DryRun:` 即坐实。
17. **`[CmdletBinding()]` 要放在函数体内 `param(` 之前**，写在 `function` 外面是语法错误
    （`Unexpected attribute 'CmdletBinding'`）。PS 5.1 解析器只认函数内属性这一种形式。
18. **每次 exec/命令行的 PowerShell 是全新会话**：上一条命令里的 `$py`、`$code` 等变量下一条命令里取不到
    （取到的是 `$null`）。写临时脚本再执行时，「定义变量 + 使用变量」必须在同一条命令里完成，
    否则会写出 0 字节文件，然后静默跑出一个空脚本。
19. **调用 lib 函数前必须先 dot-source lib**：`webui/ps/02_clean.ps1` 曾把 `Get-CleanTargets -Web` 写在 `if (Test-Path $libPath) { . $libPath }` 之前，
    运行时 `Get-CleanTargets` 未定义、`$ErrorActionPreference='Stop'` 把它变成终止错误，
    而 `run_ps` 只会把 stdout/stderr 拼成 JSON，最终表现为 `/api/clean/scan` 返回 `ok:false` + “无效的 JSON”。
    固化顺序：dot-source → `Get-Command` 存在性校验（不足则输出 JSON 兜底）→ 再调用 lib 函数。
20. **`param()` 块不接受尾逗号**：`param([switch]$A, [switch]$B,)` 最后一个参数后的逗号会让 PS 5.1 解析器报
    「Missing expression after ','」，且错误行指向最后一项参数、极易误判成注释或中文的问题。
    给参数列表增补条目时，**新参数若不是最后一项就要带逗号，是最后一项则必须去掉逗号**。
    本仓库的静态卫生检查（tests 的 source hygiene Describe）会抓住它，改动参数块后先跑一遍 Pester。

21. **switch 参数名会遮蔽同名小写变量**：`param([switch]$Plan)` 一进脚本，所有 `$plan` 都变成强类型 `SwitchParameter`，
    `$plan = Get-OptimizePlan ...` 直接抛「Cannot convert PSCustomObject to SwitchParameter」，而错误栈只指向调用行，极难定位。
    **加 `-Xxx` switch 前先全文搜一遍 `$xxx`**；已中招的就地改名（本次 `Optimize.ps1` 的 `$plan` → `$planPreview`）。

22. **`Anchor = Bottom` + `Reposition-PageControls` 改宽度 = 每次 Resize 长高一点**（2026-10-03）：
    `Reposition-PageControls` 会把每个「靠左且宽度 ≥ 400」的控件宽度重设为 `$maxW`。WinForms 的锚定是在
    **Resize 事件**里按比例换算的，所以这次**宽度**变化会被折算成一次纵向缩放，`Bottom` 锚定的控件
    `Height` 就会逐次累加——`CleanListBox` 实测 830 → 1814 → 2552 px，最后盖住整个操作区。
    同理，`Right` 锚定的控件每轮也会因为「按比例换算」而漂移。
    **规则：凡是被 `Reposition-PageControls` 命中（`Left ≤ 30` 且 `Width ≥ 400`）的控件，锚定只用 `Top|Left`**；
    需要「撑满宽度」就让 `Reposition-PageControls` 去设 `Width`，不要靠 `Anchor`。

23. **沙箱中「分离启动」的 PowerShell 子进程里 `Microsoft.PowerShell.Security` 导入失败**：用 `Start-Process powershell ...`
    （后台 / 隐藏窗口）拉起的子进程导入该模块会报 TypeData 冲突（`System.Security.AccessControl.ObjectSecurity` 的
    `AuditToString` / `AccessToString` / `Sddl` 等成员「已存在」），于是 `Get-AuthenticodeSignature` 不可用 →
    `Get-FilePublisher` 静默返回空 → P4-1 的签名厂商否决（§3.14）整段失效，表现为「0 条已保护」，极易被误判成功能回归。
    前台直接 `powershell -File ...` 的子进程完全正常（实测签名 `Valid`、publisher 正确）。
    **结论：验证签名/证书相关行为必须前台执行，且断言要写死 vetoed 条数（本机为 4）**；失败方向是 fail-open
    （publisher 空 → 不否决 → 退回打分推荐），不会误禁系统组件，无需改代码兜底。

24. **PowerShell `[System.IO.File]::ReadAllLines` / `WriteAllText` 会悄悄改掉换行与 BOM**（2026-10-03）：
    `ReadAllLines` 拆行后**丢掉行尾符**，用默认 `-join` 拼回去会得到全 `LF` 文件；`WriteAllText` 用
    `new UTF8Encoding($true)` 才带 BOM、用 `$false` 则**剥掉 BOM**。改动 `*.ps1` 时如果走这条路，
    很容易「只改了一行，diff 却整文件重写」，更严重的会给 `*.ps1` 去掉 BOM，导致 PS 5.1 把中文当 ANSI 读 → 乱码。
     **规则**：改完一律用 `ReadAllBytes` + 手动去/补 BOM + `-replace "`r`n","`n" -replace "`n","`r`n"`
    归一，然后断言 `bareLF=0`；仓库内 `.gitignore` 等非 `*.ps1` 文件按其**原有**约定（该文件无 BOM）保存，别一律加 BOM。
    验证：`git diff` 不应出现「`-﻿# 编译产物` / `+# 编译产物`」这类 BOM 噪声，也不应出现整文件重写。

---

## 6. 如何验证改动

- **单元 / 契约测试**：`tests/Optimize.Core.Tests.ps1`（Pester）。运行：
  ```powershell
  cd <项目根>
  Invoke-Pester -Path ./tests/Optimize.Core.Tests.ps1
  ```
  当前 **226 个用例**（2026-09-28 实测 226 通过 / 0 失败，入口 `_runtests.ps1`；含各域「编号稳定 / 必须备份 / 行为契约」断言，其中 6 条是 CompactOS 契约用例、1 条用 Mock 覆盖「无活动网卡」分支）。新增 lib 函数时务必补对应用例。
- **只读 smoke**：直接 `& scripts/15-HealthCheck.ps1` 或 `& webui/ps/15_health.ps1` 看 JSON 输出；磁盘/网络等可用 `-WhatIf` 预演不改系统。
- **Profiles 四态回归**：`& webui/ps/16_profiles.ps1 -Action list|plan`、`-Action apply -Name minimal -DryRun`（断言 `dryRun:true`）、`-Action apply -Name gaming -DryRun`（断言 `startup` 进 `skipped`）、`-Action apply -Name gaming -DryRun -Force`（断言全步骤跑完、`skipped` 为空）、坏名字返回 `ok:$false`。
- **GUI 真机渲染 + 重叠审计**（2026-10-03 新增，改 GUI 布局/配色必跑）：
  写一个临时 harness，用 `[System.IO.File]::ReadAllLines(..., UTF8)` 读 `OptimizeGUI.ps1`，按标记切三段拼成一个临时脚本：
  `0 .. (if (-not (Test-Administrator)) 之前)` 的前导段（注意跳过顶层 `trap { }` 块）→ 补 `$script:ProjectRoot/ScriptsDir/BackupDir/LogFile`
  + dot-source `lib\Optimize.Core.ps1` → `$MainForm = New-Object ...` 起到 `Start-BackgroundUpdateCheck` 之前的主窗体 UI 段。
  dot-source 该临时脚本后：
  1. **像素渲染**：`StartPosition=Manual` + `Location=(-4000,-4000)` + `ShowInTaskbar=$false` → `$MainForm.Show()` →
     `DoEvents()` → 逐页设 `Visible` 并 `BringToFront()` → `$MainForm.DrawToBitmap($bmp, ...)` → 存 PNG。
  2. **重叠审计**：遍历每页 `$page.Controls` 顶层控件两两求交（`Max(Left)`/`Min(Right)`…），任何 `w>0 且 h>0` 即报重叠。
     跑 `900×640`（MinSize）`/1000×700/1024×720/1280×880/1400×1000/1600×900/1920×1080` 七档，**要求全 0**。
  3. **锚定回归**：对 `CleanListBox` 这类宽控件连续 `Resize`，断言 `Height` **不随帧增长**（见 §5.22）。
- **提交前自检**：确认改动 `*.ps1` 均带 BOM、语法 0 错误（见 §5.1 的解析校验）。

---

## 7. 待定决策 / 已知未完成

- ~~**CLI 的 CompactOS 默认无条件执行**~~ → **已于 2026-09-18 收口**（见 §3.3）：三端统一为「显式开关、默认关闭」，默认来源 `config` 的 `disk.compact_os_default`。
- **GUI 体检页 `gui/pages/Health.ps1`：2026-09-28 已做无头真机点验（§5.7 harness）**——真实构建控件树（18 个控件）并用反射触发「开始体检」
  跑完整链路（27.5 s，58/100「亟需优化」），22/22 断言通过：4 条「已保护」签名否决行、推荐项「签名:」字段、编号推荐无微软签名项泄漏、
  指标 16 行、一键修复预览 21 行、与上次对比文案正常、递归 59 个控件无 U+FFFD。
  剩余缺口（2026-10-03 更新）：~~窗口级像素渲染~~ 已解决（见 §3.15 / §6）；
  仅剩 `MessageBox` / `InputBox` 模态交互路径与 UIA 点击需在交互式桌面人工确认。
  **并已在 2026-10-03 完成全部 12 个页面的窗口级像素渲染并逐页肉眼核对（含本页 5 处布局撞车修复，见 §3.16）。**
- **GUI 首页 `gui/pages/Dashboard.ps1` 同批无头真机点验通过**：递归 41 个控件，含「优化组合包」卡片标题与「选择组合包」按钮；
  「选择组合包」点击后的 `InputBox` / `MessageBox` 交互路径仍需交互式桌面真机确认。
- ~~既有缺陷：`webui/ps/02_clean.ps1` 在 dot-source lib 之前就调用 `Get-CleanTargets -Web`，导致 `/api/clean/scan` 报命令未找到~~ → **已修复**（2026-09-24）：
  lib dot-source 提前到 `Get-CleanTargets` 之前，并按 `16_profiles.ps1` 的模式补了一个“未找到共享核心库”的 JSON 兜底（而不是把 PowerShell 报错当成 JSON）。
  回归：`/api/clean/scan` 返回 `ok:true` + 6 个清理项（含预估大小）。
- ~~PR #5 / #6 合并顺序与潜在冲突~~ → 已在本集成分支按 `#5 → #6` 顺序合并，**零冲突**；剩最后一步是你在 GitHub 点 Merge（见 §2）。

---

## 8. 建议的下一步

> ✅ **2026-09-25 收口**：PR #7 已合并（merge commit `bfc7b54`），远端残留分支已清理，`v3.3.0` 已发布 Release。

0. ✅ 合并前核对远端真实 HEAD：`git ls-remote origin refs/heads/main` 为 `bfc7b54`（PR #7 merge commit），Actions `validate` 为绿。
1. ✅ 合并 **PR [#7](https://github.com/cpufreestyle/win-optimizer/pull/7)**（`sync/v3.3.0-main` → `main`）；PR #5/#6 由 GitHub 自动关闭。
2. ✅ 清理远端残留分支：`feat/optimizations`、`fix/cli-error-isolation-version`、`perf/folder-size-and-logging`、`release/v3.1.0` 与集成分支均已删除，远端只剩 `main`。
3. ✅ 打 tag `v3.3.0`：Release workflow 成功，GitHub Release `v3.3.0` 已发布。
4. ✅（部分）真机验收 GUI 体检页（§7）与新增的「体检趋势」「智能建议」显示：2026-09-28 已用无头 harness + WebUI 后端 JSON 复核完成
   （WebUI SVG 趋势卡片 / 智能建议表格 / GUI 迷你图与建议面板 / CLI `-Trend`）；
~~仅剩窗口级像素渲染~~ 已于 2026-10-03 用无头 harness 完成（§3.15）；仅剩 `InputBox` / `MessageBox` 交互路径需在交互式桌面人工确认。
5. ✅ P1 系列全部发布（P1-1 见 §3.6，P1-2→v3.5.0，P1-3→v3.6.0）；
   ✅ P2 智能降级建议已实现（§3.9），待随 v3.7.0 发布。
6. Roadmap 功能项已全部收口：P0 / P1 / P2 均落地（P2 三项见 §3.9、§3.11、§3.12）。
   后续方向建议从社区反馈 / 新 Issue 里重新提炼（体体检报告的 bench 曲线已能为「要不要再优化」提供数据）。
   「一键优化组合包」（P0-3）、「优化回滚向导」（P0-4）、「定时体检 + 趋势报告」（P1-1）均已落地（见 §3.4、§3.5、§3.6）。
