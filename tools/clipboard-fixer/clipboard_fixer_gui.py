#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Windows 鍓创鏉夸慨澶嶅伐鍏?- GUI 鐗堟湰
涓€閿慨澶嶅鍒剁矘璐村け鏁堥棶棰?"""

import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import threading

class ClipboardFixerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("馃敡 Windows 鍓创鏉夸慨澶嶅伐鍏?)
        self.root.geometry("400x500")
        self.root.resizable(False, False)
        
        try:
            self.root.iconbitmap("icon.ico")
        except:
            pass
        
        self.setup_ui()
        self.check_status()
    
    def setup_ui(self):
        title_frame = tk.Frame(self.root, bg="#2196F3", height=80)
        title_frame.pack(fill=tk.X)
        title_frame.pack_propagate(False)
        
        wm = tk.Label(
            title_frame,
            text="michaelqiu",
            font=("Arial", 16, "bold"),
            fg="#FFD700",
            bg="#2196F3"
        )
        wm.place(x=8, y=5)

        title_label = tk.Label(
            title_frame, 
            text="鍓创鏉夸慨澶嶅伐鍏?,
            font=("Arial", 18, "bold"),
            fg="white",
            bg="#2196F3"
        )
title_label.place(relx=0.5, rely=0.5, anchor=tk.CENTER)

status_frame = tk.LabelFrame(self.root, text="馃搳 鏈嶅姟鐘舵€?, font=("Microsoft YaHei", 10))
status_frame.pack(fill=tk.X, padx=20, pady=10)

self.status_labels = {}

        for service in ["rdpclip.exe", "explorer.exe"]:
            frame = tk.Frame(status_frame)
            frame.pack(fill=tk.X, padx=10, pady=5)
            
            tk.Label(frame, text=f"鈥?{service}:", font=("Microsoft YaHei", 9)).pack(side=tk.LEFT)
            self.status_labels[service] = tk.Label(
                frame, 
                text="妫€娴嬩腑...",
                font=("Microsoft YaHei", 9),
                fg="gray"
            )
            self.status_labels[service].pack(side=tk.RIGHT)
        
        button_frame = tk.LabelFrame(self.root, text="馃洜锔?淇鎿嶄綔", font=("Microsoft YaHei", 10))
        button_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)
        
        buttons = [
            ("馃攳 妫€娴嬬姸鎬?, self.check_status, "#4CAF50"),
            ("馃攧 閲嶅惎鍓创鏉挎湇鍔?, self.restart_clipboard, "#2196F3"),
            ("馃棏锔?娓呯┖鍓创鏉?, self.clear_clipboard, "#FF9800"),
            ("馃攣 閲嶅惎璧勬簮绠＄悊鍣?, self.restart_explorer, "#9C27B0"),
            ("鉁?涓€閿慨澶?, self.fix_all, "#F44336"),
        ]
        
        for text, command, color in buttons:
            btn = tk.Button(
                button_frame,
                text=text,
                command=command,
                font=("Microsoft YaHei", 10),
                bg=color,
                fg="white",
                relief=tk.FLAT,
                cursor="hand2",
                height=2
            )
            btn.pack(fill=tk.X, padx=10, pady=5)
            btn.bind("<Enter>", lambda e, b=btn, c=color: b.config(bg=self._lighten_color(c)))
            btn.bind("<Leave>", lambda e, b=btn, c=color: b.config(bg=c))
        
        log_frame = tk.LabelFrame(self.root, text="馃摑 鎿嶄綔鏃ュ織", font=("Microsoft YaHei", 10))
        log_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)
        
        self.log_text = tk.Text(log_frame, height=6, font=("Consolas", 9))
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        
        scrollbar = ttk.Scrollbar(self.log_text, command=self.log_text.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.config(yscrollcommand=scrollbar.set)
        
        tk.Label(
            self.root,
            text="Built with 鉂わ笍 | v1.0.1",
            font=("Microsoft YaHei", 8),
            fg="gray"
        ).pack(pady=5)
    
    def _lighten_color(self, color):
        colors = {
            "#4CAF50": "#66BB6A",
            "#2196F3": "#42A5F5",
            "#FF9800": "#FFA726",
            "#9C27B0": "#AB47BC",
            "#F44336": "#EF5350"
        }
        return colors.get(color, color)
    
    def log(self, message):
        self.log_text.insert(tk.END, f"[{self._get_time()}] {message}\n")
        self.log_text.see(tk.END)
    
    def _get_time(self):
        from datetime import datetime
        return datetime.now().strftime("%H:%M:%S")
    
    def run_command(self, cmd, show_window=True):
        try:
            if show_window:
                subprocess.run(cmd, shell=True, check=True)
            else:
                subprocess.run(
                    cmd, 
                    shell=True, 
                    check=True,
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
            return True
        except Exception as e:
            self.log(f"鉂?閿欒: {e}")
            return False
    
    def check_status(self):
        self.log("馃攳 妫€娴嬫湇鍔＄姸鎬?..")
        
        for service in ["rdpclip.exe", "explorer.exe"]:
            try:
                result = subprocess.run(
                    f'tasklist /fi "imagename eq {service}"',
                    shell=True,
                    capture_output=True,
                    text=True,
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
                if service.lower() in result.stdout.lower():
                    self.status_labels[service].config(text="鉁?杩愯涓?, fg="green")
                else:
                    self.status_labels[service].config(text="鉂?鏈繍琛?, fg="red")
            except:
                self.status_labels[service].config(text="鉂?鏈煡", fg="gray")
        
        self.log("鉁?鐘舵€佹娴嬪畬鎴?)
    
    def restart_clipboard(self):
        self.log("馃攧 閲嶅惎鍓创鏉挎湇鍔?..")
        
        def task():
            subprocess.run(
                "taskkill /f /im rdpclip.exe",
                shell=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            self.log("  鈥?宸茬粓姝?rdpclip.exe")
            
            import time
            time.sleep(1)
            
            subprocess.run(
                'start "" "C:\\Windows\\System32\\rdpclip.exe"',
                shell=True
            )
            self.log("  鈥?宸插惎鍔?rdpclip.exe")
            self.log("鉁?鍓创鏉挎湇鍔￠噸鍚畬鎴?)
        
        threading.Thread(target=task, daemon=True).start()
    
    def clear_clipboard(self):
        self.log("馃棏锔?娓呯┖鍓创鏉?..")
        
        try:
            subprocess.run(
                "echo off | clip",
                shell=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            subprocess.run(
                "powershell -command \"[System.Windows.Forms.Clipboard]::Clear()\"",
                shell=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            self.log("鉁?鍓创鏉垮凡娓呯┖")
        except Exception as e:
            self.log(f"鉂?娓呯┖澶辫触: {e}")
    
    def restart_explorer(self):
        self.log("馃攣 閲嶅惎璧勬簮绠＄悊鍣?..")
        
        def task():
            subprocess.run(
                "taskkill /f /im explorer.exe",
                shell=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            self.log("  鈥?宸茬粓姝?explorer.exe")
            
            import time
            time.sleep(2)
            
            subprocess.run(
                'start "" "C:\\Windows\\explorer.exe"',
                shell=True
            )
            self.log("  鈥?宸插惎鍔?explorer.exe")
            self.log("鉁?璧勬簮绠＄悊鍣ㄩ噸鍚畬鎴?)
        
        threading.Thread(target=task, daemon=True).start()
    
    def fix_all(self):
        self.log("鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?鉁?涓€閿慨澶嶅紑濮?鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?)
        
        def task():
            import time
            
            self.log("[1/5] 娓呯┖鍓创鏉?..")
            subprocess.run("echo off | clip", shell=True, creationflags=subprocess.CREATE_NO_WINDOW)
            time.sleep(0.5)
            self.log("      鉁?瀹屾垚")
            
            self.log("[2/5] 缁堟鍓创鏉挎湇鍔?..")
            subprocess.run("taskkill /f /im rdpclip.exe", shell=True, creationflags=subprocess.CREATE_NO_WINDOW)
            time.sleep(0.5)
            self.log("      鉁?瀹屾垚")
            
            self.log("[3/5] 缁堟璧勬簮绠＄悊鍣?..")
            subprocess.run("taskkill /f /im explorer.exe", shell=True, creationflags=subprocess.CREATE_NO_WINDOW)
            time.sleep(2)
            self.log("      鉁?瀹屾垚")
            
            self.log("[4/5] 鍚姩鍓创鏉挎湇鍔?..")
            subprocess.run('start "" "C:\\Windows\\System32\\rdpclip.exe"', shell=True)
            time.sleep(1)
            self.log("      鉁?瀹屾垚")
            
            self.log("[5/5] 鍚姩璧勬簮绠＄悊鍣?..")
            subprocess.run('start "" "C:\\Windows\\explorer.exe"', shell=True)
            time.sleep(1)
            self.log("      鉁?瀹屾垚")
            
            self.log("鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?馃帀 淇瀹屾垚锛?鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?)
            self.log("璇锋祴璇曞鍒剁矘璐村姛鑳?)
            
            self.check_status()
        
        threading.Thread(target=task, daemon=True).start()


def main():
    root = tk.Tk()
    app = ClipboardFixerGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
