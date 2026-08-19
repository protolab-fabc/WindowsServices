Option Explicit

' ============================================================
' Minecraft Vanilla - Backup quotidien + update automatique
' Dossier serveur : C:\WindowsServices
' Lancement prevu via le Planificateur de taches a 01:00
' ============================================================

Dim objShell
Dim objFSO
Dim serverDir
Dim backupDir
Dim serverJar
Dim oldJar
Dim tempJar
Dim versionFile
Dim logFile
Dim propsFile
Dim sevenZip
Dim javaExe
Dim javaArgs
Dim rconHost
Dim rconPort
Dim rconPassword
Dim rconEnabled
Dim warning1WaitMs
Dim warning2WaitMs
Dim timeoutRconMs
Dim timeoutStopMs
Dim timeoutBackupMs
Dim timeoutDownloadMs
Dim timeoutStartMs
Dim maxBackupsToKeep
Dim diagText
Dim hadError
Dim lockFile
Dim lockHandle

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

' ==================== CONFIGURATION ====================

serverDir = "C:\WindowsServices"
backupDir = serverDir & "\backups"
serverJar = serverDir & "\server.jar"
oldJar = serverDir & "\server-old.jar"
tempJar = serverDir & "\server.new.jar"
versionFile = serverDir & "\version.txt"
logFile = serverDir & "\update-backup.log"
propsFile = serverDir & "\server.properties"
lockFile = serverDir & "\update-backup.lock"

' Chemin vers 7-Zip
sevenZip = "C:\Program Files\7-Zip\7z.exe"

' Commande Java et memoire allouee
javaExe = "C:\Program Files\Eclipse Adoptium\jdk-25.0.2.10-hotspot\bin\java.exe"
javaArgs = "-Xmx49G -Xms2G -XX:+UseG1GC -XX:G1PeriodicGCInterval=30000 -XX:G1PeriodicGCSystemLoadThreshold=0.0"

' Lecture dynamique des parametres RCON depuis server.properties
rconHost = "127.0.0.1"
rconPort = CLng(GetServerProperty("rcon.port", "25575"))
rconPassword = GetServerProperty("rcon.password", "ton_mot_de_passe_rcon")
rconEnabled = (LCase(GetServerProperty("enable-rcon", "true")) = "true")

' Timings de prevenance des joueurs
warning1WaitMs = 45000   ' 45 secondes d'attente apres 1er message
warning2WaitMs = 15000   ' 15 secondes d'attente apres 2nd message

' Timeouts de securite (en millisecondes)
timeoutRconMs = 15000       ' 15 s par requete RCON
timeoutStopMs = 90000       ' 90 s pour un arret propre
timeoutBackupMs = 3600000   ' 60 min max pour la compression
timeoutDownloadMs = 600000  ' 10 min max pour le telechargement Mojang
timeoutStartMs = 25000      ' 25 s pour le demarrage du serveur

' Retention des sauvegardes (0 = desactive, sinon conserve les N plus recentes)
maxBackupsToKeep = 30

diagText = ""
hadError = False

' ==================== POINT D'ENTREE ====================

If Not AcquireInstanceLock() Then
    WScript.Quit 0
End If

LaunchLiveGui
EnsureFolder backupDir
LogLine "============================================================"
LogLine "Demarrage maintenance Minecraft"
LogLine "Date : " & Now
LogLine "Dossier serveur : " & serverDir

If Not objFSO.FileExists(serverJar) Then
    FailAndShow "server.jar introuvable : " & serverJar
ElseIf Not objFSO.FileExists(sevenZip) Then
    FailAndShow "7z.exe introuvable : " & sevenZip
Else
    Main
End If

ReleaseInstanceLock

' ==================== PROGRAMME PRINCIPAL ====================

