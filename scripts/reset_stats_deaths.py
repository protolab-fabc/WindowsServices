import json
import glob
import os

stats_files = glob.glob("world/players/stats/*.json")
for fpath in stats_files:
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            data = json.load(f)
        if "stats" in data and "minecraft:custom" in data["stats"]:
            if "minecraft:deaths" in data["stats"]["minecraft:custom"]:
                data["stats"]["minecraft:custom"]["minecraft:deaths"] = 0
            with open(fpath, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            print(f"Reset deaths in {os.path.basename(fpath)}")
    except Exception as e:
        print(f"Error processing {fpath}: {e}")
