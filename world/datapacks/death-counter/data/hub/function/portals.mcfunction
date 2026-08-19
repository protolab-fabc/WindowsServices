# Portails bidirectionnels Hub (Peak Island) <-> Survie (Overworld)

# 1. Du monde Survie vers le Hub (Portail de retour au spawn initial de Survie: X=-128, Y=72, Z=-200 / -202)
execute in minecraft:overworld as @a[x=-132,y=70,z=-204,dx=6,dy=6,dz=6] if block ~ ~ ~ nether_portal run function hub:tp_to_hub
execute in minecraft:overworld as @a[x=-130,y=71,z=-201,dx=3,dy=4,dz=2] run function hub:tp_to_hub

# 2. Du Hub vers le monde Survie (Portail 1 à Peak Island: X=198, Y=65, Z=-200)
execute in hub:lobby as @a[x=196,y=64,z=-202,dx=4,dy=5,dz=5] if block ~ ~ ~ nether_portal run function hub:tp_to_survival
execute in hub:lobby as @a[x=197,y=64,z=-201,dx=2,dy=4,dz=3] run function hub:tp_to_survival

# 3. Du Hub vers le monde Survie (Portail 2 - Position Vibrions: X=171..172, Y=63..65, Z=-188)
execute in hub:lobby as @a[x=170,y=62,z=-189,dx=4,dy=5,dz=3] if block ~ ~ ~ nether_portal run function hub:tp_to_survival
execute in hub:lobby as @a[x=171,y=63,z=-188,dx=2,dy=3,dz=1] run function hub:tp_to_survival

# Détection globale de portails au Hub (tout bloc portail dans le hub téléporte vers la survie)
execute in hub:lobby as @a if block ~ ~ ~ nether_portal run function hub:tp_to_survival
execute in hub:lobby as @a if block ~ ~ ~ end_portal run function hub:tp_to_survival

# 4. Sécurité anti-chute dans le vide au Hub
execute in hub:lobby as @a[y=-10,dy=-80] run tp @s 193.5 64 -200 0 0
