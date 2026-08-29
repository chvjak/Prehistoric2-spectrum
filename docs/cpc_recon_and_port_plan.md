# CPC reconnaissance and monochrome Spectrum port plan

## Scope and evidence

This is a clean-room technical plan for a stock ZX Spectrum 128K port study.
It records behaviour and data-flow observations from the CPC disk loader; it
does not copy CPC source, game code, graphics, music, or level data.

The analysed input was the archived CPC disk image identified as
`Prehistorik_2-Return_to_Hungerland.dsk` (80 tracks, extended DSK, 389,376
bytes). CPCRulez describes the normal CPC version as using horizontal overscan
and a hard multidirectional scroll. Its CPC+ path additionally uses split
display, palette effects and hardware sprites. Those CPC+ facilities are not
part of the Spectrum target.

Sources:

- https://cpcrulez.fr/prehistorik_2-return_to_hungerland.htm
- https://www.cpc-power.com/index.php?num=1682&page=detail

## Disk layout

The loader has a deliberately simple, chunked layout rather than one monolithic
executable.

| Files | Packed bytes on disk | Observation |
| --- | ---: | --- |
| `PREHIST2` | 2,816 payload bytes | Initial binary, loaded at `0x2F00`; entry jumps to `0x37C6`. |
| `PREHIST2.000` | 12,416 | First packed module. |
| `PREHIST2.001` | 20,864 | Second packed module; two CP/M extents. |
| `PREHIST2.002` | 24,832 | Third packed module; two CP/M extents. |
| `PREHIST2.010` .. `.034` | 2,176 .. 6,912 each | 25 later streamed chunks, 125,952 bytes total. |

This supports a port architecture based on small level/object chunks and an
explicit loader, rather than attempting to keep full CPC screens resident.

## Annotated loader landmarks

The following annotations are behavioural labels, not reconstructed source.
Addresses refer to the first-stage loader after its AMSDOS header.

| CPC address | Behaviour | Spectrum implication |
| --- | --- | --- |
| `0x37C6` | Entry: disables interrupts and moves the stack to `0x3F00`. | Use a normal Spectrum startup and IM 2; do not inherit the CPC bootstrap. |
| `0x37CA` .. `0x37D6` | Writes a uniform Gate Array pen/colour state through `0x7Fxx`. | Replace with one-time fill of both Spectrum attribute pages: `INK 7`, `PAPER 0`, no BRIGHT/FLASH. |
| `0x37D7` .. `0x37E2` | Clears `0xC000..0xFFFF` with an `LDIR` overlap-fill idiom. | Equivalent only for transient buffers; Spectrum screens remain bank 5 and bank 7. |
| `0x37E3` .. `0x37F2` | Installs a temporary unpacking routine at `0xA300`, then calls its entry at `0x8000`. | Keep a host-side packer; use a small streaming decoder only if level chunks cannot fit in the 128K map. |
| `0x380E` .. `0x3816` | Changes CPC display/ROM configuration through Gate Array ports. | No direct counterpart; select Spectrum RAM banks via `0x7FFD` only at defined frame boundaries. |
| `0x3827` .. `0x388D` | Loads packed blocks, decompresses them into temporary RAM, copies/repages them, then jumps to `0x6000`. | This is the useful model: deterministic load -> decode -> place into the runtime bank map -> enter level runtime. |
| `0x38C9` .. `0x38D8` | Constructs `prehist2.000`-style filenames and uses the CPC cassette/disk firmware open/read/close routines (`0xBC77`, `0xBC83`, `0xBC7A`). | Replace with a level-package boundary in the build. A stock `.sna` has no runtime disk loader; package the first playable level resident. |
| `0x3939` onward | Byte-stream decoder copied to `0xA300`; it reads control bits and emits variable-length output. | Treat compression as a data-format concern. Do not port this decoder until measurements show that a simpler RLE/LZ decoder is insufficient. |

## What transfers, and what does not

