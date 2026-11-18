' PC-Optimizer-7thGen VBS launcher
' Request admin and start PowerShell GUI (prefer PowerShell 7, fallback to 5.1)

Set objShell = CreateObject("Shell.Application")
strDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

If Not IsAdmin() Then
    objShell.ShellExecute "wscript.exe", """" & WScript.ScriptFullName & """", "", "runas", 1
    WScript.Quit
End If

' 优先 PowerShell 7（启动与后台查询快得多；老机器未装时回退 5.1）
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
If strPs = "" Then
    On Error Resume Next
    strPathDirs = objWsh.ExpandEnvironmentStrings("%PATH%")
    For Each strDirItem In Split(strPathDirs, ";")
        strDirItem = Trim(strDirItem)
        If strDirItem <> "" Then
            strCand = objFso.BuildPath(strDirItem, "pwsh.exe")
            If objFso.FileExists(strCand) Then
                strPs = strCand
                Exit For
            End If
        End If
    Next
    On Error GoTo 0
End If
If strPs = "" Then strPs = "powershell.exe"

' 第 5 个参数 0 = 隐藏控制台窗口，只显示 WinForms 界面
objShell.ShellExecute strPs, "-NoProfile -ExecutionPolicy Bypass -File """ & strDir & "\OptimizeGUI.ps1""", strDir, "", 0

Function IsAdmin()
    ' 注意：不能在这里把全局 objShell（Shell.Application）覆盖成 WScript.Shell，
    ' 否则提权分支再调 objShell.ShellExecute 会报「对象不支持此属性或方法」。
    Dim objProbe
    On Error Resume Next
    Set objProbe = CreateObject("WScript.Shell")
    Err.Clear
    objProbe.RegRead "HKEY_USERS\S-1-5-19\Environment\TEMP"
    IsAdmin = (Err.Number = 0)
    On Error GoTo 0
End Function
