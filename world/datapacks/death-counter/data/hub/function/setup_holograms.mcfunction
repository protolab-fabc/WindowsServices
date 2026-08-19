# Creation des equipes de couleur
team add holo_green
team modify holo_green color green
team add holo_gold
team modify holo_gold color gold
team add holo_gray
team modify holo_gray color gray
team add holo_yellow
team modify holo_yellow color yellow

# Nettoyage des anciens hologrammes
execute as @e[tag=hub_portal_holo] run kill @s
execute as @e[tag=overworld_portal_holo] run kill @s

# Hub Portal Hologram (X=171.5, Y=67.4..67.7, Z=-188)
execute in hub:lobby run summon armor_stand 171.5 67.4 -188.0 {Tags:["hub_portal_holo","hub_line1"],Invisible:1b,Invulnerable:1b,NoGravity:1b,Marker:1b,CustomNameVisible:1b,CustomName:'"▶ Entrez pour jouer ◀"'}
execute in hub:lobby run summon armor_stand 171.5 67.7 -188.0 {Tags:["hub_portal_holo","hub_line2"],Invisible:1b,Invulnerable:1b,NoGravity:1b,Marker:1b,CustomNameVisible:1b,CustomName:'"✦ MONDE SURVIE ✦"'}

# Overworld Portal Hologram (X=-128, Y=77.4..77.7, Z=-200)
execute in minecraft:overworld run summon armor_stand -128.0 77.4 -200.0 {Tags:["overworld_portal_holo","ow_line1"],Invisible:1b,Invulnerable:1b,NoGravity:1b,Marker:1b,CustomNameVisible:1b,CustomName:'"▶ Retour à Peak Island ◀"'}
execute in minecraft:overworld run summon armor_stand -128.0 77.7 -200.0 {Tags:["overworld_portal_holo","ow_line2"],Invisible:1b,Invulnerable:1b,NoGravity:1b,Marker:1b,CustomNameVisible:1b,CustomName:'"✦ LE HUB ✦"'}

# Application des couleurs via les equipes
execute as @e[tag=hub_line1] run team join holo_gray @s
execute as @e[tag=hub_line2] run team join holo_green @s
execute as @e[tag=ow_line1] run team join holo_yellow @s
execute as @e[tag=ow_line2] run team join holo_gold @s
