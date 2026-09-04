import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from nozor_agent import rcon_exec

def rebuild():
    commands = [
        # --- 1. Cadre en Obsidienne Pure & Pleureuse (100% stable en vanilla) ---
        # Bas (Y=71, Z=-200)
        "execute in minecraft:overworld run setblock -130 71 -200 crying_obsidian",
        "execute in minecraft:overworld run setblock -129 71 -200 obsidian",
        "execute in minecraft:overworld run setblock -128 71 -200 obsidian",
        "execute in minecraft:overworld run setblock -127 71 -200 obsidian",
        "execute in minecraft:overworld run setblock -126 71 -200 crying_obsidian",

        # Pilier Gauche (X=-130, Z=-200)
        "execute in minecraft:overworld run setblock -130 72 -200 obsidian",
        "execute in minecraft:overworld run setblock -130 73 -200 obsidian",
        "execute in minecraft:overworld run setblock -130 74 -200 obsidian",
        "execute in minecraft:overworld run setblock -130 75 -200 obsidian",

        # Pilier Droit (X=-126, Z=-200)
        "execute in minecraft:overworld run setblock -126 72 -200 obsidian",
        "execute in minecraft:overworld run setblock -126 73 -200 obsidian",
        "execute in minecraft:overworld run setblock -126 74 -200 obsidian",
        "execute in minecraft:overworld run setblock -126 75 -200 obsidian",

        # Haut (Y=76, Z=-200)
        "execute in minecraft:overworld run setblock -130 76 -200 crying_obsidian",
        "execute in minecraft:overworld run setblock -129 76 -200 obsidian",
        "execute in minecraft:overworld run setblock -128 76 -200 obsidian",
        "execute in minecraft:overworld run setblock -127 76 -200 obsidian",
        "execute in minecraft:overworld run setblock -126 76 -200 crying_obsidian",

        # Blocs de portail intérieurs (3x4)
        "execute in minecraft:overworld run fill -129 72 -200 -127 75 -200 nether_portal[axis=x]",

        # --- 2. Décorations extérieures (au-dessus et sur les côtés, ne touchant pas le portail intérieur) ---
        # Fronton supérieur (Y=77, Z=-200)
        "execute in minecraft:overworld run setblock -130 77 -200 stone_brick_stairs[facing=east,half=bottom]",
        "execute in minecraft:overworld run setblock -129 77 -200 stone_brick_slab",
        "execute in minecraft:overworld run setblock -128 77 -200 chiseled_stone_bricks",
        "execute in minecraft:overworld run setblock -127 77 -200 stone_brick_slab",
        "execute in minecraft:overworld run setblock -126 77 -200 stone_brick_stairs[facing=west,half=bottom]",

        # Piliers décoratifs extérieurs (X=-131 et X=-125)
        "execute in minecraft:overworld run setblock -131 72 -200 mossy_stone_brick_stairs[facing=west,half=bottom]",
        "execute in minecraft:overworld run setblock -131 73 -200 stone_brick_wall",
        "execute in minecraft:overworld run setblock -131 74 -200 mossy_stone_brick_wall",
        "execute in minecraft:overworld run setblock -131 75 -200 stone_brick_wall",
        "execute in minecraft:overworld run setblock -131 76 -200 stone_brick_stairs[facing=west,half=top]",

        "execute in minecraft:overworld run setblock -125 72 -200 mossy_stone_brick_stairs[facing=east,half=bottom]",
        "execute in minecraft:overworld run setblock -125 73 -200 stone_brick_wall",
        "execute in minecraft:overworld run setblock -125 74 -200 mossy_stone_brick_wall",
        "execute in minecraft:overworld run setblock -125 75 -200 stone_brick_wall",
        "execute in minecraft:overworld run setblock -125 76 -200 stone_brick_stairs[facing=east,half=top]",

        # Lanternes
        "execute in minecraft:overworld run setblock -131 76 -199 chain",
        "execute in minecraft:overworld run setblock -131 75 -199 lantern[hanging=true]",
        "execute in minecraft:overworld run setblock -125 76 -199 chain",
        "execute in minecraft:overworld run setblock -125 75 -199 lantern[hanging=true]",

        # Panneau lumineux
        'execute in minecraft:overworld run setblock -130 73 -199 oak_wall_sign[facing=south]{front_text:{has_glowing_text:1b,color:"gold",messages:[\'{"text":"✦ HUB ✦","bold":true,"color":"gold"}\',\'{"text":"Retour au Hub","color":"yellow"}\',\'{"text":"Peak Island","color":"gray"}\',\'{"text":"✦ ✦ ✦","color":"gold"}\']}}',

        # Hologramme
        "execute in minecraft:overworld run function hub:setup_holograms",

        # Forceload
        "execute in minecraft:overworld run forceload add -135 -215 -120 -195"
    ]

    for c in commands:
        rcon_exec(c)

    print("Solid portal frame rebuilt successfully!")

if __name__ == "__main__":
    rebuild()
