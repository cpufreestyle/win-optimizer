"""
PC-Optimizer-7thGen WebUI 后端
本地运行，不联网。通过 subprocess 调用 webui/ps/ 下的 PowerShell 脚本（管理员权限）。
"""
import os
import sys
import json
import subprocess
import webbrowser
from flask import Flask, render_template, jsonify, request, send_from_directory

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PS_DIR = os.path.join(BASE_DIR, "ps")
TEMPLATES = os.path.join(BASE_DIR, "templates")
STATIC = os.path.join(BASE_DIR, "static")

app = Flask(__name__, template_folder=TEMPLATES, static_folder=STATIC)


# ============================================================
#  MCP (Model Context Protocol) 支持 — WebMCP
# ============================================================
# 将现有 webui/ps/*.ps1 暴露为 MCP 工具（SSE 端点 5001），
# 让 Claude Desktop / Cursor / Cline 等 AI 客户端能直接调用优化功能。
# 缺 mcp 库时静默跳过，WebUI 仍可正常使用。
MCP_AVAILABLE = False
mcp = None
try:
    from mcp.server.fastmcp import FastMCP  # type: ignore
    MCP_AVAILABLE = True
except Exception:
    MCP_AVAILABLE = False


def _register_mcp_tools(server):
    """把所有 run_ps 功能注册为 MCP tools（复用现有 PS 脚本）"""

    @server.tool()
    def overview() -> dict:
        """获取系统概览（CPU/内存/磁盘/系统/运行时间等）。"""
        return run_ps("01_system_info.ps1")

    @server.tool()
    def clean_scan() -> dict:
        """扫描可清理的垃圾文件并返回大小估算。"""
        return run_ps("02_clean.ps1", "-Action", "scan")

    @server.tool()
    def clean(items: str = "all") -> dict:
        """清理垃圾文件。items: 'all' 或逗号分隔的 key（temp/usertemp/prefetch/wsus/thumb/wer）。"""
        return run_ps("02_clean.ps1", "-Action", "clean", "-Items", str(items))

    @server.tool()
    def services_list() -> dict:
        """列出可优化的服务项。"""
        return run_ps("03_services.ps1", "-Action", "list")

    @server.tool()
    def services_apply(mode: str = "safe") -> dict:
        """应用服务优化。mode: 'safe' 安全禁用 / 'all' 全部禁用。"""
        return run_ps("03_services.ps1", "-Action", "apply", "-Mode", str(mode))

    @server.tool()
    def services_restore() -> dict:
        """恢复服务到原始状态（从备份）。"""
        return run_ps("03_services.ps1", "-Action", "restore")

    @server.tool()
    def startup_list() -> dict:
        """列出开机启动项。"""
        return run_ps("04_startup.ps1", "-Action", "list")

    @server.tool()
    def startup_disable(items: str = "all") -> dict:
        """禁用启动项。items: 'all' 或逗号分隔 key。"""
        return run_ps("04_startup.ps1", "-Action", "disable", "-Items", str(items))

    @server.tool()
    def visual_list() -> dict:
        """列出视觉效果模式（最佳性能/平衡/自定义）及当前设置。"""
        return run_ps("05_visual.ps1", "-Action", "list")

    @server.tool()
    def visual_apply(value: int = 1) -> dict:
        """应用视觉效果模式。value: 1=最佳性能 / 2=平衡 / 3=自定义。"""
        return run_ps("05_visual.ps1", "-Action", "apply", "-Value", str(int(value)))

    @server.tool()
    def power_list() -> dict:
        """列出电源计划（高性能/卓越性能/平衡/节能）及当前计划。"""
        return run_ps("06_power.ps1", "-Action", "list")

    @server.tool()
    def power_apply(value: int = 1, usb: bool = True, pci: bool = True) -> dict:
        """应用电源计划。value: 1=高性能 / 2=卓越性能 / 3=平衡。"""
        return run_ps("06_power.ps1", "-Action", "apply", "-Value", str(int(value)),
                      "-Usb", str(usb).lower(), "-Pci", str(pci).lower())

    @server.tool()
    def disk_list() -> dict:
        """列出本机磁盘（类型/大小/文件系统）。"""
        return run_ps("07_disk.ps1", "-Action", "list")

    @server.tool()
    def disk_optimize(trim: bool = True, defrag: bool = True, winsxs: bool = True, compact: bool = False) -> dict:
        """执行磁盘优化。trim=TRIM(SSD), defrag=碎片整理(HDD), winsxs=WinSxS清理, compact=压缩OS。"""
        return run_ps("07_disk.ps1", "-Action", "optimize",
                      "-Trim", str(trim).lower(), "-Defrag", str(defrag).lower(),
                      "-WinSxS", str(winsxs).lower(), "-Compact", str(compact).lower())

    @server.tool()
    def network_list() -> dict:
        """列出网络适配器及当前 DNS。"""
        return run_ps("08_network.ps1", "-Action", "list")

    @server.tool()
    def network_apply(dns: int = 0, tcp: bool = True, rss: bool = True, rsc: bool = True, dnscache: bool = True) -> dict:
        """网络优化。dns: 0=自动 / 1=阿里 / 2=DNSPod / 3=114 / 4=Google / 5=Cloudflare。"""
        return run_ps("08_network.ps1", "-Action", "apply",
                      "-Dns", str(int(dns)), "-Tcp", str(tcp).lower(), "-Rss", str(rss).lower(),
                      "-Rsc", str(rsc).lower(), "-DnsCache", str(dnscache).lower())

    @server.tool()
    def backup_list() -> dict:
        """列出已存在的备份文件。"""
        return run_ps("09_backup.ps1", "-Action", "list")

    @server.tool()
    def backup_create() -> dict:
        """创建新的系统设置备份。"""
        return run_ps("09_backup.ps1", "-Action", "create")

    @server.tool()
    def backup_restore(file: str = "") -> dict:
        """恢复备份。file: 备份文件名（留空恢复最新）。"""
        if file:
            return run_ps("09_backup.ps1", "-Action", "restore", "-File", str(file))
        return run_ps("09_backup.ps1", "-Action", "restore")

    @server.tool()
    def update_block(action: str = "status") -> dict:
        """屏蔽 Windows 更新（如 24H2）。action: status / apply / restore。"""
        return run_ps("10_block_update.ps1", "-Action", str(action))

    @server.tool()
    def update_manual(action: str = "status") -> dict:
        """手动更新模式（不自动下载/安装/重启）。action: status / apply / restore。"""
        return run_ps("11_manual_mode.ps1", "-Action", str(action))

    @server.tool()
    def update_restore_auto() -> dict:
        """恢复 Windows 自动更新（撤销手动更新模式 / 更新屏蔽）。"""
        return run_ps("14_restore_autoupdate.ps1")

    @server.tool()
    def update_hide_list() -> dict:
        """列出可隐藏的更新。"""
        return run_ps("12_hide_updates.ps1", "-Action", "list")

    @server.tool()
    def update_hide(items: str = "all") -> dict:
        """隐藏指定更新。items: 'all' 或逗号分隔 key。"""
        return run_ps("12_hide_updates.ps1", "-Action", "hide", "-Items", str(items))

    @server.tool()
    def update_show(items: str = "all") -> dict:
        """恢复已隐藏的更新。items: 'all' 或逗号分隔 key。"""
        return run_ps("12_hide_updates.ps1", "-Action", "show", "-Items", str(items))

    @server.tool()
    def features_list() -> dict:
        """列出 Windows 可选功能。"""
        return run_ps("13_features.ps1", "-Action", "list")

    @server.tool()
    def features_enable(items: str = "all") -> dict:
        """启用 Windows 可选功能。items: 'all' 或逗号分隔 key。"""
        return run_ps("13_features.ps1", "-Action", "enable", "-Items", str(items))

    @server.tool()
    def launch_client(kind: str = "gui", admin: bool = True) -> dict:
        """启动 PC-Optimizer 客户端程序。

        kind:
          'gui' (默认) 启动桌面端 Windows Forms GUI (OptimizeGUI.ps1)
          'web'        启动 WebUI (浏览器访问 http://127.0.0.1:5000 并自动打开浏览器)
        admin: 是否以管理员身份启动 (GUI 的清理/服务等需管理员权限；默认 True，
               会触发 UAC 提权确认)。设为 False 则以当前权限直接启动。
        """
        import time
        try:
            root = os.path.dirname(BASE_DIR)  # 项目根目录
            if kind == "web":
                webui = BASE_DIR
                if not os.path.exists(os.path.join(webui, "app.py")):
                    return {"ok": False, "error": "找不到 webui/app.py"}
                subprocess.Popen(
                    [sys.executable, "app.py"],
                    cwd=webui,
                    creationflags=subprocess.CREATE_NEW_CONSOLE
                    | getattr(subprocess, "DETACHED_PROCESS", 0),
                )
                time.sleep(3)
                try:
                    webbrowser.open("http://127.0.0.1:5000")
                except Exception:
                    pass
                return {
                    "ok": True,
                    "launched": "web",
                    "url": "http://127.0.0.1:5000",
                    "mcp_sse": "http://127.0.0.1:5001/sse",
                }
            else:
                script = os.path.join(root, "OptimizeGUI.ps1")
                if not os.path.exists(script):
                    return {"ok": False, "error": f"找不到客户端: {script}"}
                if admin:
                    arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}"'.format(script)
                    cmd = "Start-Process powershell -ArgumentList '{0}' -Verb RunAs".format(arg)
                    p = subprocess.Popen(
                        ["powershell.exe", "-NoProfile", "-Command", cmd],
                        creationflags=getattr(subprocess, "DETACHED_PROCESS", 0),
                    )
                else:
                    p = subprocess.Popen(
                        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script],
                        creationflags=getattr(subprocess, "DETACHED_PROCESS", 0),
                    )
                return {"ok": True, "launched": "gui", "admin": admin, "pid": p.pid}
        except Exception as e:
            return {"ok": False, "error": str(e)}


