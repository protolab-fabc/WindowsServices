$ErrorActionPreference = "Stop"
try {
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument '//B "C:\WindowsServices\scripts\update-backup.vbs" /silent' -WorkingDirectory "C:\WindowsServices"
    $trigger = New-ScheduledTaskTrigger -Daily -At 01:00
    Register-ScheduledTask -TaskName "MinecraftDailyBackup" -Action $action -Trigger $trigger -Force
    Write-Output "SUCCESS: Tache planifiee MinecraftDailyBackup enregistree avec succes !"
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