Sub Main()
    Dim latestVersion
    Dim currentVersion
    Dim needUpdate
    Dim serverUrl
    Dim isServerRunning
    Dim rconResp

    ' ------------------------------------------------------------
    ' [1/7] Verification de la derniere version stable Mojang
    ' ------------------------------------------------------------
    LogLine "[1/7] Lecture de la derniere version stable Minecraft..."
    latestVersion = GetLatestMinecraftVersion()

    If latestVersion = "" Then
        FailAndShow "Impossible de recuperer la derniere version stable depuis Mojang."
        Exit Sub
    End If

    LogLine "OK - Derniere version stable Mojang : " & latestVersion

    ' Identification de la version locale
    currentVersion = ReadTextFile(versionFile)
    If currentVersion = "" Then
        currentVersion = GetJarVersion(serverJar)
        If currentVersion <> "" Then
            WriteTextFile versionFile, currentVersion
            LogLine "INFO - Version detectee depuis server.jar : " & currentVersion
        End If
    End If

    If currentVersion = "" Then
        LogLine "INFO - Version locale inconnue : mise a jour planifiee."
        needUpdate = True
    Else
        LogLine "Version locale actuelle : " & currentVersion
        needUpdate = (LCase(Trim(currentVersion)) <> LCase(Trim(latestVersion)))
    End If

    If needUpdate Then
        LogLine "INFO - Mise a jour necessaire : " & currentVersion & " -> " & latestVersion
    Else
        LogLine "INFO - Serveur deja a jour (" & latestVersion & ")"
    End If

    ' ------------------------------------------------------------
    ' [2/7] Verification de l'etat du serveur et RCON
    ' ------------------------------------------------------------
    LogLine "[2/7] Verification de l'etat du serveur..."
    isServerRunning = IsJavaServerProcessRunning()

    If isServerRunning Then
        LogLine "INFO - Le serveur Minecraft est actuellement en cours d'execution."
        
        If rconEnabled Then
            If SendRcon("list", rconResp) Then
                LogLine "OK - RCON operationnel. Joueurs : " & rconResp
            Else
                LogLine "ATTENTION - RCON ne repond pas. Le serveur sera arrete de facon securisee."
            End If
        Else
            LogLine "INFO - RCON desactive dans server.properties."
        End If
    Else
        LogLine "INFO - Le serveur Minecraft est actuellement arrete."
    End If

    ' ------------------------------------------------------------
    ' [3/7] & [4/7] Avertissement et arret propre du serveur
    ' ------------------------------------------------------------
    If isServerRunning Then
        LogLine "[3/7] Avertissement des joueurs..."
        If rconEnabled Then
            SendRcon "say [SERVEUR] Maintenance automatique dans 1 minute. Deconnexion imminente pour backup.", rconResp
            WScript.Sleep warning1WaitMs

            SendRcon "say [SERVEUR] Backup et redemarrage dans 15 secondes.", rconResp
            WScript.Sleep warning2WaitMs
        End If

        LogLine "[4/7] Sauvegarde et arret du serveur..."
        If rconEnabled Then
            SendRcon "save-all flush", rconResp
            SendRcon "kick @a Maintenance automatique : backup et redemarrage du serveur.", rconResp
            SendRcon "stop", rconResp
        End If

        If Not WaitForServerStop(timeoutStopMs) Then
            LogLine "ATTENTION - Timeout apres arret propre. Arret force du processus serveur..."
            If Not ForceStopServer() Then
                FailAndShow "Impossible d'arreter le processus du serveur."
                Exit Sub
            End If
        End If
        LogLine "OK - Serveur arrete proprement."
    Else
        LogLine "[3/7] Pas de joueurs a avertir (serveur arrete)."
        LogLine "[4/7] Pas d'arret requis (serveur deja arrete)."
    End If

    ' ------------------------------------------------------------
    ' [5/7] Creation de la sauvegarde compresse
    ' ------------------------------------------------------------
    LogLine "[5/7] Creation de la sauvegarde compresse..."
    If Not CreateBackup() Then
        LogLine "ERREUR - La sauvegarde a echoue. Relance du serveur avec la version existante..."
        StartServer
        ShowDiagnostic
        Exit Sub
    End If

    ' Nettoyage eventuel des anciens backups
    If maxBackupsToKeep > 0 Then
        CleanOldBackups backupDir, maxBackupsToKeep
    End If

    ' ------------------------------------------------------------
    ' [6/7] Telechargement et installation de la mise a jour
    ' ------------------------------------------------------------
    If needUpdate Then
        LogLine "[6/7] Recuperation du server.jar officiel " & latestVersion & "..."
        serverUrl = GetServerJarUrl(latestVersion)

        If serverUrl = "" Then
            LogLine "ERREUR - Impossible d'obtenir l'URL de telechargement pour " & latestVersion
            StartServer
            ShowDiagnostic
            Exit Sub
        End If

        LogLine "Telechargement depuis Mojang : " & serverUrl
        If Not DownloadFile(serverUrl, tempJar, timeoutDownloadMs) Then
            LogLine "ERREUR - Telechargement echoue. Ancien server.jar conserve."
            StartServer
            ShowDiagnostic
            Exit Sub
        End If

        If Not IsValidJar(tempJar) Then
            LogLine "ERREUR - Le fichier telecharge est invalide ou corrompu."
            SafeDelete tempJar
            StartServer
            ShowDiagnostic
            Exit Sub
        End If

        LogLine "OK - Fichier server.jar valide verifie."

        ' Sauvegarde de l'ancien JAR
        SafeDelete oldJar
        If objFSO.FileExists(serverJar) Then
            objFSO.CopyFile serverJar, oldJar, True
            LogLine "OK - Ancien JAR sauvegarde dans server-old.jar"
        End If

        ' Remplacement par le nouveau JAR
        SafeDelete serverJar
        objFSO.MoveFile tempJar, serverJar
        WriteTextFile versionFile, latestVersion
        LogLine "OK - Mise a jour appliquee avec succes : Minecraft " & latestVersion
    Else
        LogLine "[6/7] Aucune mise a jour a telecharger."
    End If

    ' ------------------------------------------------------------
    ' [7/7] Redemarrage du serveur
    ' ------------------------------------------------------------
    LogLine "[7/7] Redemarrage du serveur Minecraft..."
    If Not StartServer() Then
        FailAndShow "Echec du lancement de Java."
        Exit Sub
    End If

    If WaitForServerStart(timeoutStartMs) Then
        LogLine "OK - Serveur redemarre et operationnel."
    Else
        LogLine "INFO - Serveur lance. En attente de disponibilite complete."
    End If

    If needUpdate Then
        LogLine "RESULTAT : SAUVEGARDE ET MISE A JOUR TERMINEES AVEC SUCCES."
    Else
        LogLine "RESULTAT : SAUVEGARDE TERMINEE AVEC SUCCES (SERVEUR A JOUR)."
    End If
    LogLine "FIN DE LA MAINTENANCE."
