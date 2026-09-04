@echo off
chcp 65001 >nul
cd /d C:\WindowsServices\scripts
"C:\Users\Administrateur\AppData\Local\Programs\Python\Python312\python.exe" nozor_agent.py >> nozor_agent.log 2>&1
