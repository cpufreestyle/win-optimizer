# 创新功能优化方案（Roadmap 草案）

> 提出日期：2026-09-23
> 基线：v3.3.0（`lib` 51 函数、三端共享核心、88 个 Pester 用例、MCP 工具齐备）
> 配套：`docs/DEVELOPMENT.md`（架构/配置/发布）、`docs/HANDOFF.md`（当前状态）

## 总原则

1. **逻辑一律先进 lib**（`lib/Optimize.Core.ps1`），三端只做渲染与交互 —— B1 五域下沉的经验必须延续。
2. **只读先行、修改必备份**：任何自动执行的功能先出「将做什么」清单，执行前自动调用对应域 `Backup-*`。
3. **Win7 兼容红线不破**：不引入 `Get-PhysicalDisk` / `Optimize-Volume` 等 Storage 模块 API；`*.ps1` 存 UTF-8 BOM；DNS 选项编号不得变更。
4. 新功能必须补 Pester 契约用例（编号稳定 / 必须备份 / 行为契约），保持 CI 绿。

---

## P0-1 遥测计划任务域下沉 lib，并补齐三端（修现存漂移）

**痛点（已实测确认）**：`Get-TelemetryTasks` 只被 CLI `scripts/03-DisableServices.ps1:118` 使用；
`Disable-ScheduledTaskCompat` 定义在 `OptimizeGUI.ps1:121`（GUI 私有），GUI 硬编码 4 条任务
（`gui/pages/Services.ps1:150`），比 config 的 5 条少 `DiskDiagnosticDataCollector`；
WebUI `webui/ps/03_services.ps1` 完全没有这个功能。这正是 B1 想消灭的「三端三套」。

**方案**：lib 新增 `Disable-TelemetryTasks [-WhatIf]`（内部统一 `Get-ScheduledTask` → 失败回退
`schtasks /Change /Disable`，把 GUI 的 compat 逻辑吸收进来）；三端改为调用同一函数，config 为唯一任务清单来源。

**落点**：`lib/Optimize.Core.ps1` 新增函数；`OptimizeGUI.ps1` 删除私有 compat 函数（注意保留
`#region GUI-PAGE-LOADER` 标记）；`gui/pages/Services.ps1` 改调用；`webui/ps/03_services.ps1`
补勾选项与 `/api/services/apply` 参数透传；Pester 补 Win7 compat 分支与 `-WhatIf` 断言。

**风险**：低。纯编排已有能力，无新系统操作面；Win7 用 `schtasks` 路径需在测试中 Mock 覆盖。

---

## P0-2 体检自动修复（Auto-Remediation）

**痛点**：`Get-SystemHealthReport` 已产出结构化 issue（`code`/`severity`/`advice`），
但只能「告诉用户该去点哪个菜单」，老电脑用户面对 15 个菜单依然无从下手。

**方案**：lib 新增
- `Get-HealthRemediationPlan [-Report <report>]`：把 issue code 映射为「具体动作 + 目标域 + 预估影响」，纯只读，可预览；
- `Invoke-HealthRemediation [-IssueCode] [-MaxSeverity] [-WhatIf] [-Force]`：按 plan 逐个调用**已存在的**域函数，每步前自动 `Backup-*`。

映射表（初版）：

| issue code | 动作 | 自动执行？ |
|---|---|---|
| `services.auto` | `Disable-Services`（safe + recommended，已备份） | 是 |
| `startup.many` | 仅列出清单，交互禁用 | 否（避免误杀） |
| `visual.effects` | `Set-VisualEffectProfile -Profile '最佳性能'` | 是 |
| `power.balanced` | `Set-PowerPlan`（默认高性能，可用 `-Plan` 指定） | 是 |
| `disk.cleanable` | 清理 config 中 `web: true` 且非敏感目标 | 是 |
| `network.dns.*` | `Invoke-NetworkOptimization`（默认 Cloudflare，可参数指定） | 是 |
| `memory.low` / `disk.space` | 仅给建议，不自动动作 | 否 |

实际落地与上表的偏差：`services.auto` 走 `Disable-Services -Mode all`（safe + recommended 全量，已备份）；
`network.dns.*` 多个网卡合并为一次 `Invoke-NetworkOptimization`，避免重复备份与重复改 DNS。