if MCP_AVAILABLE:
    mcp = FastMCP("PC-Optimizer-7thGen", host="127.0.0.1", port=5001)
    _register_mcp_tools(mcp)


def run_ps(script_name, *args):
    """调用 PowerShell 脚本，返回解析后的 JSON dict。"""
    script = os.path.join(PS_DIR, script_name)
    if not os.path.exists(script):
        return {"ok": False, "error": f"找不到脚本: {script_name}"}
    cmd = [
        "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", script
    ]
    for a in args:
        cmd.append(a)
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
        )
        out = proc.stdout.strip()
        # 提取最后一行 JSON（PowerShell 可能在前输出其他文本）
        lines = [l for l in out.splitlines() if l.strip().startswith("{")]
        if not lines:
            return {"ok": False, "error": "无 JSON 输出", "raw": out[-500:], "stderr": proc.stderr[-500:]}
        return json.loads(lines[-1])
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "执行超时（300s）"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ---------------- 页面 ----------------
@app.route("/")
def index():
    return render_template("index.html")


# ---------------- 系统概览 ----------------
@app.route("/api/overview")
def api_overview():
    return jsonify(run_ps("01_system_info.ps1"))


# ---------------- 清理 ----------------
@app.route("/api/clean/scan")
def api_clean_scan():
    return jsonify(run_ps("02_clean.ps1", "-Action", "scan"))


