// Slices the base mesh along world Y and reports the X/Z extents of each slice.
// Used to place gear (hat brim, scarf, emblem) against the real silhouette.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(process.argv[2] ?? '../../assets/mascot/source/miibot_source.glb');
const scene = doc.getRoot().listScenes()[0];
const pts = [];
scene.traverse((node) => {
  const mesh = node.getMesh();
  if (!mesh) return;
  const m = node.getWorldMatrix();
  for (const prim of mesh.listPrimitives()) {
    const pos = prim.getAttribute('POSITION');
    const v = [0, 0, 0];
    for (let i = 0; i < pos.getCount(); i += 3) {
      pos.getElement(i, v);
      const x = m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12];
      const y = m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13];
      const z = m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14];
      pts.push([x, y, z]);
    }
  }
});
const step = 0.05;
for (let y = 1.0; y >= -1.0; y -= step) {
  const s = pts.filter((p) => p[1] <= y && p[1] > y - step);
  if (!s.length) continue;
  const xs = s.map((p) => p[0]), zs = s.map((p) => p[2]);
  const f = (n) => n.toFixed(2).padStart(6);
  console.log(`y ${f(y)}  x[${f(Math.min(...xs))},${f(Math.max(...xs))}]  z[${f(Math.min(...zs))},${f(Math.max(...zs))}]  n=${s.length}`);
}