**落点**：`scripts/15-HealthCheck.ps1` 增加 `[R]` 交互；GUI `gui/pages/Health.ps1` 每条 issue 后
加「修复」按钮；WebUI 加 `/api/health/remediate` + 前端按钮。`New-HealthIssue` 增加可选
`remediation` 字段（lib 内单点定义，三端零漂移）。

**风险**：中。必须带 `-WhatIf` 与确认；`High` 级一律不自动执行。建议首发只放开 Medium/Low。

已实现：默认 `-MaxSeverity Medium`（即放开 Medium/Low）；`High` 级需 `-MaxSeverity High` + `-Force`；
`-WhatIf` 零副作用（连备份都不落盘，与 `Disable-TelemetryTasks` 对齐）。

---

## P0-3 优化组合包 Profiles（一键到位）—— 已实现

**痛点**：完整优化要依次点 5~6 个菜单（服务→启动项→视觉→电源→网络），中途易放弃；不同用户场景
（办公 / 游戏 / 省电）需要的取舍完全不同。

**方案**：`config/optimization.json` 新增 `profiles`（config 驱动，社区可直接贡献），每份聚合：

```
老机均衡:  services=safe,      startup=interactive, visual=best_performance, power=high,      dns=cloudflare, compact_os=false
游戏加速:  services=recommended,  startup=trim,      visual=best_performance, power=ultimate, dns=aliyun,     compact_os=false
静音省电:  services=recommended, startup=interactive, visual=balanced,        power=power_saver, dns=114,      compact_os=false
最小干预:  services=safe,       startup=none,        visual=balanced,        power=keep,      dns=none,       compact_os=false
```

lib 新增 `Get-Profiles` / `Get-ProfilePlan <name>` / `Invoke-Profile <name> [-WhatIf] [-Force]`——
**纯编排现有域函数，不新增任何系统操作面**，天然获得全部备份与兼容性保障。

**落点（三端均已落地）**：
- CLI：`scripts/16-Profiles.ps1`，`Optimize.ps1` 菜单 `[16]`（列表 → 只读预览 → `[1]` 预演 / `[2]` 确认执行）。
- GUI：`gui/pages/Dashboard.ps1` 新增「优化组合包 Profiles」卡片（选中编号 → 预览 → 确认执行）。
- WebUI：`webui/ps/16_profiles.ps1` + `/api/profile/list|plan|apply` + MCP `profile_list`/`profile_plan`/`profile_apply`，
  前端 `renderProfiles()` 组合包卡片 + 预览表格 + 预演/执行。
执行时输出分域进度与失败续跑（单步失败不中断，结束汇总 success/failed/skipped）。

**风险闸门**：`Get-ProfileSteps` 为每步派生 `risk`（low/medium/high）与 `auto`。默认只跑 `auto` 且非
`high` 的步骤；`auto=false` 或 `risk=high` 的步骤必须显式 `-Force` 才执行。内置 `config` 中
`auto=false` 与 `risk=high` 完全等价（仅 `startup=all` 的「禁用全部启动项」与 `disk` 磁盘优化两处），
因此 `-Force` 是唯一的高危开关，三端入口一致。

**与原方案的偏差**
- `startup` 字段取值从 `interactive`/`trim` 改为 `list`（只读列出启动项清单）与 `all`（禁用全部）：
  「交互式逐项决定」在 CLI/GUI/WebUI 三端都需要一套额外的勾选 UI，收益低于复杂度，
  故首版用「只读清单 + 高危爆破」两档，取消逐项交互。
- 磁盘优化的 `compact_os` 在 lib 内部扁平化为 `compactOs`（`Get-Profiles` 统一输出该字段），
  config 仍以 `profiles.<name>.compact_os` 书写；`disk`/`compact_os` 未在本轮内置组合包里启用
  （`minimal` 等四个都是 `disk=none`），磁盘优化仍由 07-DiskOptimize / WebUI 磁盘页按需触发。
- `dns` 字段直接复用 08-NetworkOptimize 的 DNS 选项编号（1=Cloudflare 2=Google 3=阿里 4=114），
  不新增枚举；未知 DNS/visual/power 值对应步骤直接不生成，而不是报错中断整包。
