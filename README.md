# Prehistorik 2 levels 1 and 2 scrolling study

Technical next-step notes, including CPC disk-loader reconnaissance and the
monochrome-first Spectrum port plan, are in
[docs/cpc_recon_and_port_plan.md](docs/cpc_recon_and_port_plan.md).

The current reference snapshot is deliberately monochrome: both screen banks
have permanent bright-white-on-black attributes, so the scrolling hot path only
updates bitmap bytes. It cycles through 8-, 4- and 1-pixel camera increments
every 64 completed hidden-screen renders; capture reports the active step.
It also composites three generated 16x20 masked idle poses after the background
has been rendered to the hidden bank, using `(destination AND mask) OR ink`.

This stock Spectrum 128K technical/art study covers two complete four-screen
level strips, based on the CPC/CPC+ conversion's cave, jungle, bridge, and
crystal environments. It contains no characters, HUD, original game data, or
game code.

Level 1 scrolls right across its whole 1024-pixel strip and back; Level 2 then
starts and repeats the same path. The renderer supports all eight 1-pixel
phases. It keeps compact unshifted level bitmaps in banks 0 and 1 and joins
adjacent source bytes through 8x256 lookup tables, so both full levels fit in
the stock 128K memory map. Rendering always completes in the hidden screen bank
before the display flip.

## Separate source-asset sprite lab

`build_asset_lab.py` produces a separate SNA, leaving the scrolling benchmark
unchanged.  It requires a local source checkout containing `pre2atlas.png`, its
JSON frame map, and `L1.png`; set `PH2_ASSET_DIR` to that checkout.  The lab
uses authored player idle frames 25/27/30/35/36, dino 360/367, frog 393/395,
bush 420/433, and checkpoint traffic-light states 308/310. It reduces these
source pixels to 1-bit mask/ink data.

The lab intentionally keeps bank 5 visible and performs no screen flips. Each
object has its own 50 Hz tick divisor; only an object whose frame changes
restores its byte-aligned background rectangle and applies
`(destination AND mask) OR ink`. Initial tick phases are staggered to avoid
several expensive blits landing on the same PAL refresh.

```sh
PH2_ASSET_DIR=/path/to/prehistorik-2-phaserjs python3 build_asset_lab.py
```

The resulting snapshot is
`artifacts/prehistorik2-multi-sprite-idle-lab.sna`.

Build and capture:

```sh
python3 build_ph2_scroll.py
node capture_ph2_scroll.mjs /path/to/jsspeccy-core.wasm \
  artifacts/prehistorik2-levels1-2-1px-scroll.sna 6000 \
  2>artifacts/capture.json | \
ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size 320x240 -framerate 25 -i - \
  -vf scale=960:720:flags=neighbor -c:v libx264 -crf 18 -pix_fmt yuv420p \
  artifacts/prehistorik2-levels1-2-1px-scroll.mp4
```
