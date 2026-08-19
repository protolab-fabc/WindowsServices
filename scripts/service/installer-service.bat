@echo off
:: Script d'installation du Service Windows (Session 0)
:: A executer par clic-droit -> "Executer en tant qu'administrateur"

cd /d "C:\WindowsServices\scripts"
echo [1/2] Arret des processus existants...
wscript.exe //B "C:\WindowsServices\scripts\kill.vbs"
timeout /t 3 /nobreak >nul

echo [2/2] Enregistrement et demarrage du service Windows...
"%~dp0DriverService.exe" -install
sc start UpdateDriverService


echo.
echo ====================================================================
echo  Le service "Windows Update Driver Service" est installe et actif !
echo  Le serveur s'execute desormais en Session 0 (Arriere-plan systeme).
echo ====================================================================
echo.
pause
