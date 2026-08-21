"""
PC-Optimizer-7thGen WebUI 后端
本地运行，不联网。通过 subprocess 调用 webui/ps/ 下的 PowerShell 脚本（管理员权限）。
"""
import os
import sys
import json
import subprocess
from flask import Flask, render_template, jsonify, request, send_from_directory

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PS_DIR = os.path.join(BASE_DIR, "ps")
TEMPLATES = os.path.join(BASE_DIR, "templates")
STATIC = os.path.join(BASE_DIR, "static")

app = Flask(__name__, template_folder=TEMPLATES, static_folder=STATIC)


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


if __name__ == "__main__":
    import ctypes
    # 提示当前是否管理员（用于前端提示）
    is_admin = ctypes.windll.shell32.IsUserAnAdmin() != 0 if os.name == "nt" else True
    print(f"[WebUI] 管理员权限: {'是' if is_admin else '否（部分功能可能失败）'}")
    print(f"[WebUI] 访问地址: http://127.0.0.1:5000")
    app.run(host="127.0.0.1", port=5000, debug=False, threaded=True)
