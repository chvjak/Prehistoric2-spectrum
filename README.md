# Prehistorik 2 levels 1 and 2 scrolling study

Technical next-step notes, including CPC disk-loader reconnaissance and the
monochrome-first Spectrum port plan, are in
[docs/cpc_recon_and_port_plan.md](docs/cpc_recon_and_port_plan.md).

The current reference snapshot is deliberately monochrome: both screen banks
have permanent bright-white-on-black attributes, so the scrolling hot path only
updates bitmap bytes. It cycles through 8-, 4- and 1-pixel camera increments
every 64 completed hidden-screen renders; capture reports the active step.

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
