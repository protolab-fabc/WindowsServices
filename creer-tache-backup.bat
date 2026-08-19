@echo off
:: Creation de la tache planifiee de backup quotidien Minecraft a 01h00
:: Clic droit -> "Executer en tant qu'administrateur"

cd /d "C:\WindowsServices"

echo ============================================================
echo   Installation de la Tache Planifiee de Sauvegarde (01:00)
echo ============================================================
echo.

schtasks /create /tn "MinecraftDailyBackup" /tr "wscript.exe //B \"C:\WindowsServices\scripts\update-backup.vbs\" /silent" /sc daily /st 01:00 /f /rl highest

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCES] La tache planifiee "MinecraftDailyBackup" a ete creee avec succes !
    echo Le serveur effectuera sa sauvegarde compresse chaque nuit a 01h00.
) else (
    echo.
    echo [ERREUR] Impossible de creer la tache. Veillez a executer ce fichier en tant qu'Administrateur.
)

echo.
pause
