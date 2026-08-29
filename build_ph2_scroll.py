#!/usr/bin/env python3
"""Build a Spectrum 128K 1-pixel Prehistorik 2-style scrolling test.

The actual CPC+ game scrolls with hardware support.  This stock Spectrum
version instead stores each source line in eight pre-shifted variants.  A
frame picks the correct phase plus the coarse-byte offset, so the hot path is
32-byte LDIR copies per active scanline with no per-pixel shifting on the Z80.
"""
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
ROOT = HERE.parent
OUT = HERE / "artifacts"
BANK = 0x4000
SCREEN = 6912
SNA_SIZE = 131_103
LEVEL_TOP = 48
LEVEL_HEIGHT = 136
WORLD_WIDTH = 320
VIEW_WIDTH = 256
SOURCE_BANKS = (0, 1, 3)


def zx_address(y: int) -> int:
    return 0x4000 + ((y & 0xC0) << 5) + ((y & 7) << 8) + ((y & 0x38) << 2)


def make_world() -> Image.Image:
    """A wide cave/jungle strip, composed in the visual language of CPC PH2."""
    image = Image.new("1", (WORLD_WIDTH, LEVEL_HEIGHT), 0)
    draw = ImageDraw.Draw(image)
    rng = random.Random(0x504832)

    # Ground and irregular strata.  The low rock shelf is deliberately dense,
    # while high arches leave the attribute gradient visible behind it.
    floor = [110 + int(5 * __import__("math").sin(x / 17)) + rng.randrange(-2, 3)
             for x in range(WORLD_WIDTH)]
    ground = [(0, LEVEL_HEIGHT - 1), *[(x, floor[x]) for x in range(WORLD_WIDTH)],
              (WORLD_WIDTH - 1, LEVEL_HEIGHT - 1)]
    draw.polygon(ground, fill=1)
    for y in range(114, LEVEL_HEIGHT, 5):
        for x in range((y * 7) % 19, WORLD_WIDTH, 19):
            if y >= floor[min(x, WORLD_WIDTH - 1)]:
                draw.line((x, y, min(WORLD_WIDTH - 1, x + 12), y - 2), fill=0)

    # Long ledges, hanging rock and suspended platforms from a food-cave level.
    ledges = [(8, 76, 68), (95, 88, 151), (174, 66, 230), (248, 83, 308)]
    for left, y, right in ledges:
        draw.rectangle((left, y, right, y + 4), fill=1)
        draw.polygon([(left + 4, y + 5), (right - 5, y + 5),
                      (right - 13, y + 9), (left + 11, y + 8)], fill=1)
        for x in range(left + 7, right - 3, 13):
            draw.line((x, y + 5, x - 3, y + 11), fill=1)

    arches = [(20, 108, 49), (135, 106, 56), (251, 111, 45)]
    for x, base, width in arches:
        draw.ellipse((x, base - 65, x + width, base + 16), fill=1)
        draw.ellipse((x + 9, base - 53, x + width - 8, base + 14), fill=0)
        draw.rectangle((x, base, x + width, base + 21), fill=1)
        draw.rectangle((x + 10, base, x + width - 9, base + 14), fill=0)

    # Palm-like background silhouettes and stalactites; no actors or HUD.
    for cx, base in ((78, 105), (216, 92), (300, 110)):
        draw.rectangle((cx - 2, base - 47, cx + 2, base), fill=1)
        for direction in (-1, 1):
            for n in range(4):
                tipx = cx + direction * (10 + n * 6)
                tipy = base - 39 - n * 5
                draw.line((cx, base - 45, tipx, tipy), fill=1, width=2)
    for x, depth in ((4, 33), (55, 23), (113, 47), (188, 31), (276, 42)):
        draw.polygon([(x, 0), (x + 13, 0), (x + 7, depth)], fill=1)

    # White rock highlights and small floating food-like glints, but no sprite.
    for _ in range(150):
        x = rng.randrange(WORLD_WIDTH)
        y = rng.randrange(66, LEVEL_HEIGHT)
        if image.getpixel((x, y)):
            image.putpixel((x, y), 0)
            if x + 2 < WORLD_WIDTH and rng.random() < 0.5:
                image.putpixel((x + 2, y - 1), 1)
    for x, y in ((42, 55), (121, 58), (194, 47), (271, 53)):
        draw.rectangle((x, y, x + 4, y + 3), fill=1)
        draw.point((x + 2, y - 1), fill=1)
    return image


