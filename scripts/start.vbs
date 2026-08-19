Set objShell = CreateObject("WScript.Shell")
objShell.CurrentDirectory = "C:\WindowsServices"
Dim cmd
cmd = Chr(34) & "C:\Program Files\Eclipse Adoptium\jdk-25.0.2.10-hotspot\bin\java.exe" & Chr(34) & " -Xmx49G -Xms2G -XX:+UseG1GC -XX:G1PeriodicGCInterval=30000 -XX:G1PeriodicGCSystemLoadThreshold=0.0 -jar " & Chr(34) & "C:\WindowsServices\server.jar" & Chr(34) & " --nogui"
objShell.Run cmd, 0, False
