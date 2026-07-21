# 发布指南（Release 发布）

本文件说明如何把本地改动推送到 GitHub 并创建 Release。所有面向 Release 的文件均已去除 UTF-8 BOM，Release 页面不会显示乱码。

## 前置：推送本地提交

仓库远程为 **HTTPS**，推送需使用 **Personal Access Token（PAT）**：

```powershell
cd d:\workspace\win-optimizer
git push origin main
```

- 弹窗中 **用户名填 GitHub 邮箱、密码填 Personal Access Token**；
- PAT 在 GitHub → Settings → Developer settings → Personal access tokens 生成，需勾选 `repo` 权限；
- GitHub 已停用账户密码登录 Git，无法用登录密码 push。

生成 PAT 后，可用以下命令缓存凭据，避免重复输入：

```powershell
git config --global credential.helper manager
```

## 方案 A：GitHub 网页发布（推荐，零依赖）

1. 浏览器打开 https://github.com/cpufreestyle/win-optimizer/releases/new
2. **Choose a tag** 填 `v2.1.2`（如已有同名 Release 则先删除或换版本号）
3. **Release title** 填 `v2.1.2 一键优化与 Release 乱码修复`
4. 说明框粘贴本仓库 `RELEASE_NOTES.md` 的内容
5. 点击 **Publish release**

## 方案 B：使用 GitHub CLI（`gh`）

### 1. 安装 gh

任选一种（需在本机带 GUI / 浏览器的终端执行）：

```powershell
# 方式一：winget（Win11 自带）
winget install --id GitHub.cli

# 方式二：scoop
scoop install gh

# 方式三：chocolatey
choco install gh

# 方式四：便携版（无包管理器时）
$ProgressPreference='SilentlyContinue'
$zip="$env:TEMP\gh.zip"; $dest="$HOME\gh-cli"
Invoke-WebRequest "https://github.com/cli/cli/releases/download/v2.96.0/gh_2.96.0_windows_amd64.zip" -OutFile $zip -UseBasicParsing
Expand-Archive $zip $dest -Force
$gh=(Get-ChildItem $dest -Recurse -Filter gh.exe).FullName
$env:Path=(Split-Path $gh)+";"+$env:Path
# 永久生效（重开终端后）：
[Environment]::SetEnvironmentVariable("Path", "$HOME\gh-cli;" + [Environment]::GetEnvironmentVariable("Path","User"), "User")
```

### 2. 登录 gh（需浏览器，交互式）

```powershell
gh auth login
```

按提示用 GitHub 账号 `cpufreestyle` 完成浏览器 OAuth 授权（本步骤无法在非交互环境完成）。

### 3. 创建 Release

```powershell
cd d:\workspace\win-optimizer
gh release create v2.1.2 `
  --title "v2.1.2 一键优化与 Release 乱码修复" `
  --notes-file RELEASE_NOTES.md
```

该命令会自动把 `v2.1.2` 这个 tag 推上远程，无需单独 `git push --tags`。

## 版本号说明

- 当前示例版本为 `v2.1.2`，请按实际发布内容调整（如 `v2.2.0`）；
- 若远程已存在同名 tag 的 Release，需先 `gh release delete v2.1.2` 或改用新版本号；
- Release 说明以仓库根目录 `RELEASE_NOTES.md` 为准，更新时同步修改该文件。
