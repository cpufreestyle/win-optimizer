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

**落点**：`scripts/15-HealthCheck.ps1` 增加 `[R]` 交互；GUI `gui/pages/Health.ps1` 每条 issue 后
加「修复」按钮；WebUI 加 `/api/health/remediate` + 前端按钮。`New-HealthIssue` 增加可选
`remediation` 字段（lib 内单点定义，三端零漂移）。

**风险**：中。必须带 `-WhatIf` 与确认；`High` 级一律不自动执行。建议首发只放开 Medium/Low。

---

## P0-3 优化组合包 Profiles（一键到位）

**痛点**：完整优化要依次点 5~6 个菜单（服务→启动项→视觉→电源→网络），中途易放弃；不同用户场景
（办公 / 游戏 / 省电）需要的取舍完全不同。

**方案**：`config/optimization.json` 新增 `profiles`（config 驱动，社区可直接贡献），每份聚合：

```
老机均衡:  services=safe,      startup=interactive, visual=best_performance, power=high,      dns=cloudflare, compact_os=false
游戏加速:  services=recommended,  startup=trim,      visual=best_performance, power=ultimate, dns=aliyun,     compact_os=false
静音省电:  services=recommended, startup=interactive, visual=balanced,        power=power_saver, dns=114,      compact_os=false
最小干预:  services=safe,       startup=none,        visual=balanced,        power=keep,      dns=none,       compact_os=false
```

lib 新增 `Get-Profiles` / `Get-ProfilePlan <name>` / `Invoke-Profile <name> [-WhatIf]`——
**纯编排现有域函数，不新增任何系统操作面**，天然获得全部备份与兼容性保障。

**落点**：CLI 新菜单项；GUI 首页/Dashboard 大按钮卡片；WebUI `/api/profile/apply` + 首页卡片。
执行时输出分域进度与失败续跑（复用 CLI 一键优化的错误隔离模式）。

**风险**：低-中。`ultimate`/`power_saver` 计划 GUID 需 Win7 适配（lib 的 `Invoke-PowerCfg` 已有兼容层，需确认失败回退）。

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

---

## P1-1 定时体检 + 趋势报告

`Save-HealthReport` / `Get-HealthHistory` 已落库历史 JSON，但从未被自动执行、也无人看趋势。

- CLI `scripts/15-HealthCheck.ps1 -InstallSchedule [-Time '09:00']`：注册 schtasks 每日任务（非管理员降级为登录时触发，仅警告）。
- lib 新增 `Get-HealthTrend [-Days 30]`：输出分数 / 可用内存% / 可清理MB / 启动项数序列。
- WebUI 趋势卡片用**内联 SVG 折线**（禁外链 CDN，目标机器可能离线）；CLI `-Trend` 用字符 sparkline；GUI 健康页加迷你趋势。

**风险**：低。只读 + 纯本地文件；定时任务注册失败必须静默容错（虚拟机/域控环境常见）。

## P1-2 前后对比报告导出（一键分享）

`Compare-HealthReports` 已存在但只能屏幕看。新增 `Export-HealthReport -From -To -Format Html|Markdown`：
输出**自包含单文件**（内联 CSS，无外部依赖）到桌面，含总分变化、逐指标对比表、新增/消失的 issue 清单。
用于求助发帖、优化前后效果证明。

## P1-3 优化前自动创建系统还原点

config 新增 `safety.create_restore_point`（默认 `false`，与 `disk.compact_os_default` 同思路）。
修改类操作前执行 `Checkpoint-Computer`，失败回退 WMI `SystemRestore`，再失败只警告不阻断。
老硬盘创建还原点较慢，默认关闭；GUI/WebUI 设置项同步。有 AST 契约用例兜底默认值。

---

## P2（探索性）

- **MCP `optimize_plan` dry-run 工具**：与 `health_scan` 并列，只返回「将做什么」不执行；
  CLI/GUI/WebUI 的预览层统一调用 lib 的 plan 对象，三端预览文案零漂移。
- **开机耗时基线**：体检报告加 `bench` 段（磁盘顺序读探测、启动项数、服务自动数），
  配合 P1-1 趋势图让「优化有没有变快」可量化。探测必须 <10s 且纯只读。
- **智能降级建议**：`memory.low` / `disk.space` 命中时，自动指出「最值得关的 3 个启动项 /
  最值得清的 3 个目录」（按体积/影响排序），而不是只给菜单编号。

---

## 建议实施顺序

1. P0-1（半天，先消灭现存漂移，可作为独立 PR）
2. P0-2（体检修复，lib 单点映射，测试友好）
3. P0-4（时间线/回滚，依赖 P0-1 引入的备份 manifest 规范）
4. P0-3（组合包，编排面最大）
5. P1-1 → P1-2 → P1-3
6. P2 按社区反馈取舍

每步都走「集成分支 + PR」流程（见 HANDOFF §2），PR 前确认：Pester 88+ 全绿、
`*.ps1` 全 BOM、`config/optimization.schema.json` 同步更新、GUI 改动真机点验。
