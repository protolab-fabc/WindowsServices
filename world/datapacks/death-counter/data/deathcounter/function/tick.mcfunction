# Tick : met a jour l'affichage, portails et detecte les nouvelles morts

# 1. Gestion des portails de téléportation Hub <-> Survie
function hub:portals

# 2. Arrivée des nouveaux joueurs au Hub
execute as @a[tag=!joined_hub] in hub:lobby run tp @s 193.5 64 -200 0 0
execute as @a[tag=!joined_hub] run tag @s add joined_hub

# 3. Initialiser le score des nouveaux joueurs a 0 s'il n'est pas defini
execute as @a unless score @s deaths = @s deaths run scoreboard players set @s deaths 0
execute as @a unless score @s deaths_prev = @s deaths_prev run scoreboard players set @s deaths_prev 0

# 4. Mettre a jour le format d'affichage "X ☠" pour chaque joueur
execute as @a run function deathcounter:update_format

# 5. Detecter les nouvelles morts et annoncer dans le chat
execute as @a unless score @s deaths = @s deaths_prev run function deathcounter:on_death
execute as @a run scoreboard players operation @s deaths_prev = @s deaths
