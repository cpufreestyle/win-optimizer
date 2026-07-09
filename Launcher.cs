using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;

class Program
{
    static void Main(string[] args)
    {
        // 获取 EXE 所在目录
        string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
        string ps1Path = Path.Combine(exeDir, "OptimizeGUI.ps1");

        if (!File.Exists(ps1Path))
        {
            System.Windows.Forms.MessageBox.Show(
                "找不到 OptimizeGUI.ps1 文件！\n请确保它与本程序在同一目录。",
                "错误",
                System.Windows.Forms.MessageBoxButtons.OK,
                System.Windows.Forms.MessageBoxIcon.Error);
            return;
        }

        // 检查管理员权限
        if (!IsAdministrator())
        {
            // 以管理员身份重启
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Process.GetCurrentProcess().MainModule.FileName;
            psi.WorkingDirectory = exeDir;
            psi.Verb = "runas";
            psi.UseShellExecute = true;
            try
            {
                Process.Start(psi);
            }
            catch
            {
                System.Windows.Forms.MessageBox.Show(
                    "需要管理员权限才能运行此程序！",
                    "权限不足",
                    System.Windows.Forms.MessageBoxButtons.OK,
                    System.Windows.Forms.MessageBoxIcon.Warning);
            }
            return;
        }

        // 启动 PowerShell
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = "powershell.exe";
        startInfo.Arguments = string.Format(
            "-NoProfile -ExecutionPolicy Bypass -File \"{0}\"", ps1Path);
        startInfo.WorkingDirectory = exeDir;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;

        try
        {
            Process p = Process.Start(startInfo);
            p.WaitForExit();
        }
        catch (Exception ex)
        {
            System.Windows.Forms.MessageBox.Show(
                "启动失败: " + ex.Message,
                "错误",
                System.Windows.Forms.MessageBoxButtons.OK,
                System.Windows.Forms.MessageBoxIcon.Error);
        }
    }

    static bool IsAdministrator()
    {
        try
        {
            WindowsIdentity identity = WindowsIdentity.GetCurrent();
            WindowsPrincipal principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }
}
