import ctypes
import os
import queue
import shutil
import stat
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from tkinter import BOTH, END, LEFT, RIGHT, VERTICAL, BooleanVar, StringVar, Tk, messagebox, ttk


def format_bytes(size: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.2f} {unit}"
        value /= 1024
    return f"{size} B"


def safe_path(value: str | None) -> Path | None:
    if not value:
        return None
    path = Path(os.path.expandvars(value)).expanduser()
    return path if path.exists() else None


@dataclass(frozen=True)
class CleanupTarget:
    key: str
    name: str
    description: str
    path: str | None = None
    recycle_bin: bool = False


TARGETS = [
    CleanupTarget(
        key="user_temp",
        name="User temp files",
        description="Application cache and temp files for the current user.",
        path=r"%LOCALAPPDATA%\Temp",
    ),
    CleanupTarget(
        key="system_temp",
        name="Windows temp",
        description="Global Windows temp folder.",
        path=r"C:\Windows\Temp",
    ),
    CleanupTarget(
        key="windows_update",
        name="Windows Update cache",
        description="Downloaded update packages left on disk.",
        path=r"C:\Windows\SoftwareDistribution\Download",
    ),
    CleanupTarget(
        key="prefetch",
        name="Prefetch cache",
        description="Program prefetch cache. Windows may rebuild it later.",
        path=r"C:\Windows\Prefetch",
    ),
    CleanupTarget(
        key="thumbnail_cache",
        name="Thumbnail cache",
        description="Explorer thumbnail database and icon cache files.",
        path=r"%LOCALAPPDATA%\Microsoft\Windows\Explorer",
    ),
    CleanupTarget(
        key="crash_dumps",
        name="Crash dumps",
        description="Local crash dump files created by applications.",
        path=r"%LOCALAPPDATA%\CrashDumps",
    ),
    CleanupTarget(
        key="wer_reports",
        name="Error reports",
        description="Windows Error Reporting cache and reports.",
        path=r"%LOCALAPPDATA%\Microsoft\Windows\WER",
    ),
    CleanupTarget(
        key="recycle_bin",
        name="Recycle Bin",
        description="Empty the system Recycle Bin.",
        recycle_bin=True,
    ),
]