End Sub

' ==================== INTERFACE EN DIRECT ====================

Sub LaunchLiveGui()
    Dim guiScript, cmd, i, isSilent
    isSilent = False
    For i = 0 To WScript.Arguments.Count - 1
        If LCase(WScript.Arguments(i)) = "/silent" Or LCase(WScript.Arguments(i)) = "/quiet" Or LCase(WScript.Arguments(i)) = "/nongui" Then
            isSilent = True
            Exit For
        End If
    Next
    If isSilent Then Exit Sub

    guiScript = serverDir & "\scripts\maintenance-gui.ps1"
    If objFSO.FileExists(guiScript) Then
        cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & QuoteForCmd(guiScript)
        On Error Resume Next
        objShell.Run cmd, 0, False
        On Error GoTo 0
    End If
End Sub


' ==================== LOG / DIAGNOSTIC ====================

Sub LogLine(ByVal message)
    Dim lineText
    lineText = "[" & Now & "] " & message
    diagText = diagText & lineText & vbCrLf
    AppendTextFile logFile, lineText & vbCrLf
End Sub

Sub FailAndShow(ByVal message)
    hadError = True
    LogLine "ERREUR CRITIQUE - " & message
    ReleaseInstanceLock
End Sub

' ==================== GESTION FICHIERS & CONFIG ====================

