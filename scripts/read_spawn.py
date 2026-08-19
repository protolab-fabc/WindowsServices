import gzip
import struct

with gzip.open("world/level.dat", "rb") as f:
    content = f.read()

# Let's search for SpawnX, SpawnY, SpawnZ in NBT
def find_tag(name, data_type=None):
    tag_name = name.encode('utf-8')
    idx = 0
    while True:
        idx = content.find(tag_name, idx)
        if idx == -1:
            break
        # Tag name is preceded by 1 byte (type) and 2 bytes (len)
        if idx >= 3:
            t = content[idx-3]
            l = struct.unpack(">H", content[idx-2:idx])[0]
            if l == len(name):
                val_start = idx + len(name)
                if t == 3: # TAG_Int
                    val = struct.unpack(">i", content[val_start:val_start+4])[0]
                    print(f"{name} (Int): {val}")
                elif t == 6: # TAG_Double
                    val = struct.unpack(">d", content[val_start:val_start+8])[0]
                    print(f"{name} (Double): {val}")
                elif t == 5: # TAG_Float
                    val = struct.unpack(">f", content[val_start:val_start+4])[0]
                    print(f"{name} (Float): {val}")
        idx += 1

find_tag("SpawnX")
find_tag("SpawnY")
find_tag("SpawnZ")
find_tag("SpawnAngle")