class CleanerApp:
    def __init__(self, root: Tk) -> None:
        self.root = root
        self.root.title("C Drive Cleaner")
        self.root.geometry("920x640")
        self.root.minsize(860, 580)

        self.log_queue: queue.Queue[str] = queue.Queue()
        self.status_var = StringVar(value="Ready")
        self.total_var = StringVar(value="0 B")
        self.scan_button: ttk.Button | None = None
        self.clean_button: ttk.Button | None = None
        self.select_all_button: ttk.Button | None = None
        self.clear_all_button: ttk.Button | None = None
        self.progress: ttk.Progressbar | None = None
        self.target_table: ttk.Treeview | None = None
        self.log_table: ttk.Treeview | None = None
        self.row_state: dict[str, dict[str, object]] = {}
        self.scanning = False
        self.cleaning = False

        self._build_ui()
        self._start_log_pump()
        self.scan_targets()

    def _build_ui(self) -> None:
        style = ttk.Style()
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("Segoe UI", 16, "bold"))
        style.configure("Muted.TLabel", foreground="#4b5563")

        container = ttk.Frame(self.root, padding=18)
        container.pack(fill=BOTH, expand=True)

        header = ttk.Frame(container)
        header.pack(fill="x")
        ttk.Label(header, text="C Drive Cleaner", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            header,
            text="Scans common cache and temp folders only. Personal folders are not touched.",
            style="Muted.TLabel",
        ).pack(anchor="w", pady=(6, 0))

        summary = ttk.Frame(container, padding=(0, 14, 0, 10))
        summary.pack(fill="x")
        ttk.Label(summary, text="Selected reclaimable space:", font=("Segoe UI", 10, "bold")).pack(side=LEFT)
        ttk.Label(summary, textvariable=self.total_var, font=("Segoe UI", 11)).pack(side=LEFT, padx=(8, 0))
        ttk.Label(summary, textvariable=self.status_var, style="Muted.TLabel").pack(side=RIGHT)

        self.progress = ttk.Progressbar(container, mode="indeterminate")
        self.progress.pack(fill="x", pady=(0, 12))

        actions = ttk.Frame(container)
        actions.pack(fill="x", pady=(0, 12))
        self.scan_button = ttk.Button(actions, text="Scan", command=self.scan_targets)
        self.scan_button.pack(side=LEFT)
        self.clean_button = ttk.Button(actions, text="Clean selected", command=self.clean_selected)
        self.clean_button.pack(side=LEFT, padx=10)
        self.select_all_button = ttk.Button(actions, text="Select all", command=lambda: self._set_all(True))
        self.select_all_button.pack(side=LEFT)
        self.clear_all_button = ttk.Button(actions, text="Clear selection", command=lambda: self._set_all(False))
        self.clear_all_button.pack(side=LEFT, padx=10)

        table_frame = ttk.LabelFrame(container, text="Cleanup targets", padding=12)
        table_frame.pack(fill=BOTH, expand=True)

        columns = ("target", "description", "path", "size", "count")
        self.target_table = ttk.Treeview(table_frame, columns=columns, show="headings", height=12)
        self.target_table.heading("target", text="Target")
        self.target_table.heading("description", text="Description")
        self.target_table.heading("path", text="Path")
        self.target_table.heading("size", text="Size")
        self.target_table.heading("count", text="Files")
        self.target_table.column("target", width=180, anchor="w")
        self.target_table.column("description", width=250, anchor="w")
        self.target_table.column("path", width=280, anchor="w")
        self.target_table.column("size", width=90, anchor="center")
        self.target_table.column("count", width=80, anchor="center")
        self.target_table.pack(fill=BOTH, expand=True, side=LEFT)

        scrollbar = ttk.Scrollbar(table_frame, orient=VERTICAL, command=self.target_table.yview)
        self.target_table.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(fill="y", side=RIGHT)

        for target in TARGETS:
            state = {"var": BooleanVar(value=False), "size": 0, "count": 0, "scanned": False}
            path_text = "Recycle Bin" if target.recycle_bin else str(safe_path(target.path) or "Unavailable")
            item_id = self.target_table.insert(
                "",
                END,
                values=(self._label_text(target.key), target.description, path_text, "Not scanned", "-"),
                tags=(target.key,),
            )
            state["item"] = item_id
            self.row_state[target.key] = state
            self.target_table.tag_bind(target.key, "<Double-1>", lambda _event, key=target.key: self._toggle_item(key))

        ttk.Label(
            container,
            text="Tip: double-click a row to toggle selection. Some system folders may require administrator rights.",
            style="Muted.TLabel",
        ).pack(fill="x", pady=(10, 6))

        log_frame = ttk.LabelFrame(container, text="Execution log", padding=12)
        log_frame.pack(fill=BOTH, expand=False)
        self.log_table = ttk.Treeview(log_frame, columns=("time", "message"), show="headings", height=8)
        self.log_table.heading("time", text="Time")
        self.log_table.heading("message", text="Message")
        self.log_table.column("time", width=90, anchor="center")
        self.log_table.column("message", width=760, anchor="w")
        self.log_table.pack(fill=BOTH, expand=True)

    def _label_text(self, key: str) -> str:
        target = next(item for item in TARGETS if item.key == key)
        row = self.row_state.get(key)
        checked = False
        if row:
            checked = row["var"].get()
        return f"[{'x' if checked else ' '}] {target.name}"

    def _start_log_pump(self) -> None:
        self._drain_logs()

    def _drain_logs(self) -> None:
        while not self.log_queue.empty():
            message = self.log_queue.get_nowait()
            now = time.strftime("%H:%M:%S")
            self.log_table.insert("", END, values=(now, message))
            children = self.log_table.get_children()
            if children:
                self.log_table.see(children[-1])
        self.root.after(150, self._drain_logs)

    def log(self, message: str) -> None:
        self.log_queue.put(message)

    def _toggle_item(self, key: str) -> None:
        if self.scanning or self.cleaning:
            return
        row = self.row_state[key]
        row["var"].set(not row["var"].get())
        self._refresh_row(key)

    def _set_all(self, value: bool) -> None:
        if self.scanning or self.cleaning:
            return
        for key, row in self.row_state.items():
            row["var"].set(value)
            self._refresh_row(key)

    def _refresh_row(self, key: str) -> None:
        target = next(item for item in TARGETS if item.key == key)
        row = self.row_state[key]
        path_text = "Recycle Bin" if target.recycle_bin else str(safe_path(target.path) or "Unavailable")
        if row["scanned"]:
            size_text = format_bytes(int(row["size"]))
            count_text = str(row["count"])
        else:
            size_text = "Not scanned"
            count_text = "-"
        self.target_table.item(
            row["item"],
            values=(self._label_text(key), target.description, path_text, size_text, count_text),
        )
        self._refresh_total()

    def _refresh_total(self) -> None:
        total = 0
        for row in self.row_state.values():
            if row["var"].get():
                total += int(row["size"])
        self.total_var.set(format_bytes(total))

    def _set_busy(self, busy: bool, message: str) -> None:
        self.status_var.set(message)
        state = "disabled" if busy else "normal"
        for button in (self.scan_button, self.clean_button, self.select_all_button, self.clear_all_button):
            if button:
                button.config(state=state)
        if self.progress:
            if busy:
                self.progress.start(12)
            else:
                self.progress.stop()

    def scan_targets(self) -> None:
        if self.scanning or self.cleaning:
            return
        self.scanning = True
        self._set_busy(True, "Scanning...")
        self.log("Scan started.")
        threading.Thread(target=self._scan_worker, daemon=True).start()

    def _scan_worker(self) -> None:
        for target in TARGETS:
            size = 0
            count = 0
            try:
                if target.recycle_bin:
                    size, count = self._scan_recycle_bin()
                else:
                    path = safe_path(target.path)
                    if path is None:
                        raise FileNotFoundError("Target path is unavailable.")
                    size, count = self._scan_directory(path)
                self.log(f"{target.name}: {format_bytes(size)} found.")
            except Exception as exc:
                self.log(f"{target.name}: scan failed - {exc}")
            row = self.row_state[target.key]
            row["size"] = size
            row["count"] = count
            row["scanned"] = True
            self.root.after(0, lambda key=target.key: self._refresh_row(key))
        self.root.after(0, self._scan_done)

    def _scan_done(self) -> None:
        self.scanning = False
        self._set_busy(False, "Scan completed")
        self.log("Scan completed.")
        self._refresh_total()

    def clean_selected(self) -> None:
        if self.scanning or self.cleaning:
            return

        selected = [target for target in TARGETS if self.row_state[target.key]["var"].get()]
        if not selected:
            messagebox.showinfo("Cleaner", "Select at least one target.")
            return

        total = sum(int(self.row_state[target.key]["size"]) for target in selected)
        confirmed = messagebox.askyesno(
            "Confirm cleanup",
            f"You are about to clean {len(selected)} target(s).\nEstimated reclaimable space: {format_bytes(total)}\n\nContinue?",
        )
        if not confirmed:
            return

        self.cleaning = True
        self._set_busy(True, "Cleaning...")
        self.log("Cleanup started.")
        threading.Thread(target=self._clean_worker, args=(selected,), daemon=True).start()

    def _clean_worker(self, selected: list[CleanupTarget]) -> None:
        freed = 0
        for target in selected:
            try:
                if target.recycle_bin:
                    before, _ = self._scan_recycle_bin()
                    self._clear_recycle_bin()
                    freed += before
                else:
                    path = safe_path(target.path)
                    if path is None:
                        raise FileNotFoundError("Target path is unavailable.")
                    freed += self._clear_directory(path)
                self.log(f"{target.name}: cleanup completed.")
            except Exception as exc:
                self.log(f"{target.name}: cleanup failed - {exc}")
            row = self.row_state[target.key]
            row["size"] = 0
            row["count"] = 0
            row["scanned"] = True
            row["var"].set(False)
            self.root.after(0, lambda key=target.key: self._refresh_row(key))
        self.root.after(0, lambda: self._clean_done(freed))

    def _clean_done(self, freed: int) -> None:
        self.cleaning = False
        self._set_busy(False, "Cleanup completed")
        self.total_var.set("0 B")
        self.log(f"Cleanup completed. Approx. {format_bytes(freed)} reclaimed.")
        messagebox.showinfo("Cleaner", f"Cleanup completed.\nApprox. {format_bytes(freed)} reclaimed.")

    def _scan_directory(self, path: Path) -> tuple[int, int]:
        total_size = 0
        file_count = 0
        for root, _, files in os.walk(path, topdown=True, onerror=None):
            for file_name in files:
                file_path = Path(root) / file_name
                try:
                    total_size += file_path.stat().st_size
                    file_count += 1
                except OSError:
                    continue
        return total_size, file_count

    def _clear_directory(self, path: Path) -> int:
        freed = 0
        for item in path.iterdir():
            try:
                item_size = self._path_size(item)
                self._remove_path(item)
                freed += item_size
            except Exception as exc:
                self.log(f"Skipped {item}: {exc}")
        return freed

    def _path_size(self, path: Path) -> int:
        if path.is_file():
            try:
                return path.stat().st_size
            except OSError:
                return 0
        size = 0
        for root, _, files in os.walk(path, topdown=True, onerror=None):
            for file_name in files:
                file_path = Path(root) / file_name
                try:
                    size += file_path.stat().st_size
                except OSError:
                    continue
        return size

    def _remove_path(self, path: Path) -> None:
        if not path.exists():
            return
        try:
            if path.is_dir():
                shutil.rmtree(path, onexc=self._on_remove_error)
            else:
                self._ensure_writable(path)
                path.unlink()
        except TypeError:
            if path.is_dir():
                shutil.rmtree(path, onerror=self._legacy_remove_error)
            else:
                self._ensure_writable(path)
                path.unlink()

    def _ensure_writable(self, path: Path) -> None:
        try:
            os.chmod(path, stat.S_IWRITE)
        except OSError:
            pass

    def _on_remove_error(self, func, path, exc_info) -> None:
        del exc_info
        self._ensure_writable(Path(path))
        func(path)

    def _legacy_remove_error(self, func, path, _exc_info) -> None:
        self._ensure_writable(Path(path))
        func(path)

    def _scan_recycle_bin(self) -> tuple[int, int]:
        powershell = (
            "$shell = New-Object -ComObject Shell.Application; "
            "$bin = $shell.Namespace(0xA); "
            "$size = 0; $count = 0; "
            "if ($bin -ne $null) { "
            "foreach ($item in $bin.Items()) { "
            "$count++; "
            "try { $size += [int64]$item.ExtendedProperty('Size') } catch {} "
            "} "
            "} "
            "Write-Output \"$size|$count\""
        )
        output = subprocess.check_output(["powershell", "-NoProfile", "-Command", powershell], text=True).strip()
        size_text, count_text = output.split("|")
        return int(size_text), int(count_text)

    def _clear_recycle_bin(self) -> None:
        flags = 0x00000001 | 0x00000002 | 0x00000004
        result = ctypes.windll.shell32.SHEmptyRecycleBinW(None, None, flags)
        if result != 0:
            raise OSError(f"Windows returned error code {result}")


def main() -> None:
    root = Tk()
    CleanerApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
