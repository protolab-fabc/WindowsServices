for ($x = -131; $x -le -125; $x++) {
    for ($y = 70; $y -le 76; $y++) {
        $isAir = & "$PSScriptRoot\rcon.ps1" -Command "execute in minecraft:overworld if block $x $y -200 minecraft:air"
        if ($isAir -notmatch "passed") {
            Write-Host "Solid block at $x $y -200"
        }
    }
}
