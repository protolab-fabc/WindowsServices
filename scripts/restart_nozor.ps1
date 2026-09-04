# restart_nozor.ps1
# Script de redémarrage complet de Nozor (Agent Python + Watcher PowerShell)

Write-Host "=== REDEMARRAGE DE NOZOR ===" -ForegroundColor Cyan

# 1. Arrêt des anciens processus Nozor (spécifique aux runners)
$existing = Get-CimInstance Win32_Process | Where-Object {
    ($_.CommandLine -like "*nozor_agent.py*") -or
    ($_.CommandLine -like "*nozor_watcher.ps1*") -or
    ($_.CommandLine -like "*run_nozor_agent.bat*") -or
    ($_.CommandLine -like "*run_nozor_watcher.bat*")
}

if ($existing) {
    foreach ($p in $existing) {
        if ($p.CommandLine -notlike "*restart_nozor.ps1*") {
            Write-Host "Arret du processus PID $($p.ProcessId) ($($p.Name))..." -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 1
} else {
    Write-Host "Aucun ancien processus Nozor actif detecte." -ForegroundColor Gray
}

# 2. Lancement de Nozor Agent
Write-Host "Lancement de Nozor Agent via WMI..." -ForegroundColor Cyan
$agentResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine = 'cmd.exe /c "C:\WindowsServices\scripts\run_nozor_agent.bat"'
    CurrentDirectory = "C:\WindowsServices\scripts"
}

if ($agentResult.ReturnValue -eq 0) {
    Write-Host "-> Nozor Agent lance (PID cmd: $($agentResult.ProcessId))." -ForegroundColor Green
} else {
    Write-Host "-> Echec demarrage Nozor Agent (Code: $($agentResult.ReturnValue))." -ForegroundColor Red
}

# 3. Lancement de Nozor Watcher
Write-Host "Lancement de Nozor Watcher via WMI..." -ForegroundColor Cyan
$watcherResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine = 'cmd.exe /c "C:\WindowsServices\scripts\run_nozor_watcher.bat"'
    CurrentDirectory = "C:\WindowsServices\scripts"
}

if ($watcherResult.ReturnValue -eq 0) {
    Write-Host "-> Nozor Watcher lance (PID cmd: $($watcherResult.ProcessId))." -ForegroundColor Green
} else {
    Write-Host "-> Echec demarrage Nozor Watcher (Code: $($watcherResult.ReturnValue))." -ForegroundColor Red
}

# 4. Attente et verification
Write-Host "Initialisation (3 secondes)..." -ForegroundColor Gray
Start-Sleep -Seconds 3

# Verification port 8090
$portCheck = Get-NetTCPConnection -LocalPort 8090 -ErrorAction SilentlyContinue
if ($portCheck) {
    Write-Host "-> Port 8090 ACTIF (PID $($portCheck.OwningProcess)) !" -ForegroundColor Green
} else {
    Write-Host "-> ATTENTION: Port 8090 non detecte pour le moment." -ForegroundColor Yellow
}

# Verification des processus actifs
$active = Get-CimInstance Win32_Process | Where-Object {
    ($_.CommandLine -like "*nozor_agent.py*") -or
    ($_.CommandLine -like "*nozor_watcher.ps1*") -or
    ($_.CommandLine -like "*run_nozor*")
}

Write-Host "`nProcessus Nozor en execution :" -ForegroundColor Cyan
foreach ($proc in $active) {
    if ($proc.CommandLine -notlike "*restart_nozor.ps1*") {
        Write-Host "  - PID $($proc.ProcessId): $($proc.Name) ($($proc.CommandLine))" -ForegroundColor White
    }
}

Write-Host "=== REDEMARRAGE TERMINE ===" -ForegroundColor Cyan
