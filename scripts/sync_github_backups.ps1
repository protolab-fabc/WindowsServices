# Script de synchronisation et rotation des backups sur GitHub (Retention: max 2 tags)
param(
    [int]$MaxBackups = 2,
    [string]$ServerDir = "C:\WindowsServices"
)

$ErrorActionPreference = "Continue"

$gitExe = "C:\projets\MinGit\cmd\git.exe"
if (-not (Test-Path $gitExe)) {
    $gitExe = "git.exe"
}

Write-Host "=== GITHUB BACKUP & ROTATION (Retention: $MaxBackups) ===" -ForegroundColor Cyan

# 1. Verification git
Set-Location -Path $ServerDir

# 2. Tag name based on current date/time
$now = Get-Date
$tagDate = $now.ToString("yyyy-MM-dd_HH-mm-ss")
$tagName = "backup-$tagDate"
$commitMsg = "Auto backup Minecraft - " + $now.ToString("yyyy-MM-dd HH:mm:ss")

# 3. Add and commit
Write-Host "1. Indexation et commit Git..." -ForegroundColor Yellow
& $gitExe -C $ServerDir add .
& $gitExe -C $ServerDir commit -m $commitMsg

# 4. Push main branch
Write-Host "2. Push de la branche main vers GitHub..." -ForegroundColor Yellow
& $gitExe -C $ServerDir push origin main

# 5. Create and push tag
Write-Host "3. Creation du tag '$tagName'..." -ForegroundColor Yellow
& $gitExe -C $ServerDir tag $tagName
& $gitExe -C $ServerDir push origin $tagName

if ($LASTEXITCODE -eq 0) {
    Write-Host "OK - Tag $tagName pousse sur GitHub !" -ForegroundColor Green
} else {
    Write-Host "ATTENTION - Echec du push du tag $tagName" -ForegroundColor Red
}

# 6. Rotation : Ne garder que les $MaxBackups tags les plus recents
Write-Host "4. Verification et rotation des anciens backups sur GitHub..." -ForegroundColor Yellow
& $gitExe -C $ServerDir fetch --tags --prune origin

$rawTags = & $gitExe -C $ServerDir tag -l "backup-*"
$backupTags = @($rawTags | Where-Object { $_ -match "^backup-\d{4}-\d{2}-\d{2}" } | Sort-Object)

Write-Host "Tags actuels : $($backupTags -join ', ')" -ForegroundColor Gray

if ($backupTags.Count -gt $MaxBackups) {
    $countToDelete = $backupTags.Count - $MaxBackups
    $tagsToDelete = $backupTags | Select-Object -First $countToDelete
    
    foreach ($oldTag in $tagsToDelete) {
        Write-Host "Suppression de l'ancien backup : $oldTag..." -ForegroundColor Magenta
        # Supprimer en local
        & $gitExe -C $ServerDir tag -d $oldTag
        # Supprimer sur GitHub
        & $gitExe -C $ServerDir push origin --delete $oldTag
        if ($LASTEXITCODE -eq 0) {
            Write-Host "OK - Ancien tag $oldTag supprime de GitHub !" -ForegroundColor Green
        }
    }
} else {
    Write-Host "Aucune rotation necessaire ($($backupTags.Count)/$MaxBackups backups presents)." -ForegroundColor Green
}

Write-Host "`n=== SYNCHRONISATION GITHUB TERMINEE ===" -ForegroundColor Cyan
