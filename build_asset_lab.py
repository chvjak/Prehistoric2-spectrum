#!/usr/bin/env python3
"""Build the single-screen, independently animated PH2 sprite laboratory."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE / "artifacts"
ATLAS_ROOT = Path(os.environ.get("PH2_ASSET_DIR", "/tmp/ph2-phaser"))
ATLAS_PATH = ATLAS_ROOT / "assets/spritesheets/pre2atlas.png"
ATLAS_JSON = ATLAS_ROOT / "assets/spritesheets/pre2atlas.json"
TILESET_PATH = ATLAS_ROOT / "assets/tilesets/L1.png"
BANK, SNA_SIZE = 0x4000, 131_103


@dataclass(frozen=True)
class SpriteSpec:
    name: str
    keys: tuple[str, ...]
    x: int
    y: int
    width: int
    height: int
    period: int
    edge_threshold: float
    fill_threshold: float


SPRITES = (
    SpriteSpec("player", ("25", "27", "30", "35", "36"), 104, 80, 32, 40, 8, 58, 184),
    SpriteSpec("dino", ("360", "367"), 144, 96, 48, 32, 12, 54, 174),
    SpriteSpec("frog", ("393", "395"), 64, 96, 48, 32, 10, 52, 172),
    SpriteSpec("bush", ("420", "433"), 8, 104, 56, 24, 16, 45, 166),
    SpriteSpec("checkpoint", ("308", "310"), 200, 56, 48, 72, 25, 50, 170),
)


def zx_address(y: int) -> int:
    return 0x4000 + ((y & 0xC0) << 5) + ((y & 7) << 8) + ((y & 0x38) << 2)


def require_sources() -> None:
    missing = [str(path) for path in (ATLAS_PATH, ATLAS_JSON, TILESET_PATH) if not path.exists()]
    if missing:
        raise RuntimeError("Set PH2_ASSET_DIR to the PH2 atlas checkout. Missing: " + ", ".join(missing))


def frame(atlas: Image.Image, atlas_json: dict, key: str) -> Image.Image:
    spec = atlas_json["frames"][key]["frame"]
    return atlas.crop((spec["x"], spec["y"], spec["x"] + spec["w"], spec["y"] + spec["h"]))


def mono_values(image: Image.Image) -> tuple[list[int], list[int]]:
    rgba = image.convert("RGBA")
    opaque: list[int] = []
    ink: list[int] = []
    bayer = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = rgba.getpixel((x, y))
            solid = a >= 32
            light = max(r, g, b) * 0.58 + (r * 0.2126 + g * 0.7152 + b * 0.0722) * 0.42
            threshold = (bayer[y & 3][x & 3] + 0.5) * 16
            opaque.append(int(solid))
            ink.append(int(solid and light >= threshold))
    return opaque, ink


def traced_values(image: Image.Image, edge_threshold: float, fill_threshold: float) -> tuple[list[int], list[int]]:
    """Make clean 1-bit sprite art: silhouette, feature edges, solid highlights."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = list(rgba.getdata())
    opaque = [int(pixel[3] >= 32) for pixel in pixels]
    light = [
        max(r, g, b) * 0.58 + (r * 0.2126 + g * 0.7152 + b * 0.0722) * 0.42
        for r, g, b, _ in pixels
    ]

    def neighbours(index: int, diagonals: bool = True):
        x, y = index % width, index // width
        offsets = (
            ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
            if diagonals
            else ((0, -1), (-1, 0), (1, 0), (0, 1))
        )
        for dx, dy in offsets:
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height:
                yield ny * width + nx

    contour = [False] * len(pixels)
    feature = [False] * len(pixels)
    highlight = [False] * len(pixels)
    for index, solid in enumerate(opaque):
        if not solid:
            continue
        adjacent = list(neighbours(index))
        contour[index] = len(adjacent) < 8 or any(not opaque[n] for n in adjacent)
        highlight[index] = light[index] >= fill_threshold
        r, g, b, _ = pixels[index]
        for other in neighbours(index, diagonals=False):
            if not opaque[other] or light[index] <= light[other]:
                continue
            rr, gg, bb, _ = pixels[other]
            colour_jump = max(abs(r - rr), abs(g - gg), abs(b - bb))
            if light[index] - light[other] >= edge_threshold or colour_jump >= edge_threshold * 1.45:
                feature[index] = True
                break

    # Reject Bayer-like single-pixel noise while retaining every silhouette pixel.
    solid_highlight = [
        value and sum(highlight[n] for n in neighbours(index)) >= 2
        for index, value in enumerate(highlight)
    ]
    stable_feature = [
        value and any(contour[n] or feature[n] or solid_highlight[n] for n in neighbours(index))
        for index, value in enumerate(feature)
    ]
    ink = [int(contour[i] or stable_feature[i] or solid_highlight[i]) for i in range(len(pixels))]
    return opaque, ink


def stamp(canvas: Image.Image, source: Image.Image, x: int, y: int) -> None:
    canvas.alpha_composite(source, (x, y))


def build_background(tileset: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (256, 192), (0, 0, 0, 255))
    ground = tileset.crop((0, 288, 176, 384))
    stamp(canvas, ground, -14, 120)
    stamp(canvas, ground, 140, 120)
    stamp(canvas, tileset.crop((0, 208, 96, 286)), 72, 134)
    return canvas


