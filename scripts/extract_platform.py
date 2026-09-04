import io, nbtlib, zlib, struct, json

def get_chunk_nbt(mca_path, cx, cz):
    rx = cx & 31
    rz = cz & 31
    with open(mca_path, 'rb') as f:
        f.seek(4 * (rx + rz * 32))
        b = f.read(4)
        offset = struct.unpack('>I', b'\x00' + b[:3])[0] * 4096
        if offset == 0: return None
        f.seek(offset)
        length = struct.unpack('>I', f.read(4))[0]
        version = ord(f.read(1))
        compressed = f.read(length - 1)
        raw = zlib.decompress(compressed)
        return nbtlib.File.parse(io.BytesIO(raw))

all_blocks = {}

for cx, cz in [(-9, -14), (-8, -14), (-9, -13), (-8, -13)]:
    nbt = get_chunk_nbt('world/dimensions/minecraft/overworld/region/r.-1.-1.mca', cx, cz)
    if not nbt: continue
    for s in nbt.get('sections', []):
        y_sec = int(s.get('Y'))
        if y_sec != 4: continue
        bs = s.get('block_states')
        if not bs: continue
        palette = bs.get('palette')
        if not palette: continue
        data = bs.get('data')
        if data is None: continue
        
        palette_len = len(palette)
        bits_per_block = max(4, (palette_len - 1).bit_length())
        blocks_per_long = 64 // bits_per_block
        mask = (1 << bits_per_block) - 1
        longs = [int(v) & 0xFFFFFFFFFFFFFFFF for v in data]
        
        for index in range(4096):
            bx = index & 15
            bz = (index >> 4) & 15
            by = (index >> 8) & 15
            
            world_x = cx * 16 + bx
            world_y = y_sec * 16 + by
            world_z = cz * 16 + bz
            
            if -140 <= world_x <= -115 and 70 <= world_y <= 80 and -220 <= world_z <= -195:
                long_idx = index // blocks_per_long
                bit_idx = (index % blocks_per_long) * bits_per_block
                if long_idx < len(longs):
                    val = (longs[long_idx] >> bit_idx) & mask
                    p = palette[val]
                    name = str(p.get('Name'))
                    if name != 'minecraft:air':
                        props = p.get('Properties')
                        prop_str = ""
                        if props:
                            prop_str = "[" + ",".join(f"{k}={v}" for k, v in props.items()) + "]"
                        all_blocks[(world_x, world_y, world_z)] = name + prop_str

print(f"Total non-air blocks in bounding box: {len(all_blocks)}")
types = set(v.split('[')[0] for v in all_blocks.values())
print("All block types in bounding box:", sorted(types))

# Check for portal and obsidian
portal_blocks = {k: v for k, v in all_blocks.items() if 'portal' in v or 'obsidian' in v}
print("Portal/obsidian blocks count:", len(portal_blocks))
for k, v in sorted(portal_blocks.items()):
    print(f"  {k} -> {v}")

# Save full structure dictionary to JSON
json_data = {f"{k[0]},{k[1]},{k[2]}": v for k, v in all_blocks.items()}
with open('scripts/overworld_portal_platform_backup.json', 'w', encoding='utf-8') as f:
    json.dump(json_data, f, indent=2)
print("Saved overworld_portal_platform_backup.json successfully!")
