import json
import time
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from nozor_agent import rcon_exec

BACKUP_FILE = os.path.join(os.path.dirname(__file__), "overworld_portal_platform_backup.json")

def restore_platform():
    if not os.path.exists(BACKUP_FILE):
        print(f"Error: {BACKUP_FILE} not found!")
        return False

    with open(BACKUP_FILE, "r", encoding="utf-8") as f:
        blocks = json.load(f)

    print(f"Restoring {len(blocks)} blocks to Overworld portal & platform...")
    
    # 1. Clear area of natural tree/ground interference in bounding box
    rcon_exec("execute in minecraft:overworld run fill -135 72 -210 -123 80 -198 air keep")
    
    # 2. Place solid blocks first (stone, bricks, obsidian), then decorations (stairs, walls, lanterns, portals)
    solids = {}
    decorations = {}
    
    for k, v in blocks.items():
        if any(d in v for d in ["stairs", "wall", "slab", "lantern", "iron_bars", "portal", "sign"]):
            decorations[k] = v
        else:
            solids[k] = v

    # Place solids
    for k, v in solids.items():
        x, y, z = k.split(",")
        rcon_exec(f"execute in minecraft:overworld run setblock {x} {y} {z} {v} destroy")

    # Place decorations
    for k, v in decorations.items():
        x, y, z = k.split(",")
        rcon_exec(f"execute in minecraft:overworld run setblock {x} {y} {z} {v} destroy")

    # 3. Ensure portal blocks inside the frame are properly lit
    portal_coords = [
        ("-129", "72", "-200"), ("-128", "72", "-200"), ("-127", "72", "-200"),
        ("-129", "73", "-200"), ("-128", "73", "-200"), ("-127", "73", "-200"),
        ("-129", "74", "-200"), ("-128", "74", "-200"), ("-127", "74", "-200"),
        ("-129", "75", "-200"), ("-128", "75", "-200"), ("-127", "75", "-200"),
    ]
    for px, py, pz in portal_coords:
        rcon_exec(f"execute in minecraft:overworld run setblock {px} {py} {pz} nether_portal[axis=x]")

    # 4. Restore Hologram
    rcon_exec("execute in minecraft:overworld run function hub:setup_holograms")

    # 5. Restore chunk forceloading
    rcon_exec("execute in minecraft:overworld run forceload add -135 -215 -120 -195")

    print("Portal and platform restored successfully!")
    return True

if __name__ == "__main__":
    restore_platform()