- `services=recommended` 定为 medium（可自动执行），`services=safe` 定为 low；`dns`/`visual`/`telemetry` 定为 low。
- `power_saver` 的 GUID 为 `a1841308-3541-4fab-bc81-f71556f20b4a`，`ultimate` 沿用
  `e9a42b02-d5df-448d-aa00-03f14749eb61`；裸 GUID 直接透传，失败由 `Set-PowerPlan` 的既有回退兜底。

---

## P0-4 优化时间线 + 一键回滚向导

**痛点**：每域各自备份到 `backups/`，恢复要逐域翻菜单；用户不知道「上周到底改了什么」，
想整体退回某个时间点只能手工逐域操作。

**方案**：
1. 每次 `Backup-*` 同时写 `manifest.json`（域、时间、条目数、版本、主机）到该次备份目录；
2. lib 新增 `Get-OptimizationTimeline`（聚合所有 manifest，按时间倒序）；
3. `Invoke-Rollback [-Since <datetime> | -Last <n>] [-DryRun] [-Force]`：按域调用已有
   `Restore-Services` / 启动项还原 / `Set-VisualEffectProfile` 还原 / `Set-PowerPlan` 还原 /
   `Set-AdapterDns` 还原，**回滚前先把当前状态备份一遍**（支持「再反悔」）。

**落点**：`scripts/09-BackupRestore.ps1` 增强为时间线视图；GUI `gui/pages/Backup.ps1` 加时间线
列表 + 单选回滚；WebUI `/api/backup/timeline` + 按范围恢复。旧备份无 manifest 时按目录名容错解析并标注「元数据缺失」。

**风险**：中。跨域回滚顺序需固定（服务→启动项→视觉→电源→网络→磁盘），任一步失败要可续跑。

**已实现（2026-09-24）**：

| 层 | 落点 |
|----|------|
| lib | `Write-BackupManifest`（6 个 `Backup-*` 全部写 `<备份文件>.manifest.json`：域/时间/条目数/字节/主机/版本）、`Get-BackupDomainFromName`、`Get-BackupDomainLabel`、`New-BackupTimelineEntry`、`Get-OptimizationTimeline`、`Get-RollbackPlan`、`Backup-DomainState`（后悔药）、`Restore-DomainState`（按域分发）、`Format-RestoreDetails`、`Invoke-Rollback` |
| CLI | `scripts/09-BackupRestore.ps1` 重写为时间线视图 + `[A]` 全量恢复 / `[Z]` 一键回滚向导 / 编号单条恢复 |
| GUI | `gui/pages/Backup.ps1` 时间线表格 + 「一键回滚向导」 + 「恢复选中备份」 |
| WebUI | `webui/ps/09_backup.ps1` 增加 `-Action timeline|create|restore|rollback`；路由 `/api/backup/timeline`、`/api/backup/rollback`；MCP 工具 `backup_timeline` / `backup_rollback`；前端 `renderBackup()` 渲染时间线表格与回滚预览 |

与原方案的偏差（均已按可行性调整）：

1. **电源计划备份改结构化 JSON**：原方案的 `.txt`（`powercfg /list` 文本）无法可靠解析出活动 GUID，
   改为 `.json`（`activeGuid` / `activeName` / `query`），还原时 `powercfg /setactive` 后回读校验；
   解析不了的旧 `.txt` 只给手动提示，不猜。
2. **更新域回滚用 `Restore-UpdateBackup`**（`reg import` + `Restore-AutoUpdate`），不再走域开关。
3. **回滚固定顺序**：服务 → 启动项 → 视觉 → 电源 → 网络 → 遥测 → 更新（原方案把磁盘列在末位，
   实际磁盘无备份，`health`/`unknown` 统一进 `skipped`）。
4. **`Restore-StartupItems` 跳过 WMI「系统启动命令」行**：这些行与注册表 / 启动文件夹条目重复，
   只登记不动作；注册表来源按 `Path` 形态（`?*:\*`）判定而非中文 `Source`，避免 CSV 编码差异导致误判。
5. **`-DryRun` 零副作用**：不进任何还原函数、不写任何备份，仅返回计划（与 `Invoke-HealthRemediation -WhatIf` 对齐）。
6. **manifest 缺失容错**：旧备份按文件名推断域、按文件时间排序，时间线标注「元数据缺失」。

