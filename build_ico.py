"""Build a minimal ICO from pre-optimized PNGs."""
import struct, io

sizes = [256, 48, 32, 16]
files = {
    256: 'Assets/radar256opt.png',
    48:  'Assets/radar48opt.png',
    32:  'Assets/radar32opt.png',
    16:  'Assets/radar16opt.png',
}
png_entries = []

for s in sizes:
    with open(files[s], 'rb') as f:
        png_entries.append(f.read())

# ICO format: header + directory entries + image data
num = len(sizes)
header = struct.pack('<HHH', 0, 1, num)  # reserved=0, type=1 (icon), count

# Calculate offsets: header(6) + entries(num*16) + image data
offset = 6 + num * 16
directory = b''
for i, s in enumerate(sizes):
    data = png_entries[i]
    w = 0 if s == 256 else s  # 0 means 256 in ICO format
    h = w
    directory += struct.pack('<BBBBHHII',
        w, h,    # width, height
        0,       # color count (0 = no palette)
        0,       # reserved
        1,       # color planes
        32,      # bits per pixel
        len(data),  # size of image data
        offset      # offset to image data
    )
    offset += len(data)

with open('Assets/radar.ico', 'wb') as f:
    f.write(header)
    f.write(directory)
    for data in png_entries:
        f.write(data)

import os
size = os.path.getsize('Assets/radar.ico')
print(f'New radar.ico: {size} bytes ({size/1024:.1f} KB)')
for i, s in enumerate(sizes):
    print(f'  {s}x{s}: {len(png_entries[i])} bytes')
