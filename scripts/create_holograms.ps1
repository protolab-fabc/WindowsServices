$commands = @(
    # Remove existing hologram displays if any
    'execute in hub:lobby as @e[type=text_display,tag=hub_portal_holo] run kill @s',
    'execute in minecraft:overworld as @e[type=text_display,tag=overworld_portal_holo] run kill @s',

    # Summon Hub Portal Floating Text Display
    'execute in hub:lobby run summon text_display 171.5 68.3 -187.8 {Tags:["hub_portal_holo"],billboard:"vertical",text:''{"text":"✦ MONDE SURVIE ✦\\n","color":"green","bold":true,"extra":[{"text":"▶ Entrez pour jouer ◀","color":"gray","bold":false}]}''}',

    # Summon Overworld Portal Floating Text Display
    'execute in minecraft:overworld run summon text_display -128.0 78.3 -199.8 {Tags:["overworld_portal_holo"],billboard:"vertical",text:''{"text":"✦ LE HUB ✦\\n","color":"gold","bold":true,"extra":[{"text":"▶ Retour à Peak Island ◀","color":"yellow","bold":false}]}''}'
)

foreach ($c in $commands) {
    & "$PSScriptRoot\rcon.ps1" -Command $c
}

Write-Host "Holograms created successfully!"
