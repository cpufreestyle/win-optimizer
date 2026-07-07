#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Windows 剪贴板修复工具 - 命令行版本
"""

import argparse
import subprocess
import sys
import time


def run_cmd(cmd, hide=True):
    """执行命令"""
    try:
        if hide:
            subprocess.run(
                cmd, 
                shell=True, 
                check=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
        else:
            subprocess.run(cmd, shell=True, check=True)
        return True
    except Exception as e:
        print(f"❌ 错误: {e}")
        return False


def check_status():
    """检测服务状态"""
    print("\n📊 剪贴板服务状态:\n")
    
    services = ["rdpclip.exe", "explorer.exe"]
    for service in services:
        try:
            result = subprocess.run(
                f'tasklist /fi "imagename eq {service}"',
                shell=True,
                capture_output=True,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            if service.lower() in result.stdout.lower():
                print(f"  ✅ {service:<20} 运行中")
            else:
                print(f"  ❌ {service:<20} 未运行")
        except:
            print(f"  ❓ {service:<20} 未知")


def restart_clipboard():
    """重启剪贴板服务"""
    print("\n🔄 重启剪贴板服务...")
    
    print("  • 终止 rdpclip.exe...", end=" ")
    run_cmd("taskkill /f /im rdpclip.exe")
    print("✅")
    
    time.sleep(1)
    
    print("  • 启动 rdpclip.exe...", end=" ")
    run_cmd('start "" "C:\\Windows\\System32\\rdpclip.exe"')
    print("✅")
    
    print("\n✅ 剪贴板服务已重启")


def clear_clipboard():
    """清空剪贴板"""
    print("\n🗑️ 清空剪贴板...")
    
    run_cmd("echo off | clip")
    run_cmd("powershell -command \"[System.Windows.Forms.Clipboard]::Clear()\"")
    
    print("✅ 剪贴板已清空")


def restart_explorer():
    """重启资源管理器"""
    print("\n🔁 重启资源管理器...")
    
    print("  • 终止 explorer.exe...", end=" ")
    run_cmd("taskkill /f /im explorer.exe")
    print("✅")
    
    time.sleep(2)
    
    print("  • 启动 explorer.exe...", end=" ")
    run_cmd('start "" "C:\\Windows\\explorer.exe"')
    print("✅")
    
    print("\n✅ 资源管理器已重启")


def fix_all():
    """一键修复"""
    print("\n")
    print("╔══════════════════════════════════════╗")
    print("║       ✨ 一键修复开始                ║")
    print("╚══════════════════════════════════════╝")
    
    print("\n[1/5] 清空剪贴板...", end=" ")
    run_cmd("echo off | clip")
    print("✅")
    
    print("[2/5] 终止剪贴板服务...", end=" ")
    run_cmd("taskkill /f /im rdpclip.exe")
    print("✅")
    
    print("[3/5] 终止资源管理器...", end=" ")
    run_cmd("taskkill /f /im explorer.exe")
    print("✅")
    
    time.sleep(2)
    
    print("[4/5] 启动剪贴板服务...", end=" ")
    run_cmd('start "" "C:\\Windows\\System32\\rdpclip.exe"')
    print("✅")
    
    time.sleep(1)
    
    print("[5/5] 启动资源管理器...", end=" ")
    run_cmd('start "" "C:\\Windows\\explorer.exe"')
    print("✅")
    
    print("\n")
    print("╔══════════════════════════════════════╗")
    print("║       🎉 修复完成！                  ║")
    print("║   请测试复制粘贴功能                 ║")
    print("╚══════════════════════════════════════╝")


def main():
    parser = argparse.ArgumentParser(
        description="Windows 剪贴板修复工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python clipboard_fixer.py --status    查看状态
  python clipboard_fixer.py --fix       一键修复
  python clipboard_fixer.py --restart   重启服务
        """
    )
    
    parser.add_argument("--status", action="store_true", help="检测剪贴板状态")
    parser.add_argument("--fix", action="store_true", help="一键修复")
    parser.add_argument("--restart", action="store_true", help="重启剪贴板服务")
    parser.add_argument("--clear", action="store_true", help="清空剪贴板")
    parser.add_argument("--explorer", action="store_true", help="重启资源管理器")
    parser.add_argument("--gui", action="store_true", help="启动图形界面")
    
    args = parser.parse_args()
    
    if args.gui:
        try:
            from clipboard_fixer_gui import ClipboardFixerGUI
            import tkinter as tk
            root = tk.Tk()
            app = ClipboardFixerGUI(root)
            root.mainloop()
        except ImportError as e:
            print(f"❌ 无法启动 GUI: {e}")
            print("请确保已安装 tkinter")
        return
    
    if args.status:
        check_status()
    elif args.fix:
        fix_all()
    elif args.restart:
        restart_clipboard()
    elif args.clear:
        clear_clipboard()
    elif args.explorer:
        restart_explorer()
    else:
        while True:
            print("\n")
            print("╔══════════════════════════════════════╗")
            print("║     🔧 Windows 剪贴板修复工具        ║")
            print("╚══════════════════════════════════════╝")
            print("\n[1] 🔍 检测状态")
            print("[2] 🔄 重启剪贴板服务")
            print("[3] 🗑️  清空剪贴板")
            print("[4] 🔁 重启资源管理器")
            print("[5] ✨ 一键修复")
            print("[0] 🚪 退出")
            
            choice = input("\n请选择 (0-5): ").strip()
            
            if choice == "1":
                check_status()
            elif choice == "2":
                restart_clipboard()
            elif choice == "3":
                clear_clipboard()
            elif choice == "4":
                restart_explorer()
            elif choice == "5":
                fix_all()
            elif choice == "0":
                print("\n再见！")
                break
            else:
                print("\n无效选择，请重试")


if __name__ == "__main__":
    main()
