Option Explicit

' ============================================================
' Minecraft Vanilla - Arret du serveur
' Tente un arret propre via RCON, puis force-kill si necessaire
' ============================================================

Dim objShell, objFSO
Dim serverDir, propsFile
Dim rconHost, rconPort, rconPassword, rconEnabled

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

serverDir = "C:\WindowsServices"
propsFile = serverDir & "\server.properties"

rconHost = "127.0.0.1"
rconPort = CLng(GetServerProperty("rcon.port", "25575"))
rconPassword = GetServerProperty("rcon.password", "ton_mot_de_passe_rcon")
rconEnabled = (LCase(GetServerProperty("enable-rcon", "true")) = "true")

' --- Verification que le serveur tourne ---
If Not IsJavaServerProcessRunning() Then
    WScript.Quit 0
End If

' --- Tentative d'arret propre via RCON ---
Dim stoppedCleanly
stoppedCleanly = False

If rconEnabled Then
    Dim rconResp
    SendRcon "say [SERVEUR] Arret immediat du serveur.", rconResp
    WScript.Sleep 1000
    SendRcon "save-all flush", rconResp
    WScript.Sleep 2000
    SendRcon "stop", rconResp

    ' Attendre jusqu'a 60s l'arret propre
    Dim startTime
    startTime = Timer
    Do While IsJavaServerProcessRunning()
        WScript.Sleep 1000
        If ElapsedMs(startTime) > 60000 Then Exit Do
    Loop

    If Not IsJavaServerProcessRunning() Then
        stoppedCleanly = True
    End If
End If

' --- Force-kill si l'arret propre a echoue ---
If Not stoppedCleanly And IsJavaServerProcessRunning() Then
    ForceKillServer
End If

WScript.Quit 0

' ==================== FONCTIONS ====================

Function IsJavaServerProcessRunning()
    Dim objWMI, procs, p
    IsJavaServerProcessRunning = False
    On Error Resume Next
    Set objWMI = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number <> 0 Then
        On Error GoTo 0
        Exit Function
    End If
    Set procs = objWMI.ExecQuery("Select * from Win32_Process Where Name = 'java.exe'")
    For Each p In procs
        If InStr(1, p.CommandLine, "server.jar", 1) > 0 Or InStr(1, p.CommandLine, "MinecraftServer", 1) > 0 Then
            IsJavaServerProcessRunning = True
            Exit For
        End If
    Next
    Set procs = Nothing
    Set objWMI = Nothing
    On Error GoTo 0
End Function

Sub ForceKillServer()
    Dim objWMI, procs, p
    On Error Resume Next
    Set objWMI = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number = 0 Then
        Set procs = objWMI.ExecQuery("Select * from Win32_Process Where Name = 'java.exe'")
        For Each p In procs
            If InStr(1, p.CommandLine, "server.jar", 1) > 0 Or InStr(1, p.CommandLine, "MinecraftServer", 1) > 0 Then
                p.Terminate()
            End If
        Next
        Set procs = Nothing
        Set objWMI = Nothing
    End If
    On Error GoTo 0
End Sub

