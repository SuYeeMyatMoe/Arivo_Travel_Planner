// Packs captured frames into per-state sprite sheets and copies posters/turnarounds into assets/mascot.
// Frames come from the viewer (npm run preview → __ari.capture(...)) and land in out/captures.
//   sp_<state>_<00..15>.png  → assets/mascot/sprites/ari_<state>.webp  (4×4 grid, 256px cells)
//   poster_*.png, turn_*.png → assets/mascot/posters/*.webp
import sharp from 'sharp';
import { readdir, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const CAP = resolve(ROOT, 'out/captures');
const ASSETS = resolve(ROOT, '../../assets/mascot');
const CELL = 256, COLS = 4, FRAMES = 16;
const STATES = {
  idle_float: { loop: true, fps: 4 },
  listening: { loop: true, fps: 5.33 },
  thinking: { loop: true, fps: 5.33 },
  talking: { loop: true, fps: 10 },
  pointing: { loop: false, fps: 8 },
  warning: { loop: true, fps: 8 },
  excited: { loop: false, fps: 10 },
  offline: { loop: true, fps: 4 },
};

await mkdir(resolve(ASSETS, 'sprites'), { recursive: true });
await mkdir(resolve(ASSETS, 'posters'), { recursive: true });

const manifest = { cell: CELL, columns: COLS, frames: FRAMES, states: {} };
for (const [state, info] of Object.entries(STATES)) {
  const frames = await Promise.all(
    Array.from({ length: FRAMES }, (_, i) => sharp(resolve(CAP, `sp_${state}_${String(i).padStart(2, '0')}.png`)).resize(CELL, CELL).png().toBuffer()),
  );
  const file = `ari_${state}.webp`;
  await sharp({ create: { width: CELL * COLS, height: CELL * Math.ceil(FRAMES / COLS), channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(frames.map((input, i) => ({ input, left: (i % COLS) * CELL, top: Math.floor(i / COLS) * CELL })))
    .webp({ quality: 88, alphaQuality: 100 })
    .toFile(resolve(ASSETS, 'sprites', file));
  manifest.states[state] = { file, ...info };
}
await writeFile(resolve(ASSETS, 'sprites', 'manifest.json'), JSON.stringify(manifest, null, 2));

for (const f of (await readdir(CAP)).filter((f) => /^(poster|turn)_.*\.png$/.test(f))) {
  await sharp(resolve(CAP, f)).webp({ quality: 90, alphaQuality: 100 }).toFile(resolve(ASSETS, 'posters', f.replace(/\.png$/, '.webp')));
}
console.log('sprites + posters written');
