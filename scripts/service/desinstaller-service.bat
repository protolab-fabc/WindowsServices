@echo off
:: Script de desinstallation du Service Windows
:: A executer par clic-droit -> "Executer en tant qu'administrateur"

cd /d "C:\WindowsServices\scripts"
echo Desinstallation du service Windows...
"%~dp0DriverService.exe" -uninstall

echo.
echo Service desinstalle avec succes.
pause