安全约束（lib 强制，三端无法绕过）：回滚前 `Backup-DomainState` 先备份当前状态；该备份失败默认中止
（`-Force` 才继续）；时间线与 `Get-RollbackPlan` 全程只读。


---

## P1-1 定时体检 + 趋势报告 —— 已实现

`Save-HealthReport` / `Get-HealthHistory` 已落库历史 JSON，但从未被自动执行、也无人看趋势。

- CLI `scripts/15-HealthCheck.ps1 -InstallSchedule [-Time '09:00']`：注册 schtasks 每日任务（非管理员降级为登录时触发，仅警告）。
- lib 新增 `Get-HealthTrend [-Days 30]`：输出分数 / 可用内存% / 可清理MB / 启动项数序列。
- WebUI 趋势卡片用**内联 SVG 折线**（禁外链 CDN，目标机器可能离线）；CLI `-Trend` 用字符 sparkline；GUI 健康页加迷你趋势。

**风险**：低。只读 + 纯本地文件；定时任务注册失败必须静默容错（虚拟机/域控环境常见）。

**落点（三端均已落地，2026-09-25）**：
- lib：`Get-HealthTrend [-BackupDir] [-Days 30] [-MaxPoints 60]`（读 `backups/health/*.json`，输出 time/score/freeRamPct/cleanableMB/startupCount/issueCount 升序序列；超过 MaxPoints 均匀抽样且保留最新点）、`Format-Sparkline`（纯 ASCII 字符 sparkline，Win7 控制台等宽字体稳定显示）。
- 定时任务：`Test-IsAdmin` / `Install-HealthSchedule [-Time] [-HealthScript]` / `Remove-HealthSchedule`（schtasks，Win7~Win11 通用；非管理员降级 ONLOGON 并 warning 说明；校验/注册失败只返回 error 不抛异常）。
- CLI：`scripts/15-HealthCheck.ps1 -InstallSchedule [-Time 09:00]` / `-UninstallSchedule` / `-Trend [-TrendDays]`；每次体检后附带一行分数 sparkline；非交互环境（计划任务自动运行）自动跳过修复提问与注册提示。
- GUI：`gui/pages/Health.ps1` 关键指标区追加一行迷你 sparkline（数据源与 CLI/WebUI 完全一致）。
- WebUI：`-Action trend`（scan 响应附带 trend）、`/api/health/trend` 路由 + MCP `health_trend`；前端「体检趋势」卡片 = 内联 SVG 折线 + 面积 + 逐点 tooltip + 最近 10 次表格，**零外链依赖，离线可用**。
- 测试：`tests/Optimize.Core.Tests.ps1` 新增 5 个用例（sparkline 映射 / 趋势序列与 `-Days`、`-MaxPoints` 抽样 / 空历史 / 计划任务参数校验 / `Test-IsAdmin`），156/156 通过。

## P1-2 前后对比报告导出（一键分享） — 已实现

`Compare-HealthReports` 已存在但只能屏幕看。新增 `Export-HealthReport -From -To -Format Html|Markdown`：
输出**自包含单文件**（内联 CSS，无外部依赖）到桌面，含总分变化、逐指标对比表、新增/消失的 issue 清单。
用于求助发帖、优化前后效果证明。

**落点（P1-2，2026-09-25 实现）**
- lib：`lib/Optimize.Core.ps1` 新增 `Export-HealthReport -From -To -Format Html|Markdown [-BackupDir] [-OutDir] [-FileName]`。
  `-From/-To` 接受报告对象或 health JSON 路径，省略时自动取历史最新两份；输出默认落桌面（失败回退 `%USERPROFILE%`）。
  输出内部调用 `Compare-HealthReports`，由 `ConvertTo-HealthCompareHtml` / `ConvertTo-HealthCompareMarkdown` 渲染。
