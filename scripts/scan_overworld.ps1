for ($x = -130; $x -le -126; $x++) {
    for ($y = 71; $y -le 75; $y++) {
        for ($z = -205; $z -le -200; $z++) {
            # Let's test if air
            $res = & "$PSScriptRoot\rcon.ps1" -Command "execute in minecraft:overworld if block $x $y $z minecraft:air"
            if ($res -notmatch "passed") {
                Write-Host "Non-air at $x $y $z"
            }
        }
    }
}