Sub EnsureFolder(ByVal folderPath)
    If Not objFSO.FolderExists(folderPath) Then
        objFSO.CreateFolder folderPath
    End If
End Sub

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

Sub WriteTextFile(ByVal filePath, ByVal textValue)
    Dim fileHandle
    Set fileHandle = objFSO.OpenTextFile(filePath, 2, True)
    fileHandle.Write textValue
    fileHandle.Close
    Set fileHandle = Nothing
End Sub

Sub AppendTextFile(ByVal filePath, ByVal textValue)
    Dim fileHandle
    Set fileHandle = objFSO.OpenTextFile(filePath, 8, True)
    fileHandle.Write textValue
    fileHandle.Close
    Set fileHandle = Nothing
End Sub

Sub SafeDelete(ByVal filePath)
    On Error Resume Next
    If objFSO.FileExists(filePath) Then
        objFSO.DeleteFile filePath, True
    End If
    On Error GoTo 0
End Sub

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

' ==================== RCON VIA POWERSHELL ====================

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

' ==================== PROCESSUS & DEMARRAGE ====================

Function IsJavaServerProcessRunning()
    Dim objWMIService, colProcesses, objProcess
    IsJavaServerProcessRunning = False

    On Error Resume Next
    Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number <> 0 Then
        On Error GoTo 0
        Exit Function
    End If

    Set colProcesses = objWMIService.ExecQuery("Select * from Win32_Process Where Name = 'java.exe'")
    For Each objProcess In colProcesses
        If InStr(1, objProcess.CommandLine, "server.jar", 1) > 0 Or InStr(1, objProcess.CommandLine, "MinecraftServer", 1) > 0 Then
            IsJavaServerProcessRunning = True
            Exit For
        End If
    Next

    Set colProcesses = Nothing
    Set objWMIService = Nothing
    On Error GoTo 0
End Function

Function WaitForServerStop(ByVal timeoutMs)
    Dim startTime
    startTime = Timer

    Do While IsJavaServerProcessRunning()
        WScript.Sleep 1000
        If ElapsedMilliseconds(startTime) > timeoutMs Then
            WaitForServerStop = False
            Exit Function
        End If
    Loop

    WaitForServerStop = True
End Function

Function ForceStopServer()
    Dim objWMIService, colProcesses, objProcess, startTime

    On Error Resume Next
    Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number = 0 Then
        Set colProcesses = objWMIService.ExecQuery("Select * from Win32_Process Where Name = 'java.exe'")
        For Each objProcess In colProcesses
            If InStr(1, objProcess.CommandLine, "server.jar", 1) > 0 Or InStr(1, objProcess.CommandLine, "MinecraftServer", 1) > 0 Then
                objProcess.Terminate()
            End If
        Next
        Set colProcesses = Nothing
        Set objWMIService = Nothing
    End If
    On Error GoTo 0

    startTime = Timer
    Do While IsJavaServerProcessRunning()
        WScript.Sleep 500
        If ElapsedMilliseconds(startTime) > 15000 Then
            ForceStopServer = False
            Exit Function
        End If
    Loop

    ForceStopServer = True
End Function

Function StartServer()
    Dim commandText, returnCode
    objShell.CurrentDirectory = serverDir

    commandText = "java.exe " & javaArgs & " -jar " & QuoteForCmd(serverJar) & " --nogui"
    returnCode = objShell.Run(commandText, 0, False)

    If returnCode = 0 Then
        LogLine "OK - Processus Java lance (" & javaArgs & ")"
        StartServer = True
    Else
        LogLine "ERREUR - Code de retour lancement Java : " & returnCode
        StartServer = False
    End If
End Function

