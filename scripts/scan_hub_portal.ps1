$resList = @()
for ($x = 168; $x -le 175; $x++) {
    for ($y = 62; $y -le 68; $y++) {
        for ($z = -190; $z -le -186; $z++) {
            $isAir = & "$PSScriptRoot\rcon.ps1" -Command "execute in hub:lobby if block $x $y $z minecraft:air"
            if ($isAir -notmatch "passed") {
                $resList += "Block at $x $y $z"
            }
        }
    }
}
$resList | Out-File "$PSScriptRoot\hub_blocks.txt"
Write-Host "Scanned $($resList.Count) non-air blocks around Hub portal."