@app.route("/api/clean", methods=["POST"])
def api_clean():
    data = request.get_json(silent=True) or {}
    items = data.get("items", "all")
    return jsonify(run_ps("02_clean.ps1", "-Action", "clean", "-Items", str(items)))


# ---------------- 服务 ----------------
@app.route("/api/services")
def api_services():
    return jsonify(run_ps("03_services.ps1", "-Action", "list"))


@app.route("/api/services/apply", methods=["POST"])
def api_services_apply():
    data = request.get_json(silent=True) or {}
    mode = data.get("mode", "safe")
    return jsonify(run_ps("03_services.ps1", "-Action", "apply", "-Mode", mode))


@app.route("/api/services/restore", methods=["POST"])
def api_services_restore():
    return jsonify(run_ps("03_services.ps1", "-Action", "restore"))


# ---------------- 启动项 ----------------
@app.route("/api/startup")
def api_startup():
    return jsonify(run_ps("04_startup.ps1", "-Action", "list"))


@app.route("/api/startup/disable", methods=["POST"])
def api_startup_disable():
    data = request.get_json(silent=True) or {}
    items = data.get("items", "all")
    return jsonify(run_ps("04_startup.ps1", "-Action", "disable", "-Items", str(items)))


# ---------------- 更新与功能 ----------------
@app.route("/api/update/block", methods=["POST"])
def api_update_block():
    data = request.get_json(silent=True) or {}
    action = data.get("action", "status")  # apply / restore / status
    return jsonify(run_ps("10_block_update.ps1", "-Action", action))


