import os, shutil, nbtlib, sys

sys.path.insert(0, os.path.dirname(__file__))
from nozor_agent import rcon_exec

NEW_SEED = -4029535714769340309

def apply_new_seed(seed: int):
    # 1. Update server.properties
    props_path = r"C:\WindowsServices\server.properties"
    with open(props_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    
    with open(props_path, "w", encoding="utf-8") as f:
        for line in lines:
            if line.startswith("level-seed="):
                f.write(f"level-seed={seed}\n")
            else:
                f.write(line)
    print(f"Updated server.properties with seed {seed}")

    # 2. Update world_gen_settings.dat
    wgs_path = r"C:\WindowsServices\world\data\minecraft\world_gen_settings.dat"
    if os.path.exists(wgs_path):
        nbt = nbtlib.load(wgs_path)
        if "data" in nbt and "seed" in nbt["data"]:
            nbt["data"]["seed"] = nbtlib.Long(seed)
            nbt.save()
            print(f"Updated world_gen_settings.dat with seed {seed}")

    # 3. Purge Overworld regions, entities, poi
    ow_dir = r"C:\WindowsServices\world\dimensions\minecraft\overworld"
    for folder in ["region", "entities", "poi"]:
        p = os.path.join(ow_dir, folder)
        if os.path.exists(p):
            shutil.rmtree(p)
            print(f"Purged {p}")

if __name__ == "__main__":
    seed_arg = int(sys.argv[1]) if len(sys.argv) > 1 else NEW_SEED
    apply_new_seed(seed_arg)
