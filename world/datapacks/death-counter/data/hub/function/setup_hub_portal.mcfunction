# Construction / maintenance du portail du Hub vers le monde Survie
# Emplacement 1 : Plateforme en pierre a X=198, Y=64, Z=-200 (axe Z)

execute in hub:lobby run setblock 198 64 -201 crying_obsidian
execute in hub:lobby run setblock 198 64 -200 obsidian
execute in hub:lobby run setblock 198 64 -199 obsidian
execute in hub:lobby run setblock 198 64 -198 crying_obsidian

execute in hub:lobby run setblock 198 65 -201 obsidian
execute in hub:lobby run setblock 198 66 -201 obsidian
execute in hub:lobby run setblock 198 67 -201 obsidian

execute in hub:lobby run setblock 198 65 -198 obsidian
execute in hub:lobby run setblock 198 66 -198 obsidian
execute in hub:lobby run setblock 198 67 -198 obsidian

execute in hub:lobby run setblock 198 68 -201 crying_obsidian
execute in hub:lobby run setblock 198 68 -200 obsidian
execute in hub:lobby run setblock 198 68 -199 obsidian
execute in hub:lobby run setblock 198 68 -198 crying_obsidian

execute in hub:lobby run setblock 198 65 -200 nether_portal[axis=z]
execute in hub:lobby run setblock 198 65 -199 nether_portal[axis=z]
execute in hub:lobby run setblock 198 66 -200 nether_portal[axis=z]
execute in hub:lobby run setblock 198 66 -199 nether_portal[axis=z]
execute in hub:lobby run setblock 198 67 -200 nether_portal[axis=z]
execute in hub:lobby run setblock 198 67 -199 nether_portal[axis=z]

execute in hub:lobby run setblock 197 66 -201 oak_wall_sign[facing=west]{front_text:{messages:['{"text":"✦ SURVIE ✦","color":"green","bold":true}','{"text":"Monde Principal","color":"dark_green"}','{"text":"Entrez pour jouer","color":"gray"}','{"text":"--------","color":"dark_gray"}']}}

# Emplacement 2 (Position Vibrions) : X=171..172, Y=62..66, Z=-188 (axe X)
execute in hub:lobby run setblock 170 62 -188 crying_obsidian
execute in hub:lobby run setblock 171 62 -188 obsidian
execute in hub:lobby run setblock 172 62 -188 obsidian
execute in hub:lobby run setblock 173 62 -188 crying_obsidian

execute in hub:lobby run setblock 170 63 -188 obsidian
execute in hub:lobby run setblock 170 64 -188 obsidian
execute in hub:lobby run setblock 170 65 -188 obsidian

execute in hub:lobby run setblock 173 63 -188 obsidian
execute in hub:lobby run setblock 173 64 -188 obsidian
execute in hub:lobby run setblock 173 65 -188 obsidian

execute in hub:lobby run setblock 170 66 -188 crying_obsidian
execute in hub:lobby run setblock 171 66 -188 obsidian
execute in hub:lobby run setblock 172 66 -188 obsidian
execute in hub:lobby run setblock 173 66 -188 crying_obsidian

execute in hub:lobby run setblock 171 63 -188 nether_portal[axis=x]
execute in hub:lobby run setblock 172 63 -188 nether_portal[axis=x]
execute in hub:lobby run setblock 171 64 -188 nether_portal[axis=x]
execute in hub:lobby run setblock 172 64 -188 nether_portal[axis=x]
execute in hub:lobby run setblock 171 65 -188 nether_portal[axis=x]
execute in hub:lobby run setblock 172 65 -188 nether_portal[axis=x]

execute in hub:lobby run setblock 170 64 -187 oak_wall_sign[facing=south]{front_text:{messages:['{"text":"✦ SURVIE ✦","color":"green","bold":true}','{"text":"Overworld","color":"dark_green"}','{"text":"Entrez pour jouer","color":"gray"}','{"text":"--------","color":"dark_gray"}']}}
