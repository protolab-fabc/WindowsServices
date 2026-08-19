# Annonce de mort dans le chat avec le nouveau total
tellraw @a [{"text":"☠ ","color":"red"},{"selector":"@s","color":"gold"},{"text":" est mort ! Total : ","color":"gray"},{"score":{"name":"@s","objective":"deaths"},"color":"red","bold":true},{"text":" mort(s)","color":"gray"}]
