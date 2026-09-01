# 开发指南 (PC-Optimizer 7th Gen)

本文档面向贡献者，说明项目架构与常见开发任务的操作步骤。

## 架构概览

项目由三套前端共享同一份**核心逻辑库**，避免重复实现与功能漂移：

| 入口 | 文件 | 说明 |
|------|------|------|
| 命令行 | `Optimize.ps1` | 交互式 CLI |
| Web UI | `webui/` (Python + `webui/ps/*.ps1`) | 浏览器界面，后端调用 PowerShell |
| 图形界面 | `OptimizeGUI.ps1` → 编译为 `PC-Optimizer.exe` | WinForms 单体 EXE |

**共享核心逻辑**：`lib/Optimize.Core.ps1`
- 纯函数集合，不依赖任何 UI（无 WinForms / 无 Web）
- 返回结构化数据（哈希表 / 对象），由前端负责展示
- 通过 `config/optimization.json` 驱动，而非硬编码

**GUI 页面拆分**：`gui/pages/*.ps1`
- 每个 `Build-XxxPage` 函数为独立文件
- 主窗体 `OptimizeGUI.ps1` 用 dot-source 加载（开发模式），编译时由 `Build-EXE.ps1` 拼接进 EXE（编译模式）
- 更新检查逻辑在 `gui/UpdateCheck.ps1`

## 配置驱动

服务列表、遥测任务、DNS 选项等数据集中在 `config/optimization.json`：

```json
{
  "version": "3.0.0",
  "services": {
    "safe_to_disable":       [ { "name": "...", "desc": "..." } ],
    "recommended_to_disable":[ { "name": "...", "desc": "..." } ]
  },
  "telemetry_tasks": [ "\\Microsoft\\Windows\\..." ],
  "dns_options": [ { "name": "...", "primary": "...", "secondary": "..." } ],
  "update_repo": "owner/repo"
}
```

修改配置即可影响三套前端，无需改代码。

## 如何新增一个 GUI 页面

1. 在 `gui/pages/` 下新建 `<Name>.ps1`，定义 `function Build-<Name>Page { ... }`。
   函数内通过 `$script:Pages["<Key>"]` 获取页面容器，向其 `Controls` 添加控件。
2. 在 `OptimizeGUI.ps1` 主窗体区域，注册页面实例（参考已有页面）：

   ```powershell
   $pageX = New-Page "<Key>"
   $script:Pages["<Key>"] = $pageX
   ```

3. 在 `OptimizeGUI.ps1` 的加载器数组 `$pageLoader` 中加入 `"gui/pages/<Name>.ps1"`。
4. 在侧边栏添加对应的切换按钮（搜索 `New-SideButton`）。
5. 重新编译 EXE 验证：`.\Build-EXE.ps1`

> 编译流程会自动拼接 `lib + gui/pages/* + gui/UpdateCheck.ps1 + 主窗体`，无需手动维护拼接顺序。

## 如何新增一个可禁用服务

只需编辑 `config/optimization.json` 的 `services` 数组，将服务加入 `safe_to_disable` 或 `recommended_to_disable`。
三套前端会自动读取，无需改动任何 PowerShell 代码。

## 版本号与发布

版本号分散在 4 处，**必须保持一致**：

| 位置 | 字段 |
|------|------|
| `config/optimization.json` | `"version"` |
| `OptimizeGUI.ps1` | `$script:Version` |
| `Optimize.ps1` | `$script:Version` |
| `Build-EXE.ps1` | `Invoke-ps2exe -version`（四段式，如 `3.0.0.0`） |

`Build-EXE.ps1` 在编译前会**自动校验**四者版本一致，不一致则中止并报错。

### 发布流程

1. 统一版本号（见上表）
2. 重新编译：`.\Build-EXE.ps1`
3. 更新 `README.md` 更新日志
4. 提交并打 tag：`git tag -a vX.Y.Z -m "..."`
5. 推送 tag 触发 GitHub Actions 自动编译并创建 Release（见 `.github/workflows/release.yml`）；
   或本地运行 `tools/publish-release.bat` 手动发布。

## Git 同步与远程配置

本仓库的远程 `origin` 使用 **SSH 协议**：

```
git@github.com:cpufreestyle/win-optimizer.git
```

**为什么用 SSH**：部分网络环境下直连 `https://github.com/...` 会被重置，表现为：

```
fatal: unable to access 'https://github.com/...': Recv failure: Connection was reset
```

此时 `fetch` / `pull` / `push` 会全部失败；改用 SSH（22 端口）即可正常连通。

### 验证 SSH 连通性

```powershell
ssh -T git@github.com
# 成功返回：Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

若本机尚未配置 SSH key：用 `ssh-keygen -t ed25519` 生成，把公钥 `~/.ssh/id_ed25519.pub` 添加到 GitHub 账户，
并确保 `ssh-agent` 已启动且加载了私钥（`ssh-add ~/.ssh/id_ed25519`）。

### 从 HTTPS 切换为 SSH

```powershell
git remote set-url origin git@github.com:cpufreestyle/win-optimizer.git
git remote -v   # 确认已生效（应显示 git@github.com:... 而非 https://...）
```

### 日常同步流程

```powershell
git add <files>
git commit -m "提交说明"
git pull --rebase origin main   # 先拉取并 rebase，避免产生多余的 merge 提交
git push origin main
```

> 注意：工作区存在未提交改动时 `pull` 会失败，需先 `commit` 或 `git stash`。

## 编码约定

- 源文件统一使用 **UTF-8 with BOM**（避免 ps2exe 按 ANSI 读取导致中文乱码）
- 中文注释与界面文案保持原样，编译时 `Build-EXE.ps1` 会转 UTF-16 LE 处理
- 函数优先返回结构化数据，UI 渲染与业务逻辑分离
- **含中文的 Git 提交信息**：建议用 `git commit -F <file>` 从 UTF-8 文件读取提交说明。
  直接使用 `git commit -m '中文说明'` 在部分终端（如 Windows PowerShell）下会因编码转换损坏
  导致单引号被吞、命令解析失败（报错 `字符串缺少终止符: '`）。示例：

  ```powershell
  # 1) 用 UTF-8 编码写好提交说明文件（如 commit-msg.txt）
  # 2) 提交并推送
  git commit -F commit-msg.txt
  git push origin main
  ```