Function SendRcon(ByVal commandText, ByRef responseText)
    Dim psCode, b64Code, tmpFile, cmd, exitCode
    responseText = ""
    If Not rconEnabled Then
        SendRcon = False
        Exit Function
    End If

    tmpFile = serverDir & "\rcon_" & objFSO.GetTempName() & ".tmp"

    psCode = "$ErrorActionPreference = 'Stop';" & vbCrLf & _
             "$client = New-Object System.Net.Sockets.TcpClient;" & vbCrLf & _
             "$ar = $client.BeginConnect('" & rconHost & "', " & rconPort & ", $null, $null);" & vbCrLf & _
             "if (-not $ar.AsyncWaitHandle.WaitOne(3000, $false)) { $client.Close(); exit 1 };" & vbCrLf & _
             "$client.EndConnect($ar);" & vbCrLf & _
             "$client.SendTimeout = 3000;" & vbCrLf & _
             "$client.ReceiveTimeout = 3000;" & vbCrLf & _
             "$stream = $client.GetStream();" & vbCrLf & _
             "try {" & vbCrLf & _
             "    function Send-Pkt([int]$id, [int]$t, [string]$b) {" & vbCrLf & _
             "        $bytes = [System.Text.Encoding]::UTF8.GetBytes($b);" & vbCrLf & _
             "        $ms = New-Object System.IO.MemoryStream;" & vbCrLf & _
             "        $bw = New-Object System.IO.BinaryWriter($ms);" & vbCrLf & _
             "        $bw.Write([int32](10 + $bytes.Length));" & vbCrLf & _
             "        $bw.Write([int32]$id);" & vbCrLf & _
             "        $bw.Write([int32]$t);" & vbCrLf & _
             "        if ($bytes.Length -gt 0) { $bw.Write($bytes) };" & vbCrLf & _
             "        $bw.Write([byte]0); $bw.Write([byte]0);" & vbCrLf & _
             "        $pkt = $ms.ToArray();" & vbCrLf & _
             "        $stream.Write($pkt, 0, $pkt.Length);" & vbCrLf & _
             "        $stream.Flush();" & vbCrLf & _
             "    };" & vbCrLf & _
             "    function Read-Pkt() {" & vbCrLf & _
             "        $lenBytes = New-Object byte[] 4;" & vbCrLf & _
             "        $read = 0;" & vbCrLf & _
             "        while ($read -lt 4) {" & vbCrLf & _
             "            $r = $stream.Read($lenBytes, $read, 4 - $read);" & vbCrLf & _
             "            if ($r -le 0) { throw 'Socket closed reading length' };" & vbCrLf & _
             "            $read += $r;" & vbCrLf & _
             "        };" & vbCrLf & _
             "        $len = [System.BitConverter]::ToInt32($lenBytes, 0);" & vbCrLf & _
             "        $data = New-Object byte[] $len;" & vbCrLf & _
             "        $read = 0;" & vbCrLf & _
             "        while ($read -lt $len) {" & vbCrLf & _
             "            $r = $stream.Read($data, $read, $len - $read);" & vbCrLf & _
             "            if ($r -le 0) { throw 'Socket closed reading body' };" & vbCrLf & _
             "            $read += $r;" & vbCrLf & _
             "        };" & vbCrLf & _
             "        $id = [System.BitConverter]::ToInt32($data, 0);" & vbCrLf & _
             "        $t = [System.BitConverter]::ToInt32($data, 4);" & vbCrLf & _
             "        $body = '';" & vbCrLf & _
             "        if ($len -gt 10) {" & vbCrLf & _
             "            $body = [System.Text.Encoding]::UTF8.GetString($data, 8, $len - 10);" & vbCrLf & _
             "        };" & vbCrLf & _
             "        return @{ Id = $id; Type = $t; Body = $body };" & vbCrLf & _
             "    };" & vbCrLf & _
             "    Send-Pkt 1 3 '" & Replace(rconPassword, "'", "''") & "';" & vbCrLf & _
             "    $auth = Read-Pkt;" & vbCrLf & _
             "    if ($auth.Id -eq -1) { throw 'RCON auth failed' };" & vbCrLf & _
             "    Send-Pkt 2 2 '" & Replace(commandText, "'", "''") & "';" & vbCrLf & _
             "    $resp = Read-Pkt;" & vbCrLf & _
             "    [System.IO.File]::WriteAllText('" & Replace(tmpFile, "'", "''") & "', $resp.Body, [System.Text.Encoding]::UTF8);" & vbCrLf & _
             "} finally {" & vbCrLf & _
             "    $stream.Close();" & vbCrLf & _
             "    $client.Close();" & vbCrLf & _
             "}"

    b64Code = Base64Encode(psCode)
    cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " & b64Code

    On Error Resume Next
    exitCode = objShell.Run(cmd, 0, True)
    If Err.Number <> 0 Then
        responseText = "Erreur execution PowerShell : " & Err.Description
        SendRcon = False
        SafeDelete tmpFile
        On Error GoTo 0
        Exit Function
    End If
    On Error GoTo 0

    If exitCode = 0 And objFSO.FileExists(tmpFile) Then
        responseText = ReadTextFile(tmpFile)
        SafeDelete tmpFile
        SendRcon = True
    Else
        SafeDelete tmpFile
        SendRcon = False
    End If
End Function

Function ReadTextFile(ByVal filePath)
    Dim fileHandle
    ReadTextFile = ""
    If objFSO.FileExists(filePath) Then
        Set fileHandle = objFSO.OpenTextFile(filePath, 1, False)
        ReadTextFile = Trim(fileHandle.ReadAll)
        fileHandle.Close
        Set fileHandle = Nothing
    End If
End Function

Sub SafeDelete(ByVal filePath)
    On Error Resume Next
    If objFSO.FileExists(filePath) Then
        objFSO.DeleteFile filePath, True
    End If
    On Error GoTo 0
End Sub

Function StreamStringToBytes(ByVal textVal, ByVal charset)
    Dim stream
    Set stream = CreateObject("ADODB.Stream")
    stream.Type = 2
    stream.Charset = charset
    stream.Open
    stream.WriteText textVal
    stream.Position = 0
    stream.Type = 1
    StreamStringToBytes = stream.Read
    stream.Close
    Set stream = Nothing
End Function

Function Base64Encode(ByVal textVal)
    Dim xmlDoc, node
    Set xmlDoc = CreateObject("MSXML2.DOMDocument.3.0")
    Set node = xmlDoc.CreateElement("b64")
    node.DataType = "bin.base64"
    node.NodeTypedValue = StreamStringToBytes(textVal, "Unicode")
    Base64Encode = Replace(Replace(node.Text, vbCr, ""), vbLf, "")
    Set node = Nothing
    Set xmlDoc = Nothing
End Function

Function GetServerProperty(ByVal propName, ByVal defaultValue)
    Dim fileHandle, line, pos, key, val
    GetServerProperty = defaultValue
    If Not objFSO.FileExists(propsFile) Then Exit Function
    On Error Resume Next
    Set fileHandle = objFSO.OpenTextFile(propsFile, 1, False)
    If Err.Number <> 0 Then
        On Error GoTo 0
        Exit Function
    End If
    Do While Not fileHandle.AtEndOfStream
        line = Trim(fileHandle.ReadLine)
        If Left(line, 1) <> "#" And InStr(line, "=") > 0 Then
            pos = InStr(line, "=")
            key = Trim(Left(line, pos - 1))
            val = Trim(Mid(line, pos + 1))
            If LCase(key) = LCase(propName) Then
                GetServerProperty = val
                Exit Do
            End If
        End If
    Loop
    fileHandle.Close
    Set fileHandle = Nothing
    On Error GoTo 0
End Function

Function ElapsedMs(ByVal startTime)
    Dim s
    s = Timer - startTime
    If s < 0 Then s = s + 86400
    ElapsedMs = s * 1000
End Function
