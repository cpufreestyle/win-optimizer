' PC-Optimizer-7thGen VBS 启动器
' 自动请求管理员权限并启动 PowerShell GUI

Set objShell = CreateObject("Shell.Application")
strDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

' 检查是否已有管理员权限
Set objShellApp = CreateObject("Shell.Application")
If Not IsAdmin() Then
    ' 以管理员身份重新启动
    objShell.ShellExecute "wscript.exe", """" & WScript.ScriptFullName & """", "", "runas", 1
    WScript.Quit
End If

' 启动 PowerShell GUI
objShell.ShellExecute "powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File """ & strDir & "\OptimizeGUI.ps1""", strDir, "", 1

Function IsAdmin()
    On Error Resume Next
    Set objShell = CreateObject("WScript.Shell")
    ' 检查是否可以访问受保护路径
    err.Clear
    objShell.RegRead("HKEY_USERS\S-1-5-19\Environment\TEMP")
    IsAdmin = (Err.Number = 0)
    On Error GoTo 0
End Function