def bitmap_from_image(image: Image.Image) -> bytes:
    _, ink = mono_values(image)
    result = bytearray(6144)
    for y in range(192):
        dest = zx_address(y) - 0x4000
        for xbyte in range(32):
            value = 0
            for bit in range(8):
                value = (value << 1) | ink[y * 256 + xbyte * 8 + bit]
            result[dest + xbyte] = value
    return bytes(result)


def sprite_canvas(atlas: Image.Image, atlas_json: dict, spec: SpriteSpec, key: str) -> Image.Image:
    source = frame(atlas, atlas_json, key)
    if source.width > spec.width or source.height > spec.height:
        raise ValueError(f"{spec.name} frame {key} does not fit {spec.width}x{spec.height}: {source.size}")
    result = Image.new("RGBA", (spec.width, spec.height), (0, 0, 0, 0))
    result.alpha_composite(source, ((spec.width - source.width) // 2, spec.height - source.height))
    return result


def write_generated(atlas: Image.Image, atlas_json: dict, background: Image.Image) -> None:
    (HERE / "generated_asset_lab_background.bin").write_bytes(bitmap_from_image(background))
    lines = ["; Generated by build_asset_lab.py from real PH2 atlas frames."]
    for spec in SPRITES:
        label = spec.name.upper()
        lines.append(f"{label}_ROWS_SOURCE:")
        for y in range(spec.height):
            lines.append(f"        DW 0x{zx_address(spec.y + y) + 0x6000 + spec.x // 8:04X}")
        lines.append(f"{label}_ROWS_SCREEN:")
        for y in range(spec.height):
            lines.append(f"        DW 0x{zx_address(spec.y + y) + spec.x // 8:04X}")
        lines.append(f"{label}_FRAME_TABLE:")
        for index in range(len(spec.keys)):
            lines.append(f"        DW {label}_FRAME{index}")
        for index, key in enumerate(spec.keys):
            opaque, ink = traced_values(
                sprite_canvas(atlas, atlas_json, spec, key), spec.edge_threshold, spec.fill_threshold
            )
            lines.append(f"{label}_FRAME{index}:")
            for y in range(spec.height):
                values: list[int] = []
                for byte in range(spec.width // 8):
                    mask = 0
                    data = 0
                    for bit in range(8):
                        pixel = y * spec.width + byte * 8 + bit
                        mask = (mask << 1) | (opaque[pixel] ^ 1)
                        data = (data << 1) | ink[pixel]
                    values.extend((mask, data))
                lines.append("        DB " + ", ".join(f"0x{value:02X}" for value in values))
    (HERE / "generated_asset_lab.inc").write_text("\n".join(lines) + "\n", encoding="ascii")


def assemble() -> bytes:
    assembler = os.environ.get("SJASMPLUS") or shutil.which("sjasmplus")
    if not assembler:
        raise RuntimeError("sjasmplus is required; set SJASMPLUS")
    binary = OUT / "ph2-traced-multi-sprite-lab-code.bin"
    result = subprocess.run(
        [assembler, f"--raw={binary}", "ph2_asset_lab.asm"],
        cwd=HERE,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise RuntimeError(f"sjasmplus failed\n{result.stdout}\n{result.stderr}")
    return binary.read_bytes()


def make_sna(code: bytes, background: bytes) -> bytes:
    pages = [bytearray(BANK) for _ in range(8)]
    pages[2][:len(code)] = code
    pages[5][:6144] = background
    pages[5][6144:6912] = bytes([0x47]) * 768
    header = bytearray(27)
    header[19], header[23:25], header[25] = 4, struct.pack("<H", 0xBFF0), 1
    blob = bytearray(header) + pages[5] + pages[2] + pages[0] + struct.pack("<HBB", 0x8000, 0, 0)
    for bank in (1, 3, 4, 6, 7):
        blob += pages[bank]
    if len(blob) != SNA_SIZE:
        raise AssertionError(len(blob))
    return bytes(blob)


def main() -> None:
    require_sources()
    OUT.mkdir(exist_ok=True)
    atlas = Image.open(ATLAS_PATH).convert("RGBA")
    atlas_json = json.loads(ATLAS_JSON.read_text(encoding="utf-8"))
    background = build_background(Image.open(TILESET_PATH).convert("RGBA"))
    background.save(OUT / "prehistorik2-multi-sprite-lab-background.png")
    write_generated(atlas, atlas_json, background)
    code = assemble()
    packed_background = (HERE / "generated_asset_lab_background.bin").read_bytes()
    snapshot = make_sna(code, packed_background)
    sna = OUT / "prehistorik2-traced-multi-sprite-idle-lab.sna"
    sna.write_bytes(snapshot)
    manifest = {
        "target": "Stock ZX Spectrum 128K PAL",
        "screen": "single visible bank 5; no runtime screen flips",
        "source_assets": {
            spec.name: {"frames": list(map(int, spec.keys)), "period_50hz_ticks": spec.period}
            for spec in SPRITES
        },
        "compositor": {
            "formula": "(destination AND mask) OR ink",
            "restore": "only the changed object's byte-aligned rectangle",
            "attributes": "fixed bright-white ink on black paper",
            "sprite_conversion": "alpha mask plus traced contour/internal edges and solid highlights; no dithering",
        },
        "snapshot": {
            "bytes": len(snapshot),
            "sha256": hashlib.sha256(snapshot).hexdigest(),
        },
    }
    (OUT / "traced-multi-sprite-lab-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
