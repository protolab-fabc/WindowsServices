# Initialisation du compteur de morts + affichage vie
# Cree les scoreboards et configure les affichages

# Scoreboard des morts (tracking automatique)
scoreboard objectives add deaths deathCount {"text":"☠ Morts","color":"red"}

# Scoreboard auxiliaire pour detecter les nouvelles morts (log en jeu)
scoreboard objectives add deaths_prev dummy

# Scoreboard de la sante (tracking automatique)
scoreboard objectives add health health {"text":"❤","color":"red"}

# Affichage : morts dans le TAB, vie au-dessus des tetes
scoreboard objectives setdisplay list deaths
scoreboard objectives setdisplay below_name health

# Format d'affichage
scoreboard objectives modify deaths numberformat styled {"color":"red","bold":true}
scoreboard objectives modify health numberformat styled {"color":"red","bold":true}

tellraw @a [{"text":"[Death Counter] ","color":"red","bold":true},{"text":"Compteur de morts + vie actifs — visible dans le TAB","color":"gray"}]

# Initialisation du portail Hub -> Survie
function hub:setup_hub_portal