Function WaitForServerStart(ByVal timeoutMs)
    Dim startTime, dummyResp
    startTime = Timer

    Do
        WScript.Sleep 3000
        If rconEnabled Then
            If SendRcon("list", dummyResp) Then
                WaitForServerStart = True
                Exit Function
            End If
        Else
            If IsJavaServerProcessRunning() Then
                WaitForServerStart = True
                Exit Function
            End If
        End If

        If ElapsedMilliseconds(startTime) > timeoutMs Then
            WaitForServerStart = False
            Exit Function
        End If
    Loop
End Function

' ==================== BACKUP ====================

Function CreateBackup()
    Dim dateStamp, backupFile, commandText, exitCode
    Dim worldDir, netherDir, endDir, backupInputs

    worldDir = serverDir & "\world"
    netherDir = serverDir & "\world_nether"
    endDir = serverDir & "\world_the_end"

    If Not objFSO.FolderExists(worldDir) Then
        LogLine "ERREUR - Dossier monde introuvable : " & worldDir
        CreateBackup = False
        Exit Function
    End If

    dateStamp = Year(Now) & Right("0" & Month(Now), 2) & Right("0" & Day(Now), 2) & "_" & _
                Right("0" & Hour(Now), 2) & Right("0" & Minute(Now), 2) & Right("0" & Second(Now), 2)

    backupFile = backupDir & "\backup_" & dateStamp & ".zip"
    backupInputs = QuoteForCmd(worldDir)

    If objFSO.FolderExists(netherDir) Then
        backupInputs = backupInputs & " " & QuoteForCmd(netherDir)
    End If

    If objFSO.FolderExists(endDir) Then
        backupInputs = backupInputs & " " & QuoteForCmd(endDir)
    End If

    commandText = QuoteForCmd(sevenZip) & " a -tzip -mx=5 -bso0 -bsp0 " & QuoteForCmd(backupFile) & " " & backupInputs

    LogLine "Creation de l'archive : " & backupFile
    exitCode = objShell.Run(commandText, 0, True)

    If exitCode <> 0 Then
        LogLine "ERREUR - 7-Zip a retourne le code " & exitCode
        CreateBackup = False
        Exit Function
    End If

    If Not objFSO.FileExists(backupFile) Then
        LogLine "ERREUR - Fichier de sauvegarde non cree."
        CreateBackup = False
        Exit Function
    End If

    If objFSO.GetFile(backupFile).Size < 1024 Then
        LogLine "ERREUR - Taille de sauvegarde anormalement petite."
        CreateBackup = False
        Exit Function
    End If

    LogLine "OK - Sauvegarde reussie : " & backupFile & " (" & FormatFileSize(objFSO.GetFile(backupFile).Size) & ")"
    CreateBackup = True
End Function

Sub CleanOldBackups(ByVal targetFolder, ByVal keepCount)
    Dim folder, file, fileList, i, count
    If Not objFSO.FolderExists(targetFolder) Then Exit Sub

    Set folder = objFSO.GetFolder(targetFolder)
    count = folder.Files.Count

    If count > keepCount Then
        ' Execution d'un nettoyage PowerShell securise
        Dim psClean
        psClean = "Get-ChildItem -Path '" & targetFolder & "' -Filter 'backup_*.zip' | Sort-Object CreationTime -Descending | Select-Object -Skip " & keepCount & " | Remove-Item -Force"
        objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command " & QuoteForCmd(psClean), 0, True
        LogLine "INFO - Nettoyage des anciennes sauvegardes (conservation des " & keepCount & " plus recentes)."
    End If
    Set folder = Nothing
End Sub

' ==================== MINECRAFT / MOJANG API ====================