def phase_bytes(world: Image.Image) -> tuple[bytes, list[tuple[int, int]]]:
    """Pack each row as eight 40-byte phase images, page-aligned by row."""
    pages = [bytearray(BANK) for _ in SOURCE_BANKS]
    cursors = [0] * len(pages)
    current = 0
    table: list[tuple[int, int]] = []
    for y in range(LEVEL_HEIGHT):
        if cursors[current] + 320 > BANK:
            current += 1
            if current >= len(pages):
                raise RuntimeError("pre-shifted world exceeds its source banks")
        offset = cursors[current]
        table.append((SOURCE_BANKS[current], 0xC000 + offset))
        row = bytearray()
        for phase in range(8):
            for byte_x in range(40):
                value = 0
                for bit in range(8):
                    world_x = byte_x * 8 + bit + phase
                    pixel = world.getpixel((world_x, y)) if world_x < WORLD_WIDTH else 0
                    value = (value << 1) | pixel
                row.append(value)
        pages[current][offset : offset + 320] = row
        cursors[current] += 320
    return b"".join(pages), table


def render_view(world: Image.Image, position: int) -> bytes:
    bitmap = bytearray(6144)
    for y in range(LEVEL_HEIGHT):
        address = zx_address(LEVEL_TOP + y) - 0x4000
        for byte_x in range(32):
            value = 0
            for bit in range(8):
                value = (value << 1) | world.getpixel((position + byte_x * 8 + bit, y))
            bitmap[address + byte_x] = value
    return bytes(bitmap)


def attrs() -> bytes:
    """Band-limited Spectrum colour gradient, shared by every scroll phase."""
    values = bytearray(768)
    # ink white/brighter foreground; paper forms a sunset-to-jungle gradient.
    papers = (1, 1, 3, 3, 2, 2, 6, 6, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    for cell_y, paper in enumerate(papers):
        for cell_x in range(32):
            bright = 0x40 if cell_y < 15 else 0
            values[cell_y * 32 + cell_x] = bright | (paper << 3) | 7
    return bytes(values)


def write_rows(table: list[tuple[int, int]]) -> None:
    lines = ["; Generated by build_ph2_scroll.py; source bank, source pointer, destination.", "ROW_TABLE:"]
    for row, (bank, source) in enumerate(table):
        dest = zx_address(LEVEL_TOP + row)
        lines += [f"        DB {bank}", f"        DW 0x{source:04X}", f"        DW 0x{dest:04X}"]
    (HERE / "generated_rows.inc").write_text("\n".join(lines) + "\n", encoding="utf-8")


def assemble() -> bytes:
    binary = OUT / "ph2-scroll-code.bin"
    assembler = os.environ.get("SJASMPLUS") or shutil.which("sjasmplus")
    if not assembler:
        raise RuntimeError("sjasmplus is required; set SJASMPLUS to its executable path")
    result = subprocess.run(
        [assembler, f"--raw={binary}", "ph2_scroll.asm"],
        cwd=HERE,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise RuntimeError(f"sjasmplus failed\n{result.stdout}\n{result.stderr}")
    code = binary.read_bytes()
    if len(code) > 0x3E00:
        raise RuntimeError(f"fixed code too large for status block: {len(code)}")
    return code


def make_sna(code: bytes, sources: bytes, initial_screen: bytes) -> bytes:
    pages = [bytearray(BANK) for _ in range(8)]
    pages[2][:len(code)] = code
    for target, offset in zip(SOURCE_BANKS, range(0, len(SOURCE_BANKS) * BANK, BANK)):
        pages[target][:] = sources[offset : offset + BANK]
    pages[5][:6144] = initial_screen
    pages[5][6144:SCREEN] = attrs()
    # Both display banks need the same immutable gradient attributes. Runtime
    # updates only touch bitmap bytes in whichever one is hidden.
    pages[7][:6144] = initial_screen
    pages[7][6144:SCREEN] = attrs()
    header = bytearray(27)
    header[19] = 4
    header[23:25] = struct.pack("<H", 0xBFF0)
    header[25] = 1
    header[26] = 0
    blob = bytearray(header) + pages[5] + pages[2] + pages[0]
    blob += struct.pack("<HBB", 0x8000, 0, 0)
    for bank in (1, 3, 4, 6, 7):
        blob += pages[bank]
    if len(blob) != SNA_SIZE:
        raise AssertionError(len(blob))
    return bytes(blob)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    world = make_world()
    world.save(OUT / "ph2-level1-panorama.png")
    sources, table = phase_bytes(world)
    write_rows(table)
    code = assemble()
    snapshot = make_sna(code, sources, render_view(world, 0))
    sna = OUT / "prehistorik2-level1-1px-scroll.sna"
    sna.write_bytes(snapshot)
    manifest = {
        "target": "Stock ZX Spectrum 128K, 3.5469 MHz PAL",
        "reference": "Prehistorik 2 CPC/CPC+ level-1 cave/jungle visual language",
        "scroll": {
            "axis": "horizontal, 64-pixel travel in each direction",
            "step": "one source pixel after each completed render",
            "technique": "8 pre-shifted 320-pixel source rows; per-row 32-byte LDIR viewport copy",
            "active_scanlines": LEVEL_HEIGHT,
            "runtime_bit_shifts": 0,
        },
        "assets": {"source_bytes": len(sources), "code_bytes": len(code)},
        "snapshot": {"bytes": len(snapshot), "sha256": hashlib.sha256(snapshot).hexdigest()},
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