@app.route("/api/update/manual", methods=["POST"])
def api_update_manual():
    data = request.get_json(silent=True) or {}
    action = data.get("action", "status")
    return jsonify(run_ps("11_manual_mode.ps1", "-Action", action))


@app.route("/api/update/hide")
def api_update_hide_list():
    return jsonify(run_ps("12_hide_updates.ps1", "-Action", "list"))


@app.route("/api/update/hidden")
def api_update_hidden_list():
    return jsonify(run_ps("12_hide_updates.ps1", "-Action", "list-hidden"))


@app.route("/api/update/hide", methods=["POST"])
def api_update_hide():
    data = request.get_json(silent=True) or {}
    items = data.get("items", "all")
    return jsonify(run_ps("12_hide_updates.ps1", "-Action", "hide", "-Items", str(items)))


@app.route("/api/update/show", methods=["POST"])
def api_update_show():
    data = request.get_json(silent=True) or {}
    items = data.get("items", "all")
    return jsonify(run_ps("12_hide_updates.ps1", "-Action", "show", "-Items", str(items)))


@app.route("/api/features")
def api_features():
    return jsonify(run_ps("13_features.ps1", "-Action", "list"))


@app.route("/api/features/enabled")
def api_features_enabled():
    return jsonify(run_ps("13_features.ps1", "-Action", "enabled"))


@app.route("/api/features/enable", methods=["POST"])
def api_features_enable():
    data = request.get_json(silent=True) or {}
    items = data.get("items", "all")
    return jsonify(run_ps("13_features.ps1", "-Action", "enable", "-Items", str(items)))


@app.route("/api/update/restore-auto", methods=["POST"])
def api_update_restore_auto():
    """恢复 Windows 自动更新（撤销手动更新模式 / 更新屏蔽）。"""
    return jsonify(run_ps("14_restore_autoupdate.ps1"))


# ---------------- 视觉效果 ----------------
@app.route("/api/visual")
def api_visual():
    return jsonify(run_ps("05_visual.ps1", "-Action", "list"))


@app.route("/api/visual/apply", methods=["POST"])
def api_visual_apply():
    data = request.get_json(silent=True) or {}
    value = int(data.get("value", 1))
    return jsonify(run_ps("05_visual.ps1", "-Action", "apply", "-Value", str(value)))


# ---------------- 电源计划 ----------------
@app.route("/api/power")
def api_power():
    return jsonify(run_ps("06_power.ps1", "-Action", "list"))


@app.route("/api/power/apply", methods=["POST"])
def api_power_apply():
    data = request.get_json(silent=True) or {}
    value = int(data.get("value", 1))
    usb = str(data.get("usb", True)).lower()
    pci = str(data.get("pci", True)).lower()
    return jsonify(run_ps("06_power.ps1", "-Action", "apply", "-Value", str(value),
                          "-Usb", usb, "-Pci", pci))