Transfer the game-level decomposition: scrolling world, collision tiles,
object/trigger list, foreground/background layers, and streamable level chunks.

Do not translate the CPC renderer line-for-line. The CPC implementation relies
on a different video layout, CRTC timing/overscan, Gate Array palette state and,
for CPC+, ASIC hardware sprites. Spectrum has neither byte-addressable
horizontal display start nor a sprite plane. Its visible bitmap must be drawn
in fixed 256x192 screen memory.

## Monochrome-first target

Use a single fixed attribute value on every cell (`0x07`: white ink on black
paper) in both screen banks. Attribute RAM is initialised once and is excluded
from the per-frame renderer. All art conversion produces a 1-bit mask/ink
bitmap and all sprite composition is bitmap-only.

This removes 768 attribute writes, attribute conflicts, palette conversion and
per-frame colour decisions. It also makes performance measurements directly
attributable to scrolling, background reconstruction and masked sprites.

## Proposed 128K map

| Bank / region | Role |
| --- | --- |
| Bank 5 | Screen A: 6,144-byte bitmap + permanent uniform attributes. |
| Bank 7 | Screen B: same layout; never write the displayed screen. |
| Bank 0 | Current level static bitmap/tile source, collision and object data. |
| Bank 1 | Next chunk / streamed source and decompression workspace. |
| Bank 2 | Shift/join tables and pre-shifted sprite frames. |
| Fixed `0xC000` page | Engine, camera/object state, interrupt handler, input and music player. |
| Fixed low memory | Startup, IM 2 vector table and small dispatch tables only. |

The exact bank assignment can move after profiling, but the two screen banks
must stay dedicated. No level data may share them.

## Renderer plan

1. **Reference slice.** Convert a small original-style test course into a
   monochrome tile/object package. Full 256x192 bitmap, no HUD, no character
   initially. Verify right and left motion in JSSpeccy from a `.sna`.
2. **Correct back-buffer renderer.** Rebuild the next screen from a world
   bitmap/tile source into the hidden bank, then flip `0x7FFD`. Include an
   explicit displayed-bank flag in RAM so capture always reads the physical
   display bank. This preserves the earlier fix for apparent interleaving.
3. **Measure three camera modes.**
   - 8-pixel camera steps, no phase work;
   - 4-pixel updates using four source phases;
   - all eight 1-pixel phases using byte-join tables.
   Record frame cost and displayed FPS with no sprites. Select the fastest mode
   that remains visually acceptable; do not assume the CPC's smoothness is
   achievable at 50 Hz on a stock Spectrum.
4. **Add masked objects.** Draw sprites only after the background has been
   composed in the hidden bank. Objects carry a feet anchor, mask, ink data,
   clipping bounds and a dirty bounding box for profiling. Add the player only
   after the camera benchmark is stable.
5. **Collision and gameplay.** Keep collision in logical tile coordinates;
   camera position is presentation-only. Run input/physics at 50 Hz even if
   the complete background is presented at a lower rate.
6. **Level streaming.** Package the full Level 1 as small binary chunks,
   then load/decode the required window into non-screen banks. Add Level 2
   only after Level 1 has repeatable memory and timing margins.
7. **Colour, later.** If the monochrome route is sound, introduce a separate,
   precomputed attribute delta stream. It must remain outside the hot bitmap
   draw loop and be applied to the hidden bank before the flip.

## Performance gates

| Gate | Required result |
| --- | --- |
| Static two-bank flip | No tearing or alternating-bank capture artefact. |
| Monochrome background | Measured complete hidden-bank composition cost for all three camera modes. |
| One sprite | Correct mask composition over arbitrary background; no opaque rectangle. |
| Gameplay slice | Stable controls and collision at 50 Hz; camera FPS documented separately. |
| Full Level 1 | Fits in 128K with a declared streaming format and no writes to displayed bank. |

The first deliverable should therefore be a monochrome, controllable Level 1
vertical slice, not a colour conversion and not a direct translation of the
CPC video code.
