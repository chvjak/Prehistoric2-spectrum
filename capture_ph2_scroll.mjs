#!/usr/bin/env node
// Capture only the stable, post-render Spectrum refreshes (25 fps).
import fs from "node:fs";
import { once } from "node:events";

const [wasmPath, snapshotPath, refreshText = "750"] = process.argv.slice(2);
if (!wasmPath || !snapshotPath) throw new Error("usage: capture_ph2_scroll.mjs core.wasm demo.sna [refreshes]");
const wasm = fs.readFileSync(wasmPath);
const snapshot = fs.readFileSync(snapshotPath);
const { instance } = await WebAssembly.instantiate(wasm);
const core = instance.exports;
let memory = new Uint8Array(core.memory.buffer);
const registers = new Uint16Array(core.memory.buffer, core.REGISTERS, 12);
const page = (bank) => core.MACHINE_MEMORY + bank * 0x4000;
const load = (bank, offset) => memory.set(snapshot.subarray(offset, offset + 0x4000), page(bank));
core.setMachineType(128);
memory.fill(0, page(8), page(10));
load(5, 27); load(2, 27 + 0x4000); load(0, 27 + 0x8000);
let offset = 49183; for (const bank of [1, 3, 4, 6, 7]) { load(bank, offset); offset += 0x4000; }
registers.fill(0); registers[10] = 0xbff0;
core.setPC(0x8000); core.setIFF1(0); core.setIFF2(0); core.setIM(1); core.setHalted(false);
core.writePort(0x00fe, 0); core.writePort(0x7ffd, 0); core.setTStates(0);
const fixed = (address) => page(2) + address - 0x8000;
const u8 = (a) => memory[fixed(a)];
const u16 = (a) => u8(a) | (u8(a+1) << 8);
const palette = [[0,0,0],[32,48,192],[192,64,16],[192,64,192],[64,176,16],[80,192,176],[224,192,16],[192,192,192],[0,0,0],[48,64,255],[255,64,48],[255,112,240],[80,224,16],[80,224,255],[255,232,80],[255,255,255]];
function frame() {
  memory = new Uint8Array(core.memory.buffer);
  const screen = memory.subarray(page(u8(0xbb07) ? 7 : 5), page(u8(0xbb07) ? 7 : 5) + 6912);
  const out = Buffer.allocUnsafe(320 * 240 * 3); let q = 0;
  const pixel = (i) => { const c = palette[i & 15]; out[q++] = c[0]; out[q++] = c[1]; out[q++] = c[2]; };
  for (let y=0;y<24;y++) for(let x=0;x<320;x++) pixel(0);
  for (let y=0;y<192;y++) {
    for(let x=0;x<32;x++) pixel(0);
    const row = ((y & 0xc0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2);
    for(let x=0;x<32;x++) { let bits=screen[row+x], attr=screen[6144 + (y >> 3) * 32 + x]; const ink=((attr&0x40)>>3)|(attr&7), paper=(attr&0x78)>>3; for(let b=0;b<8;b++){pixel(bits&0x80?ink:paper);bits=(bits<<1)&255;} }
    for(let x=0;x<32;x++) pixel(0);
  }
  for (let y=0;y<24;y++) for(let x=0;x<320;x++) pixel(0);
  return out;
}
let written = 0;
for (let refresh = 1; refresh <= Number(refreshText); refresh++) {
  if (core.runFrame() !== 0) throw new Error(`emulator status at ${refresh}`);
  // The first refresh begins the 27ms copy.  Every even refresh is the full
  // frame held by HALT, giving a clean 25fps capture without tearing.
  if ((refresh & 1) !== 0) continue;
  if (!process.stdout.write(frame())) await once(process.stdout, "drain");
  written++;
}
process.stderr.write(`${JSON.stringify({
  refreshes:Number(refreshText), framesWritten:written, renderedFrames:u16(0xbb04),
  signature: Buffer.from([u8(0xbb00),u8(0xbb01),u8(0xbb02),u8(0xbb03)]).toString(),
  level:u8(0xbb06) + 1, displayedBank:u8(0xbb07)?7:5, pc:core.getPC(),
})}\n`);
