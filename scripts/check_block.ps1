$blocks = @('stone', 'obsidian', 'crying_obsidian', 'deepslate', 'polished_andesite', 'smooth_stone', 'oak_planks', 'mossy_cobblestone', 'cobblestone', 'dirt', 'grass_block')
foreach ($b in $blocks) {
    $res = & "$PSScriptRoot\rcon.ps1" -Command "execute in minecraft:overworld if block -130 72 -200 $b"
    if ($res -match "passed") {
        Write-Host "-130 72 -200 is $b"
        break
    }
}
