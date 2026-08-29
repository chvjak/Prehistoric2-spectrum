# Prehistorik 2 level 1 scrolling study

This is a stock Spectrum 128K technical/art study of the first Prehistorik 2
environment, using the CPC/CPC+ conversion as visual inspiration.  It is not a
game port and contains no character, HUD, original game data, or game code.

The 136-line cave/jungle strip is horizontally scrolled one source pixel per
completed presentation, from left to right for 64 pixels and then back again.
The source has eight pre-shifted variants per line.  Runtime work is therefore
only a 32-byte copy per active scanline; no individual bitmap bits are shifted
by the Z80.  The static ULA attributes provide the sunset-to-jungle gradient.

Build and capture:

```sh
python3 build_ph2_scroll.py
node capture_ph2_scroll.mjs \
  /workspace/sites/another-spectrum-rt45/public/emulator/jsspeccy-core.wasm \
  artifacts/prehistorik2-level1-1px-scroll.sna 750 \
  2>artifacts/capture.json | \
ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size 320x240 -framerate 25 -i - \
  -vf scale=960:720:flags=neighbor -c:v libx264 -crf 18 -pix_fmt yuv420p \
  artifacts/prehistorik2-level1-1px-scroll.mp4
```
