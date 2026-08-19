# Stocke le score du joueur dans un storage puis appelle la macro
execute store result storage deathcounter:data deaths int 1 run scoreboard players get @s deaths
function deathcounter:apply_format with storage deathcounter:data
