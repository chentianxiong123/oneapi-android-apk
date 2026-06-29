import struct, sys

with open(sys.argv[1], 'r+b') as f:
    hdr = f.read(16)
    if hdr[4] == 2:  # 64-bit ELF
        f.seek(32)
        offset = struct.unpack('<Q', f.read(8))[0]
        f.seek(54)
        phsize = struct.unpack('<H', f.read(2))[0]
        phnum = struct.unpack('<H', f.read(2))[0]
        for i in range(phnum):
            f.seek(offset + i * phsize)
            t = struct.unpack('<I', f.read(4))[0]
            if t == 7:  # PT_TLS
                f.seek(44, 1)
                align = struct.unpack('<Q', f.read(8))[0]
                print(f"PT_TLS found, current alignment: {align}")
                if align < 64:
                    f.seek(-8, 1)
                    f.write(struct.pack('<Q', 64))
                    print(f"Fixed alignment to 64")
                break
print("Done")