- **自包含**：HTML 全内联 CSS（含暗色模式）、零外部请求，所有文本经 `HtmlEncode` 转义；Markdown 为纯文本表格，可直接粘贴到求助帖。
- CLI：`scripts/15-HealthCheck.ps1 -Export [-Format Html|Markdown] [-From 路径] [-To 路径]`；交互环境下对比区后会询问是否导出。
- WebUI：`-Action export` + `POST /api/health/export` + MCP `health_export` + 健康页“导出对比报告”按钮和格式下拉。
- GUI：`gui/pages/Health.ps1` 新增“导出对比报告”按钮（HTML / Markdown 二选一，弹窗提示文件路径）。
- 测试：`tests/Optimize.Core.Tests.ps1` 新增 6 个用例（HTML 自包含断言 / Markdown 表格 / JSON 路径传参 / 自动取最新两份 / 缺报告安全失败 / HTML 转义），全量 162/162 通过。


## P1-3 优化前自动创建系统还原点 — 已实现

config 新增 `safety.create_restore_point`（默认 `false`，与 `disk.compact_os_default` 同思路）。
修改类操作前执行 `Checkpoint-Computer`，失败回退 WMI `SystemRestore`，再失败只警告不阻断。
老硬盘创建还原点较慢，默认关闭；GUI/WebUI 设置项同步。有 AST 契约用例兜底默认值。

**落点（P1-3，2026-09-26 实现）**
- lib：`Get-RestorePointDefault`（唯一默认来源：`config/optimization.json` 的 `safety.create_restore_point`，默认 `false`）、
  `Test-SystemRestoreEnabled`（只读注册表判断 SR 是否被禁用）、
  `New-SystemRestorePoint [-Description] [-WhatIf]`：先 `Checkpoint-Computer`（Win8+），失败退 WMI `SystemRestore.CreateRestorePoint`（Win7 可用）；
  非管理员 / SR 关闭 / 24h 节流均返回 `@{ok=$false; error}`
  而不弹异常。
- 接线：`Invoke-HealthRemediation` 与 `Invoke-Profile` 新增 `-CreateRestorePoint`，**懒创建**——真要动系统的第一步前才建，
  全部步骤被跳过时不默默硬建；`-WhatIf` 不建；结果对象新增 `restorePoint` 字段。
- 三端：CLI `15-HealthCheck.ps1 -RestorePoint` 与 `16-Profiles.ps1` 交互询问；
  GUI `gui/pages/Health.ps1` 复选框“执行前先建系统还原点”；
  WebUI `-CreateRestorePoint`（auto/true/false 三态字符串）+ 前端两处复选框，执行结果展示还原点状态。
- 测试：`tests/Optimize.Core.Tests.ps1` 新增 9 个用例（默认关闭 / config 存在 / schema 开放 safety / `-WhatIf` 预演 /
  不可用时不抛异常 / remediation 与 profile 结果对象 / 三端默认同源 / Win7 红线无 CIM API），全量 **171/171** 通过。

---

## P2（探索性）

- ~~**MCP `optimize_plan` dry-run 工具**~~：**已实现（2026-09-26）**。与 `health_scan` 并列，只返回
  「将做什么」不执行；CLI/GUI/WebUI/MCP 的预览层统一调用 lib 的 plan 对象，三端预览文案零漂移。落点：
  - lib：`New-OptimizePlanStep`、`Get-OptimizePlan`（覆盖 [2]清理/[3]服务/[4]启动项/[5]视觉/[6]电源/
    [7]磁盘/[8]网络/[10]遥测/[16]组合包；每步带 domain/title/menu/action/target/detail/impact/risk，
    附 low/medium/high 汇总）、`Format-OptimizePlan`（三端共用纯文本渲染）。
  - CLI：`Optimize.ps1 -Plan [-Profile <x>] [-SkipCleanScan]`，菜单新增 `[P] 优化预览（只读）`，
    位于管理员检查之前的分支——纯只读模式无需提权。
  - WebUI：`webui/ps/optimize_plan.ps1 -Action plan` + MCP `optimize_plan(profile, skip_clean_scan)`。
  - 测试：新增 6 个用例（步骤结构 / summary 计数一致 / 电源与 DNS 标签 / 组合包与未知组合包 /
    清理步可选 / 渲染契约），全量 **194/194** 通过。