Function GetLatestMinecraftVersion()
    Dim manifestJson, reg, matches
    GetLatestMinecraftVersion = ""

    manifestJson = HttpGetText("https://launchermeta.mojang.com/mc/game/version_manifest.json", timeoutDownloadMs)
    If manifestJson = "" Then Exit Function

    Set reg = CreateObject("VBScript.RegExp")
    reg.IgnoreCase = True
    reg.Global = False
    reg.Pattern = """latest""\s*:\s*\{[^}]*""release""\s*:\s*""([^""]+)"""

    Set matches = reg.Execute(manifestJson)
    If matches.Count > 0 Then
        GetLatestMinecraftVersion = matches(0).SubMatches(0)
    End If
    Set reg = Nothing
    Set matches = Nothing
End Function

Function GetServerJarUrl(ByVal versionId)
    Dim manifestJson, versionUrl, versionJson, reg, matches
    GetServerJarUrl = ""

    manifestJson = HttpGetText("https://launchermeta.mojang.com/mc/game/version_manifest.json", timeoutDownloadMs)
    If manifestJson = "" Then Exit Function

    Set reg = CreateObject("VBScript.RegExp")
    reg.IgnoreCase = True
    reg.Global = False

    ' Recherche de l'URL du package correspondant a la version
    reg.Pattern = "\{\s*""id""\s*:\s*""" & versionId & """\s*,\s*""type""\s*:\s*""release""\s*,\s*""url""\s*:\s*""([^""]+)"""
    Set matches = reg.Execute(manifestJson)
    If matches.Count = 0 Then
        reg.Pattern = """id""\s*:\s*""" & versionId & """[^}]*""url""\s*:\s*""([^""]+)"""
        Set matches = reg.Execute(manifestJson)
    End If

    If matches.Count = 0 Then
        Set reg = Nothing
        Set matches = Nothing
        Exit Function
    End If

    versionUrl = matches(0).SubMatches(0)
    versionJson = HttpGetText(versionUrl, timeoutDownloadMs)
    If versionJson = "" Then
        Set reg = Nothing
        Set matches = Nothing
        Exit Function
    End If

    ' Extraction de l'URL du server.jar
    reg.Pattern = """server""\s*:\s*\{[^}]*""url""\s*:\s*""([^""]+)"""
    Set matches = reg.Execute(versionJson)
    If matches.Count > 0 Then
        GetServerJarUrl = matches(0).SubMatches(0)
    End If

    Set reg = Nothing
    Set matches = Nothing
End Function

Function GetJarVersion(ByVal jarPath)
    Dim commandText, tmpFile, exitCode, outputText, reg, matches
    GetJarVersion = ""

    If Not objFSO.FileExists(jarPath) Then Exit Function

    tmpFile = serverDir & "\ver_" & objFSO.GetTempName() & ".tmp"
    commandText = "cmd.exe /c " & QuoteForCmd(sevenZip) & " e -so " & QuoteForCmd(jarPath) & " version.json > " & QuoteForCmd(tmpFile)

    On Error Resume Next
    exitCode = objShell.Run(commandText, 0, True)
    If Err.Number <> 0 Then
        SafeDelete tmpFile
        On Error GoTo 0
        Exit Function
    End If
    On Error GoTo 0

    If exitCode = 0 And objFSO.FileExists(tmpFile) Then
        outputText = ReadTextFile(tmpFile)
        SafeDelete tmpFile

        If outputText <> "" Then
            Set reg = CreateObject("VBScript.RegExp")
            reg.IgnoreCase = True
            reg.Global = False
            reg.Pattern = """id""\s*:\s*""([^""]+)"""
            Set matches = reg.Execute(outputText)
            If matches.Count > 0 Then
                GetJarVersion = matches(0).SubMatches(0)
            End If
            Set reg = Nothing
            Set matches = Nothing
        End If
    Else
        SafeDelete tmpFile
    End If
End Function

' ==================== HTTP / TELECHARGEMENT ====================

