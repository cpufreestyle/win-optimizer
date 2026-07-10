using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;

class Program
{
    static void Main(string[] args)
    {
        // Load WinForms assembly for MessageBox (required for winexe without explicit reference)
        Assembly.LoadWithPartialName("System.Windows.Forms");

        // Get EXE directory
        string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
        string ps1Path = Path.Combine(exeDir, "OptimizeGUI.ps1");

        if (!File.Exists(ps1Path))
        {
            System.Windows.Forms.MessageBox.Show(
                "Cannot find OptimizeGUI.ps1!\nPlease ensure it is in the same directory as this program.",
                "Error",
                System.Windows.Forms.MessageBoxButtons.OK,
                System.Windows.Forms.MessageBoxIcon.Error);
            return;
        }

        // Check admin privileges
        if (!IsAdministrator())
        {
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
                    "Administrator privileges are required to run this program.",
                    "Access Denied",
                    System.Windows.Forms.MessageBoxButtons.OK,
                    System.Windows.Forms.MessageBoxIcon.Warning);
            }
            return;
        }

        // Launch PowerShell GUI
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
                "Launch failed: " + ex.Message,
                "Error",
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
