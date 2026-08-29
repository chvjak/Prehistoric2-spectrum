#!/usr/bin/env python3
"""Build a character-free two-level Prehistorik 2 Spectrum scrolling study."""
from __future__ import annotations

import hashlib
import json
import os
import random
import shutil
import struct
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
OUT = HERE / "artifacts"
BANK = 0x4000
SNA_SIZE = 131_103
LEVEL_TOP, LEVEL_HEIGHT = 56, 128
WORLD_WIDTH, VIEW_WIDTH = 1024, 256  # Four Spectrum screens per complete level.


def zx_address(y: int) -> int:
    return 0x4000 + ((y & 0xC0) << 5) + ((y & 7) << 8) + ((y & 0x38) << 2)


def base_floor(seed: int, y_base: int) -> list[int]:
    rng = random.Random(seed)
    return [y_base + int(6 * __import__("math").sin(x / 31)) + rng.randrange(-2, 3)
            for x in range(WORLD_WIDTH)]


def fill_ground(d: ImageDraw.ImageDraw, floor: list[int], spans: tuple[tuple[int, int], ...]) -> None:
    for start, end in spans:
        d.polygon([(start, LEVEL_HEIGHT - 1), *[(x, floor[x]) for x in range(start, end + 1)],
                   (end, LEVEL_HEIGHT - 1)], fill=1)
    for y in range(111, LEVEL_HEIGHT, 5):
        for x in range((y * 13) % 23, WORLD_WIDTH, 23):
            if floor[x] <= y:
                d.line((x, y, min(WORLD_WIDTH - 1, x + 14), y - 2), fill=0)


def make_level_one() -> Image.Image:
    """Rocky/jungle course: platforms, arches, palms and low shelves."""
    im = Image.new("1", (WORLD_WIDTH, LEVEL_HEIGHT), 0)
    d = ImageDraw.Draw(im)
    floor = base_floor(0x1EE1, 104)
    fill_ground(d, floor, ((0, WORLD_WIDTH - 1),))
    for x, y, width in ((24, 76, 112), (195, 66, 140), (404, 82, 122), (590, 61, 158), (805, 76, 144)):
        d.rectangle((x, y, x + width, y + 4), fill=1)
        d.polygon([(x + 4, y + 5), (x + width - 4, y + 5), (x + width - 17, y + 10), (x + 12, y + 8)], fill=1)
    for x, base, width in ((55, 106, 62), (305, 109, 70), (512, 108, 57), (734, 106, 78), (930, 109, 58)):
        d.ellipse((x, base - 64, x + width, base + 18), fill=1)
        d.ellipse((x + 10, base - 52, x + width - 9, base + 16), fill=0)
        d.rectangle((x, base, x + width, base + 21), fill=1)
        d.rectangle((x + 10, base, x + width - 9, base + 15), fill=0)
    for cx, base in ((150, 100), (455, 94), (678, 103), (870, 96)):
        d.rectangle((cx - 2, base - 48, cx + 2, base), fill=1)
        for side in (-1, 1):
            for n in range(4):
                d.line((cx, base - 45, cx + side * (9 + n * 6), base - 39 - n * 5), fill=1, width=2)
    for x in range(0, WORLD_WIDTH, 87):
        d.polygon([(x, 0), (x + 14, 0), (x + 7, 22 + (x * 13) % 31)], fill=1)
    return im


def make_level_two() -> Image.Image:
    """Second course: deeper cavern, bridges, lava gaps and crystal stacks."""
    im = Image.new("1", (WORLD_WIDTH, LEVEL_HEIGHT), 0)
    d = ImageDraw.Draw(im)
    floor = base_floor(0x1EE2, 111)
    fill_ground(d, floor, ((0, 178), (245, 425), (500, 668), (739, 1023)))
    for x, y, width in ((45, 71, 94), (276, 79, 116), (450, 58, 92), (697, 71, 121), (862, 63, 102)):
        d.rectangle((x, y, x + width, y + 3), fill=1)
        for brace in range(x + 10, x + width - 4, 19):
            d.line((brace, y + 4, brace - 5, y + 15), fill=1)
    for x, bottom, height in ((112, 105, 62), (353, 112, 78), (575, 106, 68), (789, 110, 81), (961, 108, 57)):
        d.polygon([(x, bottom), (x + 13, bottom - height), (x + 27, bottom)], fill=1)
        d.polygon([(x + 7, bottom), (x + 13, bottom - height + 13), (x + 20, bottom)], fill=0)
    for x, base in ((196, 100), (433, 93), (667, 100), (844, 92)):
        d.rectangle((x, base - 36, x + 5, base), fill=1)
        d.rectangle((x + 8, base - 58, x + 13, base), fill=1)
        d.line((x - 8, base - 18, x + 22, base - 28), fill=1, width=2)
    for x in range(20, WORLD_WIDTH, 63):
        d.polygon([(x, 0), (x + 18, 0), (x + 10, 18 + (x % 37))], fill=1)
    return im