- ~~**开机耗时基线**~~：**已实现（2026-09-26）**。体检报告新增 `bench` 段（磁盘顺序读/写、启动项数、
  自动服务数、物理内存、探测耗时），配合 P1-1 趋势图让「优化有没有变快」可量化。落点：
  - lib：`Get-SystemBench`（%TEMP% 64MB 块文件顺序写+读回即删，实测约 0.4-1s）、
    `Get-AutoOptimizableServices`（体检与基线共用，避免重复扫 CIM）；`Get-SystemHealthReport`
    新增 `-SkipBench`，bench 挂报告顶层属性（不进 metrics，不影响评分与对比）。
  - CLI：体检输出「性能基线」段；`-Trend` 新增磁盘读 sparkline。
  - GUI：健康页关键指标区追加三行基线数据。
  - WebUI：`15_health.ps1 -SkipBench` 参数；体检页关键指标表加「性能基线 / 开机负担」两行，
    趋势区新增磁盘读 SVG 折线（无历史 bench 数据的旧报告按 0 处理，不抛异常）。
  - 测试：新增 6 个用例（探测结果结构 / 复用传入计数 / 实扫计数 / 报告挂载 / -SkipBench /
    旧报告趋势兼容），全量 **200/200** 通过。
- ~~**智能降级建议**~~：**已实现（2026-09-26）**。`memory.low` / `startup.many` 命中时给出
  「最值得关的 3 个启动项」（僵尸项 > 更新程序 > 云同步 > 后台助手，系统/硬件组件一律不推荐），
  `disk.space` / `disk.cleanable` 命中时给出「最值得清的 3 个目录」并按可释放体积排序，
  不再只给菜单编号。落点：
  - lib：`Get-StartupRiskScore`（纯函数打分，含 essential 黑名单与 RunOnce 降权）、
    `Get-StartupTargetPath`（解析引号/参数/环境变量，判僵尸项）、
    `Get-SmartRecommendations`（报告门控 + 复用已量好的体积，不重复扫盘）、
    `Format-SmartRecommendations`（三端共用渲染）。
  - CLI：`scripts/15-HealthCheck.ps1` 体检结果后新增「智能建议」段。
  - GUI：`gui/pages/Health.ps1` 新增「智能建议」面板（自动滚动区内）。
  - WebUI：`webui/ps/15_health.ps1 -Action tips` + `GET /api/health/tips` +
    MCP `health_tips`，体检页「智能建议」表格。
  - 测试：`tests/Optimize.Core.Tests.ps1` 新增 12 个用例（打分 / 门控 / Top / 排序 / 复用测量 / 渲染），
    全量 **188/188** 通过。

---

---

## P3（v3.9 增量）—— 已实现（2026-09-26）

> 主题：把「智能建议」补成闭环（实用性），顺手修两个准确性/安全缺口。
> 延续总原则：逻辑一律先进 lib，三端只做渲染；只读先行、修改必备份；Win7 红线不破；Pester 契约兜底。

### P3-1 智能建议一键应用（闭环）

**痛点**：P2 的智能建议只能看不能点——用户知道「该关 QianwenUpdater」，还要自己去菜单 [4] 翻编号。

**方案**：lib 新增 `Invoke-SmartRecommendations [-Report] [-Top 3] [-BackupDir] [-WhatIf] [-CreateRestorePoint]`：
- 只应用启动项类建议；**清理类不自动执行**（删文件不可逆性强，保留菜单 [2] 手动确认）。
- 执行前一次 `Backup-StartupItems` 覆盖全部选中项；备份失败即中止，不动系统。
- `-CreateRestorePoint` 懒创建（真要动系统的第一步前才建，与 `Invoke-HealthRemediation` 一致）。
- `-WhatIf` 零副作用（不备份、不建还原点、不改系统）。
- 执行前按 Name+Value 重新匹配实时启动项，匹配不到就跳过——宁可不做，也不误删。
- 返回 `@{ ok; whatIf; applied; failed; backup; restorePoint; error }`，`failed` 带每项原因
  （如 WMI 来源的「需通过任务管理器手动禁用」）。

**三端落点**：CLI `15-HealthCheck.ps1` 智能建议段后交互应用（先检查管理员/SR 开关）；
GUI `gui/pages/Health.ps1`「应用智能建议」按钮（复用还原点复选框，完成后自动重新体检）；
WebUI `-Action apply-tips` + `POST /api/health/apply-tips` + MCP `health_apply_tips` + 体检页按钮与还原点勾选。

### P3-2 服务依赖护栏（准确性 / 安全）

