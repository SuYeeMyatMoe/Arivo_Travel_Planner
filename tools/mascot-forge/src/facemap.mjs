// Classifies front-facing vertices by the texel colour under their UV (visor-dark, eye-cyan, body-grey)
// and prints bounds so the expressive face overlay can be placed on the real visor.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import sharp from 'sharp';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read('../../assets/mascot/source/miibot_source.glb');
const tex = doc.getRoot().listTextures()[0];
const { data, info } = await sharp(Buffer.from(tex.getImage())).raw().toBuffer({ resolveWithObject: true });
const texel = (u, v) => {
  const x = Math.min(info.width - 1, Math.max(0, Math.floor(u * info.width)));
  const y = Math.min(info.height - 1, Math.max(0, Math.floor(v * info.height)));
  const i = (y * info.width + x) * info.channels;
  return [data[i], data[i + 1], data[i + 2]];
};
const groups = { cyan: [], dark: [], white: [] };
doc.getRoot().listScenes()[0].traverse((node) => {
  const mesh = node.getMesh(); if (!mesh) return;
  const m = node.getWorldMatrix();
  for (const prim of mesh.listPrimitives()) {
    const pos = prim.getAttribute('POSITION'), uv = prim.getAttribute('TEXCOORD_0');
    const v = [0, 0, 0], t = [0, 0];
    for (let i = 0; i < pos.getCount(); i++) {
      pos.getElement(i, v); uv.getElement(i, t);
      const x = m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12];
      const y = m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13];
      const z = m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14];
      if (z < 0.1) continue;
      const [r, g, b] = texel(t[0], t[1]);
      const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      if (b > 180 && g > 120 && r < 120) groups.cyan.push([x, y, z]);
      else if (lum > 0.8) groups.white.push([x, y, z]);
      else if (lum < 0.09) groups.dark.push([x, y, z]);
    }
  }
});
const bounds = (a) => a.length ? ['x', 'y', 'z'].map((k, i) => `${k}[${Math.min(...a.map((p) => p[i])).toFixed(3)},${Math.max(...a.map((p) => p[i])).toFixed(3)}]`).join(' ') : '-';
for (const [k, a] of Object.entries(groups)) console.log(k.padEnd(6), a.length, bounds(a));
// split cyan into left eye / right eye / mouth by position
const c = groups.cyan;
console.log('cyan L eye', bounds(c.filter((p) => p[0] < -0.08 && p[1] > 0.4)));
console.log('cyan R eye', bounds(c.filter((p) => p[0] > 0.08 && p[1] > 0.4)));
console.log('cyan mouth', bounds(c.filter((p) => Math.abs(p[0]) < 0.25 && p[1] < 0.4 && p[1] > 0.1)));
console.log('white chest', bounds(groups.white.filter((p) => p[1] < 0)));
// dark visor rows
for (let y = 0.8; y >= 0.05; y -= 0.05) {
  const s = groups.dark.filter((p) => p[1] <= y && p[1] > y - 0.05);
  if (s.length) console.log(`visor y ${y.toFixed(2)} x[${Math.min(...s.map((p) => p[0])).toFixed(2)},${Math.max(...s.map((p) => p[0])).toFixed(2)}] zmax ${Math.max(...s.map((p) => p[2])).toFixed(2)} n=${s.length}`);
}
