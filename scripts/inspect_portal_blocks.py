import io, nbtlib, zlib, struct

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

for cx, cz in [(-9, -14), (-8, -14), (-9, -13), (-8, -13)]:
    nbt = get_chunk_nbt('world/dimensions/minecraft/overworld/region/r.-1.-1.mca', cx, cz)
    if not nbt:
        continue
    sections = nbt.get('sections', [])
    for s in sections:
        if 'block_states' in s:
            palette = s['block_states'].get('palette', [])
            names = [str(p.get('Name', '')) for p in palette]
            matching = [n for n in names if any(k in n for k in ["portal", "obsidian", "stone_brick", "stairs", "wall", "lantern", "slab", "crying", "planks"])]
            if matching:
                print(f"Chunk ({cx}, {cz}) Section Y={s.get('Y')}: {matching}")
