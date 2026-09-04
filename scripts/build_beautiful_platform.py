import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from nozor_agent import rcon_exec

def build():
    print("Building magnificent sanctuary portal platform in Overworld...")

    cmds = [
        # --- 1. NETTOYAGE DE L'ESPACE AÉRIEN ---
        "execute in minecraft:overworld run fill -137 72 -225 -119 82 -196 air keep",

        # --- 2. FONDATIONS ET TALUS SOUS LA TERRASSE (Y=60 à 70) ---
        "execute in minecraft:overworld run fill -136 60 -214 -120 70 -198 stone",
        "execute in minecraft:overworld run fill -135 61 -213 -121 70 -199 dirt",

        # --- 3. PLANCHER NOBLE DE LA TERRASSE (Y=71) ---
        # Bordure extérieure en briques de pierre
        "execute in minecraft:overworld run fill -135 71 -213 -121 71 -198 stone_bricks",
        # Anneau intermédiaire en andésite polie
        "execute in minecraft:overworld run fill -134 71 -212 -122 71 -199 polished_andesite",
        # Zone centrale en briques de pierre ciselées et pierre polie
        "execute in minecraft:overworld run fill -132 71 -211 -124 71 -201 smooth_stone",
        # Allée axiale en pierre noire polie reliant l'arrivée au portail
        "execute in minecraft:overworld run fill -129 71 -212 -127 71 -201 polished_blackstone",

        # --- 4. MÉDAILLON D'ARRIVÉE AU SPAWN (X=-128, Y=71, Z=-208) ---
        "execute in minecraft:overworld run setblock -128 71 -208 gilded_blackstone",
        "execute in minecraft:overworld run setblock -129 71 -208 chiseled_polished_blackstone",
        "execute in minecraft:overworld run setblock -127 71 -208 chiseled_polished_blackstone",
        "execute in minecraft:overworld run setblock -128 71 -209 chiseled_polished_blackstone",
        "execute in minecraft:overworld run setblock -128 71 -207 chiseled_polished_blackstone",

        # --- 5. CADRE DU PORTAIL EN OBSIDIENNE PURE (X=-130..-126, Y=71..76, Z=-200) ---
        # Base
        "execute in minecraft:overworld run setblock -130 71 -200 crying_obsidian",
        "execute in minecraft:overworld run setblock -129 71 -200 obsidian",
        "execute in minecraft:overworld run setblock -128 71 -200 obsidian",
        "execute in minecraft:overworld run setblock -127 71 -200 obsidian",
        "execute in minecraft:overworld run setblock -126 71 -200 crying_obsidian",
        # Piliers
        "execute in minecraft:overworld run fill -130 72 -200 -130 75 -200 obsidian",
        "execute in minecraft:overworld run fill -126 72 -200 -126 75 -200 obsidian",
        # Haut
        "execute in minecraft:overworld run setblock -130 76 -200 crying_obsidian",
        "execute in minecraft:overworld run setblock -129 76 -200 obsidian",
        "execute in minecraft:overworld run setblock -128 76 -200 obsidian",
        "execute in minecraft:overworld run setblock -127 76 -200 obsidian",
        "execute in minecraft:overworld run setblock -126 76 -200 crying_obsidian",
        # Remplissage du portail (3x4)
        "execute in minecraft:overworld run fill -129 72 -200 -127 75 -200 nether_portal[axis=x]",

        # --- 6. ARCHE & DÉCORATION DU PORTAIL ---
        # Fronton supérieur
        "execute in minecraft:overworld run setblock -130 77 -200 stone_brick_stairs[facing=east,half=bottom]",
        "execute in minecraft:overworld run setblock -129 77 -200 stone_brick_slab",
        "execute in minecraft:overworld run setblock -128 77 -200 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -127 77 -200 stone_brick_slab",
        "execute in minecraft:overworld run setblock -126 77 -200 stone_brick_stairs[facing=west,half=bottom]",
        # Colonnes encadrantes
        "execute in minecraft:overworld run setblock -131 72 -200 mossy_stone_brick_stairs[facing=west,half=bottom]",
        "execute in minecraft:overworld run fill -131 73 -200 -131 75 -200 stone_brick_wall",
        "execute in minecraft:overworld run setblock -131 76 -200 stone_brick_stairs[facing=west,half=top]",

        "execute in minecraft:overworld run setblock -125 72 -200 mossy_stone_brick_stairs[facing=east,half=bottom]",
        "execute in minecraft:overworld run fill -125 73 -200 -125 75 -200 stone_brick_wall",
        "execute in minecraft:overworld run setblock -125 76 -200 stone_brick_stairs[facing=east,half=top]",

        # Lanternes suspendues du portail
        "execute in minecraft:overworld run setblock -131 76 -199 chain",
        "execute in minecraft:overworld run setblock -131 75 -199 soul_lantern[hanging=true]",
        "execute in minecraft:overworld run setblock -125 76 -199 chain",
        "execute in minecraft:overworld run setblock -125 75 -199 soul_lantern[hanging=true]",

        # Panneau néon doré
        'execute in minecraft:overworld run setblock -130 73 -199 oak_wall_sign[facing=south]{front_text:{has_glowing_text:1b,color:"gold",messages:[\'{"text":"✦ HUB ✦","bold":true,"color":"gold"}\',\'{"text":"Retour au Hub","color":"yellow"}\',\'{"text":"Peak Island","color":"gray"}\',\'{"text":"✦ ✦ ✦","color":"gold"}\']}}',

        # --- 7. BALUSTRADES ET JARDINIÈRES DE LA TERRASSE (Y=72) ---
        # Balustrade Ouest (X=-135)
        "execute in minecraft:overworld run fill -135 72 -212 -135 72 -200 stone_brick_wall",
        # Balustrade Est (X=-121)
        "execute in minecraft:overworld run fill -121 72 -212 -121 72 -200 stone_brick_wall",
        # Balustrade Nord derrière le portail (Z=-198)
        "execute in minecraft:overworld run fill -134 72 -198 -122 72 -198 stone_brick_wall",

        # Piliers d'angle avec lanternes
        "execute in minecraft:overworld run setblock -135 72 -213 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -135 73 -213 lantern[hanging=false]",
        "execute in minecraft:overworld run setblock -121 72 -213 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -121 73 -213 lantern[hanging=false]",
        "execute in minecraft:overworld run setblock -135 72 -198 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -135 73 -198 lantern[hanging=false]",
        "execute in minecraft:overworld run setblock -121 72 -198 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -121 73 -198 lantern[hanging=false]",

        # Jardinières de fleurs et azaleas sur la terrasse
        "execute in minecraft:overworld run setblock -133 72 -212 moss_block",
        "execute in minecraft:overworld run setblock -133 73 -212 flowering_azalea",
        "execute in minecraft:overworld run setblock -123 72 -212 moss_block",
        "execute in minecraft:overworld run setblock -123 73 -212 flowering_azalea",
        "execute in minecraft:overworld run setblock -133 72 -203 moss_block",
        "execute in minecraft:overworld run setblock -133 73 -203 sunflower",
        "execute in minecraft:overworld run setblock -123 72 -203 moss_block",
        "execute in minecraft:overworld run setblock -123 73 -203 sunflower",

        # --- 8. GRAND ESCALIER IMPÉRIAL VERS LA PLAINE (Z=-213 à -223, Y=71 à 62) ---
    ]

    # Génération des marches de l'escalier avec murets de protection
    for i in range(10):
        y = 71 - i
        z = -213 - i
        # Marches centrales (5 blocs de large)
        cmds.append(f"execute in minecraft:overworld run fill -130 {y} {z} -126 {y} {z} stone_brick_stairs[facing=north,half=bottom]")
        # Sous les marches : blocs pleins
        cmds.append(f"execute in minecraft:overworld run fill -130 {y-1} {z} -126 60 {z} stone_bricks")
        # Bordures latérales de l'escalier
        cmds.append(f"execute in minecraft:overworld run setblock -131 {y} {z} stone_bricks")
        cmds.append(f"execute in minecraft:overworld run setblock -131 {y+1} {z} stone_brick_wall")
        cmds.append(f"execute in minecraft:overworld run setblock -125 {y} {z} stone_bricks")
        cmds.append(f"execute in minecraft:overworld run setblock -125 {y+1} {z} stone_brick_wall")

    # Lampadaires en bas et en milieu d'escalier
    cmds.extend([
        "execute in minecraft:overworld run setblock -131 69 -217 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -131 70 -217 lantern[hanging=false]",
        "execute in minecraft:overworld run setblock -125 69 -217 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -125 70 -217 lantern[hanging=false]",
        "execute in minecraft:overworld run setblock -131 64 -222 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -131 65 -222 lantern[hanging=false]",
        "execute in minecraft:overworld run setblock -125 64 -222 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -125 65 -222 lantern[hanging=false]",

        # Palier d'arrivée en bas de l'escalier (Y=62)
        "execute in minecraft:overworld run fill -131 61 -225 -125 61 -223 stone_bricks",
        "execute in minecraft:overworld run fill -130 61 -225 -126 61 -223 polished_andesite",

        # --- 9. HOLOGRAMMES DE RETOUR & FORCELOAD ---
        "execute in minecraft:overworld run function hub:setup_holograms",
        "execute in minecraft:overworld run forceload add -135 -225 -120 -195",
        "execute in minecraft:overworld run gamerule command_block_output false"
    ])

    print(f"Executing {len(cmds)} architectural commands...")
    for c in cmds:
        rcon_exec(c)

    print("Magnificent platform completed successfully!")

if __name__ == "__main__":
    build()