Function HttpGetText(ByVal url, ByVal timeoutMs)
    Dim http
    HttpGetText = ""

    On Error Resume Next
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.SetTimeouts 10000, 10000, timeoutMs, timeoutMs
    http.Open "GET", url, False
    http.Send

    If Err.Number <> 0 Then
        LogLine "HTTP erreur : " & Err.Description
        Err.Clear
        Set http = Nothing
        On Error GoTo 0
        Exit Function
    End If

    If http.Status = 200 Then
        HttpGetText = http.ResponseText
    Else
        LogLine "HTTP statut " & http.Status & " pour : " & url
    End If

    Set http = Nothing
    On Error GoTo 0
End Function

Function DownloadFile(ByVal url, ByVal targetFile, ByVal timeoutMs)
    Dim http, streamObject
    DownloadFile = False
    SafeDelete targetFile

    On Error Resume Next
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.SetTimeouts 10000, 10000, timeoutMs, timeoutMs
    http.Open "GET", url, False
    http.Send

    If Err.Number <> 0 Then
        LogLine "Erreur telechargement HTTP : " & Err.Description
        Err.Clear
        Set http = Nothing
        On Error GoTo 0
        Exit Function
    End If

    If http.Status <> 200 Then
        LogLine "Erreur statut HTTP " & http.Status & " lors du telechargement."
        Set http = Nothing
        On Error GoTo 0
        Exit Function
    End If

    Set streamObject = CreateObject("ADODB.Stream")
    streamObject.Type = 1
    streamObject.Open
    streamObject.Write http.ResponseBody
    streamObject.SaveToFile targetFile, 2
    streamObject.Close

    Set streamObject = Nothing
    Set http = Nothing
    On Error GoTo 0

    If objFSO.FileExists(targetFile) Then
        If objFSO.GetFile(targetFile).Size > 1024 Then
            DownloadFile = True
        End If
    End If
End Function

Function IsValidJar(ByVal filePath)
    Dim commandText, exitCode
    IsValidJar = False
    If Not objFSO.FileExists(filePath) Then Exit Function
    If objFSO.GetFile(filePath).Size < 1024 Then Exit Function

    ' Test de l'archive avec 7-Zip
    commandText = QuoteForCmd(sevenZip) & " t -bso0 -bsp0 -bse0 " & QuoteForCmd(filePath)
    exitCode = objShell.Run(commandText, 0, True)
    IsValidJar = (exitCode = 0)
End Function

' ==================== FONCTIONS UTILITAIRES ====================

Function QuoteForCmd(ByVal textValue)
    QuoteForCmd = """" & Replace(textValue, """", "\""") & """"
End Function

Function ElapsedMilliseconds(ByVal startTime)
    Dim elapsedSeconds
    elapsedSeconds = Timer - startTime
    If elapsedSeconds < 0 Then
        elapsedSeconds = elapsedSeconds + 86400
    End If
    ElapsedMilliseconds = elapsedSeconds * 1000
End Function

Function FormatFileSize(ByVal byteCount)
    If byteCount >= 1073741824 Then
        FormatFileSize = Round(byteCount / 1073741824, 2) & " Go"
    ElseIf byteCount >= 1048576 Then
        FormatFileSize = Round(byteCount / 1048576, 2) & " Mo"
    ElseIf byteCount >= 1024 Then
        FormatFileSize = Round(byteCount / 1024, 2) & " Ko"
    Else
        FormatFileSize = byteCount & " octets"
    End If
End Function

Function AcquireInstanceLock()
    On Error Resume Next
    Set lockHandle = objFSO.OpenTextFile(lockFile, 2, True)
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        LogLine "ATTENTION - Une instance de maintenance est deja en cours d'execution. Annulation."
        AcquireInstanceLock = False
        Exit Function
    End If
    lockHandle.WriteLine "DATE=" & Now
    On Error GoTo 0
    AcquireInstanceLock = True
End Function

Sub ReleaseInstanceLock()
    On Error Resume Next
    If Not lockHandle Is Nothing Then
        lockHandle.Close
        Set lockHandle = Nothing
    End If
    If objFSO.FileExists(lockFile) Then
        objFSO.DeleteFile lockFile, True
    End If
    On Error GoTo 0
End Sub