def pack_level(world: Image.Image) -> bytes:
    data = bytearray(BANK)
    for y in range(LEVEL_HEIGHT):
        for xbyte in range(WORLD_WIDTH // 8):
            value = 0
            for bit in range(8):
                value = (value << 1) | world.getpixel((xbyte * 8 + bit, y))
            data[y * (WORLD_WIDTH // 8) + xbyte] = value
    return bytes(data)


def render_view(world: Image.Image, position: int) -> bytes:
    bitmap = bytearray(6144)
    for y in range(LEVEL_HEIGHT):
        dest = zx_address(LEVEL_TOP + y) - 0x4000
        for xbyte in range(32):
            value = 0
            for bit in range(8):
                value = (value << 1) | world.getpixel((position + xbyte * 8 + bit, y))
            bitmap[dest + xbyte] = value
    return bytes(bitmap)


def attrs() -> bytes:
    values = bytearray(768)
    papers = (1, 1, 3, 3, 2, 2, 6, 6, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    for y, paper in enumerate(papers):
        for x in range(32):
            values[y * 32 + x] = (0x40 if y < 15 else 0) | (paper << 3) | 7
    return bytes(values)


def write_generated_source() -> None:
    lines = ["; Generated by build_ph2_scroll.py.", "ROW_TABLE:"]
    for y in range(LEVEL_HEIGHT):
        lines += [f"        DW 0x{0xC000 + y * 128:04X}", f"        DW 0x{zx_address(LEVEL_TOP + y):04X}"]
    for phase in range(1, 8):
        lines.append(f"PHASE_{phase}:")
        left_hi, right_hi = 0xA8 + phase, 0xB0 + phase
        for _ in range(32):
            lines += ["        LD A,(DE)", "        LD L,A", f"        LD H,0x{left_hi:02X}", "        LD A,(HL)",
                      "        EX AF,AF'", "        INC DE", "        LD A,(DE)", "        LD L,A",
                      f"        LD H,0x{right_hi:02X}", "        LD H,(HL)", "        EX AF,AF'", "        OR H",
                      "        LD (BC),A", "        INC BC"]
        lines.append("        RET")
    (HERE / "generated_rows.inc").write_text("\n".join(lines) + "\n", encoding="ascii")


def assemble() -> bytes:
    assembler = os.environ.get("SJASMPLUS") or shutil.which("sjasmplus")
    if not assembler:
        raise RuntimeError("sjasmplus is required; set SJASMPLUS to its executable path")
    binary = OUT / "ph2-scroll-code.bin"
    result = subprocess.run([assembler, f"--raw={binary}", "ph2_scroll.asm"], cwd=HERE, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"sjasmplus failed\n{result.stdout}\n{result.stderr}")
    return binary.read_bytes()


def shift_tables(page: bytearray) -> None:
    for phase in range(8):
        page[0x2800 + phase * 256 : 0x2900 + phase * 256] = bytes((v << phase) & 0xFF for v in range(256))
        page[0x3000 + phase * 256 : 0x3100 + phase * 256] = bytes(v >> (8 - phase) if phase else 0 for v in range(256))


def make_sna(code: bytes, level_one: bytes, level_two: bytes, initial: bytes) -> bytes:
    pages = [bytearray(BANK) for _ in range(8)]
    pages[2][:len(code)] = code
    shift_tables(pages[2])
    pages[0][:], pages[1][:] = level_one, level_two
    for bank in (5, 7):
        pages[bank][:6144], pages[bank][6144:6912] = initial, attrs()
    header = bytearray(27)
    header[19], header[23:25], header[25] = 4, struct.pack("<H", 0xBFF0), 1
    blob = bytearray(header) + pages[5] + pages[2] + pages[0] + struct.pack("<HBB", 0x8000, 0, 0)
    for bank in (1, 3, 4, 6, 7): blob += pages[bank]
    if len(blob) != SNA_SIZE: raise AssertionError(len(blob))
    return bytes(blob)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    level_one, level_two = make_level_one(), make_level_two()
    level_one.save(OUT / "prehistorik2-level1-panorama.png")
    level_two.save(OUT / "prehistorik2-level2-panorama.png")
    write_generated_source()
    code = assemble()
    snapshot = make_sna(code, pack_level(level_one), pack_level(level_two), render_view(level_one, 0))
    sna = OUT / "prehistorik2-levels1-2-1px-scroll.sna"; sna.write_bytes(snapshot)
    manifest = {"target":"Stock ZX Spectrum 128K PAL", "levels":[{"id":1,"width":WORLD_WIDTH},{"id":2,"width":WORLD_WIDTH}],
                "scroll":{"one_pixel_phases":8,"presentation_step_pixels":4,"view_width":VIEW_WIDTH,"active_scanlines":LEVEL_HEIGHT},
                "snapshot":{"bytes":len(snapshot),"sha256":hashlib.sha256(snapshot).hexdigest()}}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__": main()
