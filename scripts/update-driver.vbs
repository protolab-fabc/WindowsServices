Option Explicit

' ============================================================
' Service d'arriere-plan automatique
' 1. Maintien et relance automatique du serveur si coupe / crash
' 2. Sauvegarde et mise a jour quotidienne a 01:00 du matin
' ============================================================

Dim objShell, objFSO
Dim serverDir, startScript, updateScript, lockFile, manualLockFile
Dim lastRunDate, nowTime, todayStr, hourVal, minVal

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

serverDir = "C:\WindowsServices"
startScript = serverDir & "\scripts\start.vbs"
updateScript = serverDir & "\scripts\update-backup.vbs"
lockFile = serverDir & "\update-backup.lock"
manualLockFile = serverDir & "\manual-stop.lock"

lastRunDate = ""

' Boucle permanente de surveillance (Watchdog & Scheduler)
Do
    nowTime = Now
    todayStr = Year(nowTime) & "-" & Month(nowTime) & "-" & Day(nowTime)
    hourVal = Hour(nowTime)
    minVal = Minute(nowTime)

    ' ------------------------------------------------------------
    ' 1. Declenchement de la maintenance a 01:00 du matin
    ' ------------------------------------------------------------
    If hourVal = 1 And minVal < 10 Then
        If lastRunDate <> todayStr Then
            lastRunDate = todayStr
            If objFSO.FileExists(updateScript) Then
                objShell.Run "wscript.exe //B //nologo """ & updateScript & """ /silent", 0, False
            End If
        End If
    End If

    ' ------------------------------------------------------------
    ' 2. Watchdog : Relance automatique si le serveur est coupe
    ' ------------------------------------------------------------
    ' Ne relance pas si une maintenance ou un arret manuel est en cours
    If Not objFSO.FileExists(lockFile) And Not objFSO.FileExists(manualLockFile) Then
        If Not IsJavaServerRunning() Then
            ' Attente de 3 secondes et re-verification pour eviter faux positif
            WScript.Sleep 3000
            If Not IsJavaServerRunning() And Not objFSO.FileExists(lockFile) And Not objFSO.FileExists(manualLockFile) Then
                If objFSO.FileExists(startScript) Then
                    objShell.Run "wscript.exe //B """ & startScript & """", 0, False
                    WScript.Sleep 15000
                End If
            End If
        End If
    End If

    ' Pause entre les verifications (15 secondes)
    WScript.Sleep 15000
Loop

' ==================== FONCTIONS ====================

Function IsJavaServerRunning()
    Dim objWMIService, colProcesses, objProcess
    IsJavaServerRunning = False

    On Error Resume Next
    Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number = 0 Then
        Set colProcesses = objWMIService.ExecQuery("Select ProcessId, CommandLine from Win32_Process Where Name = 'java.exe'")
        For Each objProcess In colProcesses
            If InStr(1, objProcess.CommandLine, "server.jar", 1) > 0 Then
                IsJavaServerRunning = True
                Exit For
            End If
        Next
        Set colProcesses = Nothing
        Set objWMIService = Nothing
    End If
    On Error GoTo 0
End Function
