' PC-Optimizer-7thGen VBS launcher
' Launch PowerShell GUI directly. Some operations need admin rights and will
' prompt separately inside the GUI; do not force elevation here.

Set objShell = CreateObject("Shell.Application")
strDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

Set objFso = CreateObject("Scripting.FileSystemObject")
Set objWsh = CreateObject("WScript.Shell")
strPs = ""
arrPaths = Array( _
    objWsh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\PowerShell-7\pwsh.exe"), _
    objWsh.ExpandEnvironmentStrings("%ProgramFiles%\PowerShell\7\pwsh.exe"), _
    objWsh.ExpandEnvironmentStrings("%ProgramFiles(x86)%\PowerShell\7\pwsh.exe") _
)
For Each strCand In arrPaths
    If objFso.FileExists(strCand) Then
        strPs = strCand
        Exit For
    End If
Next
If strPs = "" Then strPs = "powershell.exe"

strArgs = "-NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & strDir & "\OptimizeGUI.ps1" & Chr(34)
objShell.ShellExecute strPs, strArgs, strDir, "", 1