# ---------------- 磁盘优化 ----------------
@app.route("/api/disk")
def api_disk():
    return jsonify(run_ps("07_disk.ps1", "-Action", "list"))


@app.route("/api/disk/optimize", methods=["POST"])
def api_disk_optimize():
    data = request.get_json(silent=True) or {}
    trim = str(data.get("trim", True)).lower()
    defrag = str(data.get("defrag", True)).lower()
    winsxs = str(data.get("winsxs", True)).lower()
    compact = str(data.get("compact", False)).lower()
    return jsonify(run_ps("07_disk.ps1", "-Action", "optimize",
                          "-Trim", trim, "-Defrag", defrag,
                          "-WinSxS", winsxs, "-Compact", compact))


# ---------------- 网络优化 ----------------
@app.route("/api/network")
def api_network():
    return jsonify(run_ps("08_network.ps1", "-Action", "list"))


@app.route("/api/network/apply", methods=["POST"])
def api_network_apply():
    data = request.get_json(silent=True) or {}
    dns = int(data.get("dns", 0))
    tcp = str(data.get("tcp", True)).lower()
    rss = str(data.get("rss", True)).lower()
    rsc = str(data.get("rsc", True)).lower()
    dnscache = str(data.get("dnscache", True)).lower()
    return jsonify(run_ps("08_network.ps1", "-Action", "apply",
                          "-Dns", str(dns), "-Tcp", tcp, "-Rss", rss,
                          "-Rsc", rsc, "-DnsCache", dnscache))


# ---------------- 备份恢复 ----------------
@app.route("/api/backup/list")
def api_backup_list():
    return jsonify(run_ps("09_backup.ps1", "-Action", "list"))


@app.route("/api/backup/create", methods=["POST"])
def api_backup_create():
    return jsonify(run_ps("09_backup.ps1", "-Action", "create"))


@app.route("/api/backup/restore", methods=["POST"])
def api_backup_restore():
    data = request.get_json(silent=True) or {}
    f = data.get("file", "")
    if f:
        return jsonify(run_ps("09_backup.ps1", "-Action", "restore", "-File", f))
    return jsonify(run_ps("09_backup.ps1", "-Action", "restore"))


def start_mcp_background(port: int = 5001):
    """在后台线程启动 MCP (WebMCP) SSE server，供 AI 客户端调用优化功能。

    与 Flask 主服务并存：Flask 跑 WSGI(5000)，MCP 跑 ASGI(5001)。
    缺少 mcp 库时静默跳过，不影响 WebUI。
    """
    if not (MCP_AVAILABLE and mcp is not None):
        print("[MCP] 未安装 mcp 库，跳过 WebMCP。安装方法: pip install 'mcp<2'")
        return False
    try:
        import threading

        import uvicorn

        sse_app = mcp.sse_app()

        def _run_mcp():
            try:
                uvicorn.run(sse_app, host="127.0.0.1", port=port,
                            log_level="warning", access_log=False)
            except Exception as e:  # noqa: BLE001
                print(f"[MCP] 启动失败: {e}")

        threading.Thread(target=_run_mcp, daemon=True, name="MCP-SSE").start()
        print(f"[MCP] WebMCP 已启动: SSE 端点 http://127.0.0.1:{port}/sse "
              f"(Claude Desktop / Cursor / Cline 可配置)")
        return True
    except Exception as e:  # noqa: BLE001
        print(f"[MCP] 初始化失败（非致命，WebUI 继续）: {e}")
        return False


if __name__ == "__main__":
    import ctypes

    # 提示当前是否管理员（用于前端提示）
    is_admin = ctypes.windll.shell32.IsUserAnAdmin() != 0 if os.name == "nt" else True
    print(f"[WebUI] 管理员权限: {'是' if is_admin else '否（部分功能可能失败）'}")
    print(f"[WebUI] 访问地址: http://127.0.0.1:5000")

    start_mcp_background(5001)

    app.run(host="127.0.0.1", port=5000, debug=False, threaded=True)
