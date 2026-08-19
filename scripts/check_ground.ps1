for ($y = 55; $y -le 65; $y++) {
    $res = & "$PSScriptRoot\rcon.ps1" -Command "execute in hub:lobby if block 171 $y -186 minecraft:air"
    if ($res -notmatch "passed") {
        Write-Host "Solid block at 171 $y -186"
    }
}
