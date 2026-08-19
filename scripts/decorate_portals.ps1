$hubCommands = @(
    # --- Hub Portal Decorations (X=171..172, Y=63..65, Z=-188) ---
    # Base stairs
    "execute in hub:lobby run setblock 169 63 -188 polished_blackstone_brick_stairs[facing=west,half=bottom]",
    "execute in hub:lobby run setblock 174 63 -188 polished_blackstone_brick_stairs[facing=east,half=bottom]",
    "execute in hub:lobby run setblock 169 63 -187 polished_blackstone_brick_stairs[facing=south,half=bottom]",
    "execute in hub:lobby run setblock 174 63 -187 polished_blackstone_brick_stairs[facing=south,half=bottom]",
    
    # Side walls / pillars
    "execute in hub:lobby run setblock 169 64 -188 polished_blackstone_brick_wall",
    "execute in hub:lobby run setblock 169 65 -188 polished_blackstone_brick_wall",
    "execute in hub:lobby run setblock 174 64 -188 polished_blackstone_brick_wall",
    "execute in hub:lobby run setblock 174 65 -188 polished_blackstone_brick_wall",

    # Top side brackets
    "execute in hub:lobby run setblock 169 66 -188 polished_blackstone_brick_stairs[facing=west,half=top]",
    "execute in hub:lobby run setblock 174 66 -188 polished_blackstone_brick_stairs[facing=east,half=top]",

    # Top pediment
    "execute in hub:lobby run setblock 170 67 -188 polished_blackstone_brick_stairs[facing=east,half=bottom]",
    "execute in hub:lobby run setblock 171 67 -188 polished_blackstone_brick_slab",
    "execute in hub:lobby run setblock 172 67 -188 polished_blackstone_brick_slab",
    "execute in hub:lobby run setblock 173 67 -188 polished_blackstone_brick_stairs[facing=west,half=bottom]",

    # Hanging soul lanterns
    "execute in hub:lobby run setblock 169 66 -187 chain",
    "execute in hub:lobby run setblock 169 65 -187 soul_lantern[hanging=true]",
    "execute in hub:lobby run setblock 174 66 -187 chain",
    "execute in hub:lobby run setblock 174 65 -187 soul_lantern[hanging=true]",

    # Glowing Sign
    'execute in hub:lobby run setblock 170 64 -187 oak_wall_sign[facing=south]{front_text:{has_glowing_text:1b,color:"green",messages:[''{"text":"✦ SURVIE ✦","bold":true,"color":"green"}'',''{"text":"Monde Principal","color":"dark_green"}'',''{"text":"Entrez pour jouer","color":"gray"}'',''{"text":"✦ ✦ ✦","color":"green"}''}}'
)

$overworldCommands = @(
    # --- Overworld Portal Decorations (X=-129..-127, Y=72..75, Z=-200) ---
    # Base stairs
    "execute in minecraft:overworld run setblock -131 72 -200 mossy_stone_brick_stairs[facing=west,half=bottom]",
    "execute in minecraft:overworld run setblock -125 72 -200 mossy_stone_brick_stairs[facing=east,half=bottom]",
    "execute in minecraft:overworld run setblock -131 72 -199 stone_brick_stairs[facing=south,half=bottom]",
    "execute in minecraft:overworld run setblock -125 72 -199 stone_brick_stairs[facing=south,half=bottom]",

    # Side walls
    "execute in minecraft:overworld run setblock -131 73 -200 stone_brick_wall",
    "execute in minecraft:overworld run setblock -131 74 -200 mossy_stone_brick_wall",
    "execute in minecraft:overworld run setblock -131 75 -200 stone_brick_wall",

    "execute in minecraft:overworld run setblock -125 73 -200 stone_brick_wall",
    "execute in minecraft:overworld run setblock -125 74 -200 mossy_stone_brick_wall",
    "execute in minecraft:overworld run setblock -125 75 -200 stone_brick_wall",

    # Top side brackets
    "execute in minecraft:overworld run setblock -131 76 -200 stone_brick_stairs[facing=west,half=top]",
    "execute in minecraft:overworld run setblock -125 76 -200 stone_brick_stairs[facing=east,half=top]",

    # Top pediment
    "execute in minecraft:overworld run setblock -130 77 -200 stone_brick_stairs[facing=east,half=bottom]",
    "execute in minecraft:overworld run setblock -129 77 -200 stone_brick_slab",
    "execute in minecraft:overworld run setblock -128 77 -200 chiseled_stone_bricks",
    "execute in minecraft:overworld run setblock -127 77 -200 stone_brick_slab",
    "execute in minecraft:overworld run setblock -126 77 -200 stone_brick_stairs[facing=west,half=bottom]",

    # Hanging lanterns
    "execute in minecraft:overworld run setblock -131 76 -199 chain",
    "execute in minecraft:overworld run setblock -131 75 -199 lantern[hanging=true]",
    "execute in minecraft:overworld run setblock -125 76 -199 chain",
    "execute in minecraft:overworld run setblock -125 75 -199 lantern[hanging=true]",

    # Glowing Sign
    'execute in minecraft:overworld run setblock -130 73 -199 oak_wall_sign[facing=south]{front_text:{has_glowing_text:1b,color:"gold",messages:[''{"text":"✦ HUB ✦","bold":true,"color":"gold"}'',''{"text":"Retour au Hub","color":"yellow"}'',''{"text":"Peak Island","color":"gray"}'',''{"text":"✦ ✦ ✦","color":"gold"}''}}'
)

foreach ($cmd in $hubCommands) {
    & "$PSScriptRoot\rcon.ps1" -Command $cmd
}

foreach ($cmd in $overworldCommands) {
    & "$PSScriptRoot\rcon.ps1" -Command $cmd
}

Write-Host "Decorations applied successfully!"
