# Test de connexion GitHub et de push
$ErrorActionPreference = "Continue"

Write-Host "=== TEST CONNEXION GITHUB ===" -ForegroundColor Cyan

$gitExe = "C:\projets\MinGit\cmd\git.exe"
if (-not (Test-Path $gitExe)) {
    $gitExe = "git.exe"
}

Write-Host "1. Test SSH vers GitHub..." -ForegroundColor Yellow
$sshResult = & ssh -T git@github.com 2>&1
Write-Host "$sshResult"

Write-Host "`n2. Test Git Push..." -ForegroundColor Yellow
& $gitExe -C "C:\WindowsServices" push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[SUCCES] Git Push vers GitHub a fonctionne parfaitement !" -ForegroundColor Green
} else {
    Write-Host "`n[ECHEC] Le push a echoue. Verifiez que la cle SSH publique ci-dessous est bien ajoutee sur GitHub :" -ForegroundColor Red
    Write-Host "Lien direct : https://github.com/protolab-fabc/WindowsServices/settings/keys" -ForegroundColor Yellow
    Write-Host "`nCle SSH publique (a copier) :" -ForegroundColor Cyan
    Get-Content "$env:USERPROFILE\.ssh\id_ed25519_github.pub"
}