**痛点**：`Disable-Services` 只看服务自身状态；若某服务正被运行中服务依赖，禁用它会连带故障
（表现为「另一个功能莫名其妙挂了」）。

**方案**：lib 新增 `Get-ServiceDependents`（WMI `Win32_DependentService`，Win7 兼容，不用 CIM）；
`Disable-Services` 新增 `-Force`：默认跳过「有运行中依赖者」的服务并在 details 写明
`跳过: 正被 X, Y 依赖`，`-Force` 才强制执行。WMI 查询失败按空处理，不阻碍原有流程。
CLI `03-DisableServices.ps1` / GUI 服务页顺手把备份+禁用统一下沉 lib（获得 manifest 备份与护栏）。

### P3-3 真实开机耗时（准确性）

**痛点**：bench 原来只能数启动项/服务数，是「负担代理指标」；「到底开机几秒」没有真实数据。

**方案**：lib 新增 `Get-BootPerformanceSample`：解析 `Diagnostics-Performance` Event 100
（Win8+ 走 `Microsoft-Windows-Diagnostics-Performance/Operational`，Win7 回退经典日志），
从消息里用正则提取毫秒并做 0/超1小时异常值过滤；bench 新增
`bootSeconds / bootAt / bootSource / bootError`，`Get-HealthTrend` 同步带出（旧报告按 null 兼容）。
拿不到事件的机器按「无数据」处理，绝不影响体检主流程——这是尽力而为的增强指标。
## P4（准确性 / 留存，v3.10）

### P4-1 启动项建议的「签名厂商否决」—— 已实现（2026-09-26）

**痛点**：智能建议的名字黑名单（`Get-StartupRiskScore`）是按文件名 / 路径关键词匹配的，
管不住改名、换目录、伪装名的系统组件与驱动——一旦漏掉，用户禁掉 ` SecurityHealthSystray `
改名后的项，轻则功能失效，重则开机异常。「一键应用」（P3-1）把误关的代价从「读一遍」变成了「点一下」，
准确性护栏必须同步加厚。

**方案**：lib 新增 `Get-FilePublisher`（Get-AuthenticodeSignature 取签名证书 CN，PS2 可用，
任何失败返回空串）+ `Test-TrustedPublisher` / `Get-TrustedPublisherPatterns`
（受保护厂商特征走 `config/optimization.json` 的 `smart.trusted_publishers`，子串匹配，缺失回退内置默认）。
`Get-SmartRecommendations` 在启动项打分前加一道否决：目标文件存在且签名命中受保护厂商 →
不进推荐，并记入返回值的 `vetoed`（name/command/path/publisher/reason）。
`Format-SmartRecommendations` 统一渲染「已保护」清单，CLI / GUI 零改动即可展示；
WebUI `-Action tips` 带出 `vetoed`，前端在建议表下方列出被保护的项与原因。

**边界**：
- 「未知」不等于「信任」：未签名 / 取不到签名的项不否决，仍按既有打分规则参与推荐（虚警率不降）。
- 否决只作用于「智能建议」链路（含 P3-1 的一键应用）；菜单 [4] 手动禁用启动项不受影响，
  高级用户仍可自行决定。
- 取签名是本地只读操作，无网络；对每个候选启动项最多一次调用，失败静默降级。

**三端落点**：CLI / GUI 经 `Format-SmartRecommendations` 自动展示；WebUI `-Action tips` 新增
`vetoed` 字段 + `index.html` 建议区展示，`/api/health/scan` 的 `tips` 内嵌对象同步生效。

## 建议实施顺序

1. P0-1（半天，先消灭现存漂移，可作为独立 PR）
2. P0-2（体检修复，lib 单点映射，测试友好）
3. P0-4（时间线/回滚，依赖 P0-1 引入的备份 manifest 规范）
4. P0-3（组合包，编排面最大）
5. P1-1、P1-2、P1-3（已实现）
6. ✅ P2 三项全部落地：智能降级建议、MCP `optimize_plan` dry-run、开机耗时基线 bench（细则见上）。

每步都走「集成分支 + PR」流程（见 HANDOFF §2），PR 前确认：Pester 151+ 全绿、
`*.ps1` 全 BOM、`config/optimization.schema.json` 同步更新、GUI 改动真机点验。
