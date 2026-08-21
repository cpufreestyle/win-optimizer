' PC-Optimizer-7thGen VBS launcher
' Request admin and start PowerShell GUI

Set objShell = CreateObject("Shell.Application")
strDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

If Not IsAdmin() Then
    objShell.ShellExecute "wscript.exe", """" & WScript.ScriptFullName & """", "", "runas", 1
    WScript.Quit
End If

objShell.ShellExecute "powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File """ & strDir & "\OptimizeGUI.ps1""", strDir, "", 1

Function IsAdmin()
    On Error Resume Next
    Set objShell = CreateObject("WScript.Shell")
    err.Clear
    objShell.RegRead("HKEY_USERS\S-1-5-19\Environment\TEMP")
    IsAdmin = (Err.Number = 0)
    On Error GoTo 0
End Function
