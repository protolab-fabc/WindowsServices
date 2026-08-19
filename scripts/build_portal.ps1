$commands = @(
    "execute in hub:lobby run setblock 170 62 -188 crying_obsidian",
    "execute in hub:lobby run setblock 171 62 -188 obsidian",
    "execute in hub:lobby run setblock 172 62 -188 obsidian",
    "execute in hub:lobby run setblock 173 62 -188 crying_obsidian",
    "execute in hub:lobby run setblock 170 63 -188 obsidian",
    "execute in hub:lobby run setblock 170 64 -188 obsidian",
    "execute in hub:lobby run setblock 170 65 -188 obsidian",
    "execute in hub:lobby run setblock 173 63 -188 obsidian",
    "execute in hub:lobby run setblock 173 64 -188 obsidian",
    "execute in hub:lobby run setblock 173 65 -188 obsidian",
    "execute in hub:lobby run setblock 170 66 -188 crying_obsidian",
    "execute in hub:lobby run setblock 171 66 -188 obsidian",
    "execute in hub:lobby run setblock 172 66 -188 obsidian",
    "execute in hub:lobby run setblock 173 66 -188 crying_obsidian",
    "execute in hub:lobby run setblock 171 63 -188 nether_portal[axis=x]",
    "execute in hub:lobby run setblock 172 63 -188 nether_portal[axis=x]",
    "execute in hub:lobby run setblock 171 64 -188 nether_portal[axis=x]",
    "execute in hub:lobby run setblock 172 64 -188 nether_portal[axis=x]",
    "execute in hub:lobby run setblock 171 65 -188 nether_portal[axis=x]",
    "execute in hub:lobby run setblock 172 65 -188 nether_portal[axis=x]",
    'execute in hub:lobby run setblock 170 64 -187 oak_wall_sign[facing=south]{front_text:{messages:[''{"text":"✦ SURVIE ✦","color":"green","bold":true}'',''{"text":"Overworld","color":"dark_green"}'',''{"text":"Entrez pour jouer","color":"gray"}'',''{"text":"--------","color":"dark_gray"}''}}'
)

foreach ($c in $commands) {
    & "$PSScriptRoot\rcon.ps1" -Command $c
}
