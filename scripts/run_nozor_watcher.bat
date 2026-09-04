@echo off
chcp 65001 >nul
cd /d C:\WindowsServices
powershell.exe -ExecutionPolicy Bypass -File "C:\WindowsServices\scripts\nozor_watcher.ps1" >> "C:\WindowsServices\scripts\nozor_watcher.log" 2>&1
