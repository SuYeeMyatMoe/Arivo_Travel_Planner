// Ari mascot forge.
// Upgrades the Miibot base model (CC-BY-4.0, itsmejhade) into Ari, the Arivo explorer:
//   - explorer bucket hat with route-stitched band, boarding-pass tucked in the band and a signal beacon
//   - wind-swept volt scarf with fluttering tails
//   - compass-core chest emblem (replaces the "AI" logo) with an animated needle
//   - expressive emissive face (eyes + mouth) on a glass visor plate, driven by morph targets
//   - 8 state clips: idle_float, listening, thinking, talking, pointing, warning, excited, offline
// Output: assets/mascot/ari_explorer.glb (optimized) and assets/mascot/ari_explorer.meta.json
import { NodeIO } from '@gltf-transform/core';
import {
  ALL_EXTENSIONS,
  EXTMeshoptCompression,
  KHRMaterialsEmissiveStrength,
  KHRMaterialsClearcoat,
  KHRMaterialsSheen,
} from '@gltf-transform/extensions';
import { dedup, prune, simplifyPrimitive, meshopt, quantize, textureCompress } from '@gltf-transform/functions';
import { MeshoptEncoder, MeshoptSimplifier, MeshoptDecoder } from 'meshoptimizer';
import sharp from 'sharp';
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const REPO = resolve(import.meta.dirname, '../../..');
const SRC = resolve(REPO, 'assets/mascot/source/miibot_source.glb');
const OUT_DIR = resolve(REPO, 'assets/mascot');
const RAW = process.argv.includes('--raw'); // skip optimization for fast iteration

// ---------------------------------------------------------------- palette (design/tokens.json)
const C = {
  ink950: '#070B16',
  ink800: '#18203A',
  paper: '#FAF7F0',
  volt: '#C8F53C',
  signal: '#3ED3F5',
  lantern: '#FFB547',
  sand: '#C8A56E',
  sandDark: '#9C7C4B',
};
const lin = (hex) => new THREE.Color(hex).toArray(); // THREE.Color converts sRGB hex to linear

await MeshoptEncoder.ready;
await MeshoptDecoder.ready;
await MeshoptSimplifier.ready;

const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({ 'meshopt.encoder': MeshoptEncoder, 'meshopt.decoder': MeshoptDecoder });
const doc = await io.read(SRC);
const root = doc.getRoot();
const buffer = root.listBuffers()[0];
const scene = root.listScenes()[0];

// ---------------------------------------------------------------- sample the real face surface
// Height field of the front of the head: max z per (x, y) cell, used to seat the visor plate.
const hf = (() => {
  const cell = 0.012, x0 = -0.66, y0 = 0.0, nx = 110, ny = 80;
  const h = new Float32Array(nx * ny).fill(-Infinity);
  scene.traverse((node) => {
    const mesh = node.getMesh();
    if (!mesh) return;
    const m = node.getWorldMatrix();
    for (const prim of mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION');
      const v = [0, 0, 0];
      for (let i = 0; i < pos.getCount(); i++) {
        pos.getElement(i, v);
        const x = m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12];
        const y = m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13];
        const z = m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14];
        if (z < 0.1) continue;
        const ix = Math.floor((x - x0) / cell), iy = Math.floor((y - y0) / cell);
        if (ix < 0 || iy < 0 || ix >= nx || iy >= ny) continue;
        h[iy * nx + ix] = Math.max(h[iy * nx + ix], z);
      }
    }
  });
  const sample = (x, y) => {
    const ix = Math.round((x - x0) / cell), iy = Math.round((y - y0) / cell);
    let best = -Infinity;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const j = (iy + dy) * nx + (ix + dx);
      if (h[j] > best) best = h[j];
    }
    return best;
  };
  return { sample };
})();

// Visor plate: a smooth quadratic surface fitted to the face, lifted above every bump it covers.
const FACE = { cx: 0, cy: 0.43, a: 0.445, b: 0.255 };
const plate = (() => {
  const rows = [], rhs = [];
  for (let r = 0; r <= 1.0001; r += 0.05) for (let t = 0; t < Math.PI * 2; t += Math.PI / 24) {
    const x = FACE.cx + FACE.a * 1.05 * r * Math.cos(t), y = FACE.cy + FACE.b * 1.05 * r * Math.sin(t);
    const z = hf.sample(x, y);
    if (!Number.isFinite(z)) continue;
    rows.push([1, x, y, x * x, x * y, y * y]);
    rhs.push(z);
  }
  // normal equations 6x6
  const n = 6, A = Array.from({ length: n }, () => new Float64Array(n)), B = new Float64Array(n);
  rows.forEach((row, k) => { for (let i = 0; i < n; i++) { B[i] += row[i] * rhs[k]; for (let j = 0; j < n; j++) A[i][j] += row[i] * row[j]; } });
  for (let i = 0; i < n; i++) { // gaussian elimination
    let p = i; for (let k = i + 1; k < n; k++) if (Math.abs(A[k][i]) > Math.abs(A[p][i])) p = k;
    [A[i], A[p]] = [A[p], A[i]]; [B[i], B[p]] = [B[p], B[i]];
    for (let k = i + 1; k < n; k++) { const f = A[k][i] / A[i][i]; for (let j = i; j < n; j++) A[k][j] -= f * A[i][j]; B[k] -= f * B[i]; }
  }
  const c = new Float64Array(n);
  for (let i = n - 1; i >= 0; i--) { let s = B[i]; for (let j = i + 1; j < n; j++) s -= A[i][j] * c[j]; c[i] = s / A[i][i]; }
  const f = (x, y) => c[0] + c[1] * x + c[2] * y + c[3] * x * x + c[4] * x * y + c[5] * y * y;
  let lift = 0;
  rows.forEach((row, k) => { lift = Math.max(lift, rhs[k] - f(row[1], row[2])); });
  lift += 0.006;
  const z = (x, y) => f(x, y) + lift;
  const normal = (x, y) => {
    const e = 0.002;
    const dzdx = (z(x + e, y) - z(x - e, y)) / (2 * e), dzdy = (z(x, y + e) - z(x, y - e)) / (2 * e);
    return new THREE.Vector3(-dzdx, -dzdy, 1).normalize();
  };
  console.log(`visor plate lift ${lift.toFixed(4)}`);
  return { z, normal };
})();

// ---------------------------------------------------------------- geometry → glTF helpers
const materials = {};
function material(name, hex, { metal = 0, rough = 0.6, emissive, strength = 1, doubleSided = false, clearcoat = 0, sheen } = {}) {
  const m = doc.createMaterial(name).setBaseColorFactor([...lin(hex), 1]).setMetallicFactor(metal).setRoughnessFactor(rough).setDoubleSided(doubleSided);
  if (emissive) {
    m.setEmissiveFactor(lin(emissive));
    if (strength !== 1) m.setExtension('KHR_materials_emissive_strength', doc.createExtension(KHRMaterialsEmissiveStrength).createEmissiveStrength().setEmissiveStrength(strength));
  }
  if (clearcoat) m.setExtension('KHR_materials_clearcoat', doc.createExtension(KHRMaterialsClearcoat).createClearcoat().setClearcoatFactor(clearcoat).setClearcoatRoughnessFactor(0.05));
  if (sheen) m.setExtension('KHR_materials_sheen', doc.createExtension(KHRMaterialsSheen).createSheen().setSheenColorFactor(lin(sheen)).setSheenRoughnessFactor(0.6));
  materials[name] = m;
  return m;
}

function accessor(type, array) {
  return doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
}

function primitiveFrom(geometry, mat) {
  const g = geometry.index ? geometry : geometry; // indexed or not, both supported
  if (!g.getAttribute('normal')) g.computeVertexNormals();
  const prim = doc.createPrimitive()
    .setAttribute('POSITION', accessor('VEC3', new Float32Array(g.getAttribute('position').array)))
    .setAttribute('NORMAL', accessor('VEC3', new Float32Array(g.getAttribute('normal').array)))
    .setMaterial(mat);
  if (g.index) prim.setIndices(accessor('SCALAR', new Uint32Array(g.index.array)));
  return prim;
}

function meshNode(name, geometry, mat, parent) {
  const mesh = doc.createMesh(name).addPrimitive(primitiveFrom(geometry, mat));
  const node = doc.createNode(name).setMesh(mesh);
  parent.addChild(node);
  return node;
}

function group(name, parent, { t = [0, 0, 0], r = [0, 0, 0], s = [1, 1, 1] } = {}) {
  const node = doc.createNode(name).setTranslation(t).setRotation(quat(r)).setScale(s);
  parent.addChild(node);
  return node;
}

const quat = ([x, y, z]) => new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z, 'XYZ')).toArray();
const bake = (geometry, { t = [0, 0, 0], r = [0, 0, 0], s = [1, 1, 1] } = {}) =>
  geometry.applyMatrix4(new THREE.Matrix4().compose(new THREE.Vector3(...t), new THREE.Quaternion(...quat(r)), new THREE.Vector3(...s)));

// ---------------------------------------------------------------- materials
const M = {
  hat: material('ari_hat_canvas', C.sand, { rough: 0.9, doubleSided: true }),
  hatBand: material('ari_hat_band', C.ink800, { rough: 0.55 }),
  stitch: material('ari_route_stitch', '#A9E01E', { rough: 0.4, emissive: '#A9E01E', strength: 0.35 }),
  gold: material('ari_brass', C.lantern, { metal: 1, rough: 0.28 }),
  paper: material('ari_paper', C.paper, { rough: 0.7 }),
  ink: material('ari_ink', C.ink950, { rough: 0.4 }),
  scarf: material('ari_scarf', '#A9E01E', { rough: 0.72, doubleSided: true }),
  scarfShade: material('ari_scarf_shade', '#7FB312', { rough: 0.75, doubleSided: true }),
  visor: material('ari_visor_glass', '#03050B', { rough: 0.08, clearcoat: 1 }),
  glow: material('ari_face_glow', C.signal, { rough: 0.3, emissive: C.signal, strength: 1.0, doubleSided: true }),
  beacon: material('ari_beacon', C.signal, { rough: 0.2, emissive: C.signal, strength: 1.6 }),
  needleN: material('ari_needle_north', '#A9E01E', { rough: 0.3, emissive: '#A9E01E', strength: 0.7 }),
  stalk: material('ari_stalk', '#2A3350', { metal: 0.6, rough: 0.35 }),
  roseInk: material('ari_compass_rose', '#26304F', { rough: 0.5 }),
};

// The generated base texture is a patchy atlas. By default Ari gets a clean graphite shell with a
// soft clearcoat (BODY=textured keeps the original texture, cooled towards the ink palette).
for (const m of root.listMaterials()) {
  if (m.getName() !== 'Material.001') continue;
  m.setName('ari_body');
  if (process.env.BODY === 'textured') {
    m.setBaseColorFactor([0.86, 0.9, 1.0, 1]).setRoughnessFactor(0.42);
  } else {
    m.setBaseColorTexture(null).setBaseColorFactor([...lin("#343C52"), 1]).setRoughnessFactor(0.6).setMetallicFactor(0.05);
    m.setExtension('KHR_materials_clearcoat', doc.createExtension(KHRMaterialsClearcoat).createClearcoat().setClearcoatFactor(0.35).setClearcoatRoughnessFactor(0.3));
  }
}

// ---------------------------------------------------------------- shell
// The base mesh is an AI-generated scan with lumpy, faceted surfaces. In clean mode it is welded into one
// mesh in world space and Taubin-smoothed (volume preserving), which gives Ari a moulded, premium shell.
function smoothedShell(iterations = 14) {
  const ids = new Map(), P = [], I = [];
  scene.traverse((node) => {
    const mesh = node.getMesh();
    if (!mesh) return;
    const m = node.getWorldMatrix();
    for (const prim of mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION'), idx = prim.getIndices().getArray();
      const local = new Int32Array(pos.getCount());
      const v = [0, 0, 0];
      for (let i = 0; i < pos.getCount(); i++) {
        pos.getElement(i, v);
        const x = m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12];
        const y = m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13];
        const z = m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14];
        const key = `${Math.round(x * 2e4)},${Math.round(y * 2e4)},${Math.round(z * 2e4)}`;
        let id = ids.get(key);
        if (id === undefined) { id = P.length / 3; ids.set(key, id); P.push(x, y, z); }
        local[i] = id;
      }
      for (let k = 0; k < idx.length; k += 3) {
        const a = local[idx[k]], b = local[idx[k + 1]], c = local[idx[k + 2]];
        if (a !== b && b !== c && a !== c) I.push(a, b, c);
      }
    }
  });
  const n = P.length / 3;
  const nbr = Array.from({ length: n }, () => new Set());
  for (let k = 0; k < I.length; k += 3) {
    const [a, b, c] = [I[k], I[k + 1], I[k + 2]];
    nbr[a].add(b).add(c); nbr[b].add(a).add(c); nbr[c].add(a).add(b);
  }
  const adj = nbr.map((s) => Int32Array.from(s));
  let cur = Float64Array.from(P);
  const step = (src, f) => {
    const out = new Float64Array(src.length);
    for (let i = 0; i < n; i++) {
      const a = adj[i];
      if (!a.length) { out.set(src.subarray(i * 3, i * 3 + 3), i * 3); continue; }
      let sx = 0, sy = 0, sz = 0;
      for (const j of a) { sx += src[j * 3]; sy += src[j * 3 + 1]; sz += src[j * 3 + 2]; }
      const inv = 1 / a.length;
      out[i * 3] = src[i * 3] + f * (sx * inv - src[i * 3]);
      out[i * 3 + 1] = src[i * 3 + 1] + f * (sy * inv - src[i * 3 + 1]);
      out[i * 3 + 2] = src[i * 3 + 2] + f * (sz * inv - src[i * 3 + 2]);
    }
    return out;
  };
  // lambda/mu chosen for a low pass-band (k_pb ~ 0.02) so broad facets are removed, not just noise
  const lam = Number(process.env.LAMBDA ?? 0.63), mu = Number(process.env.MU ?? -0.645);
  for (let it = 0; it < iterations; it++) cur = step(step(cur, lam), mu);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(Float32Array.from(cur), 3));
  g.setIndex(I);
  g.computeVertexNormals();
  console.log(`shell: ${n} verts, ${I.length / 3} tris, smoothed x${iterations}`);
  return g;
}

// ---------------------------------------------------------------- hierarchy
const original = scene.listChildren()[0]; // Sketchfab_model
const bodyMaterial = root.listMaterials().find((m) => m.getName() === 'ari_body');
const shellGeometry = process.env.BODY === "textured" ? null : smoothedShell(Number(process.env.SMOOTH ?? 280));
scene.removeChild(original);
const ari = doc.createNode('Ari');
scene.addChild(ari);
const body = group('Body', ari);
if (shellGeometry) meshNode('Shell', shellGeometry, bodyMaterial, body);
else body.addChild(original);

// ---------------------------------------------------------------- hat
const HAT_REST = { t: [0, 0.78, -0.035], r: [-0.17, 0, 0.1], s: [1, 1, 0.9] };
const hat = group('Hat', body, HAT_REST);
{
  // bucket-hat profile: tall soft crown with a pinched top, short brim that droops downward
  const profile = [
    [0.001, 0.4], [0.16, 0.392], [0.3, 0.372], [0.41, 0.34], [0.5, 0.29], [0.56, 0.2], [0.59, 0.1], [0.603, 0.0],
    [0.64, -0.022], [0.7, -0.07], [0.76, -0.125], [0.8, -0.165], [0.815, -0.185], [0.812, -0.2], [0.795, -0.198],
    [0.75, -0.158], [0.69, -0.1], [0.625, -0.05], [0.575, -0.03], [0.555, 0.05], [0.5, 0.25], [0.3, 0.35], [0.001, 0.37],
  ].map(([r, y]) => new THREE.Vector2(r, y));
  meshNode('HatCanvas', new THREE.LatheGeometry(profile, 72), M.hat, hat);
  meshNode('HatBand', new THREE.CylinderGeometry(0.598, 0.614, 0.088, 72, 1, true).translate(0, 0.046, 0), M.hatBand, hat);

  // route stitch: dashed volt line running around the band
  const dashes = [];
  for (let k = 0; k < 28; k++) {
    const a = (k / 28) * Math.PI * 2;
    const d = new THREE.BoxGeometry(0.052, 0.011, 0.008);
    dashes.push(bake(d, { t: [Math.sin(a) * 0.617, 0.046, Math.cos(a) * 0.617], r: [0, a, 0] }).toNonIndexed());
  }
  meshNode('RouteStitch', mergeGeometries(dashes), M.stitch, hat);

  // boarding pass tucked into the band (front-left)
  const passA = -0.72;
  const pass = group('BoardingPass', hat, { t: [Math.sin(passA) * 0.63, 0.1, Math.cos(passA) * 0.63], r: [0, passA, 0.26] });
  meshNode('PassPaper', new THREE.BoxGeometry(0.15, 0.085, 0.006), M.paper, pass);
  meshNode('PassStripe', new THREE.BoxGeometry(0.035, 0.085, 0.0075).translate(0.057, 0, 0), M.stitch, pass);
  const bars = [];
  for (let k = 0; k < 7; k++) bars.push(new THREE.BoxGeometry(k % 3 === 0 ? 0.006 : 0.003, 0.03, 0.0072).translate(-0.055 + k * 0.012, -0.018, 0).toNonIndexed());
  meshNode('PassBarcode', mergeGeometries(bars), M.ink, pass);

  // compass-star pin on the band (front-right)
  const pinA = 0.62;
  const star = new THREE.Shape();
  for (let k = 0; k < 8; k++) {
    const rr = k % 2 === 0 ? 0.042 : 0.013, a = (k / 8) * Math.PI * 2 + Math.PI / 2;
    k === 0 ? star.moveTo(Math.cos(a) * rr, Math.sin(a) * rr) : star.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  star.closePath();
  const pinGeo = new THREE.ExtrudeGeometry(star, { depth: 0.01, bevelEnabled: true, bevelThickness: 0.004, bevelSize: 0.003, bevelSegments: 2 });
  meshNode('StarPin', pinGeo, M.gold, group('Pin', hat, { t: [Math.sin(pinA) * 0.622, 0.05, Math.cos(pinA) * 0.622], r: [0, pinA, 0] }));
}

// signal beacon (antenna) poking out of the crown
const beaconTip = new THREE.Vector3(0.19, 0.6, -0.04);
{
  const curve = new THREE.CatmullRomCurve3([new THREE.Vector3(0.1, 0.3, 0), new THREE.Vector3(0.14, 0.47, -0.01), beaconTip]);
  meshNode('BeaconStalk', new THREE.TubeGeometry(curve, 16, 0.013, 10, false), M.stalk, hat);
}
const beacon = group('Beacon', hat, { t: beaconTip.toArray() });
meshNode('BeaconBulb', new THREE.SphereGeometry(0.043, 24, 16), M.beacon, beacon);
meshNode('BeaconHalo', new THREE.TorusGeometry(0.066, 0.006, 8, 40).rotateX(Math.PI / 2), M.beacon, beacon);

// ---------------------------------------------------------------- scarf
{
  const scarf = group('Scarf', body);
  const U = 144, V = 16, geo = new THREE.BufferGeometry();
  const pos = [], idx = [];
  for (let i = 0; i <= U; i++) {
    const u = (i / U) * Math.PI * 2;
    const cx = Math.sin(u) * 0.575, cz = Math.cos(u) * 0.566 - 0.01;
    const cy = 0.05 + 0.018 * Math.sin(3 * u + 0.6);
    // tall, soft fabric band with folds: wider vertically, thin radially, rippled along its length
    const fold = Math.sin(9 * u) * 0.5 + Math.sin(14 * u + 1.3) * 0.3;
    const thick = 0.05 + 0.018 * fold, tall = 0.1 + 0.014 * Math.sin(5 * u);
    const lean = 0.35 * Math.sin(4 * u + 0.4); // band twists slightly as it wraps
    const radial = new THREE.Vector3(Math.sin(u), 0, Math.cos(u));
    for (let j = 0; j <= V; j++) {
      const v = (j / V) * Math.PI * 2;
      const rr = Math.cos(v) * thick, yy = Math.sin(v) * tall;
      const p = new THREE.Vector3(cx, cy, cz)
        .addScaledVector(radial, rr * Math.cos(lean) - yy * Math.sin(lean) * 0.3)
        .add(new THREE.Vector3(0, yy * Math.cos(lean) + rr * Math.sin(lean) * 0.3, 0));
      pos.push(p.x, p.y, p.z);
    }
  }
  for (let i = 0; i < U; i++) for (let j = 0; j < V; j++) {
    const a = i * (V + 1) + j, b = (i + 1) * (V + 1) + j;
    idx.push(a, b, a + 1, b, b + 1, a + 1);
  }
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  meshNode('ScarfWrap', geo, M.scarf, scarf);

  // knot on the right shoulder, tails stream back in the wind
  const knotAt = new THREE.Vector3(0.47, 0.035, 0.33);
  meshNode('ScarfKnot', new THREE.SphereGeometry(1, 20, 14).scale(0.085, 0.07, 0.075).translate(...knotAt.toArray()), M.scarf, scarf);
  const tails = group('ScarfTails', scarf, { t: knotAt.toArray() });
  const ribbon = (points, w0, w1, twist, phase) => {
    const curve = new THREE.CatmullRomCurve3(points.map((p) => new THREE.Vector3(...p)));
    const N = 40, P = [], I = [];
    for (let k = 0; k <= N; k++) {
      const s = k / N, p = curve.getPoint(s), T = curve.getTangent(s);
      let W = new THREE.Vector3().crossVectors(T, new THREE.Vector3(0, 1, 0)).normalize();
      W.applyAxisAngle(T, twist * s + 0.25);
      const Nn = new THREE.Vector3().crossVectors(W, T).normalize();
      p.addScaledVector(Nn, 0.03 * Math.sin(s * 9 + phase) * s);
      const w = (w0 + (w1 - w0) * s) / 2;
      P.push(...p.clone().addScaledVector(W, w).toArray(), ...p.clone().addScaledVector(W, -w).toArray());
      if (k < N) { const a = k * 2; I.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
    g.setIndex(I);
    g.computeVertexNormals();
    return g;
  };
  meshNode('ScarfTailA', ribbon([[0, 0, 0], [0.12, 0.02, -0.18], [0.3, 0.07, -0.42], [0.48, 0.02, -0.66], [0.66, 0.1, -0.86]], 0.15, 0.1, 0.9, 0), M.scarf, tails);
  meshNode('ScarfTailB', ribbon([[0, -0.02, 0], [0.09, -0.08, -0.16], [0.22, -0.1, -0.36], [0.36, -0.16, -0.54]], 0.12, 0.08, -0.7, 1.7), M.scarfShade, tails);
}

// ---------------------------------------------------------------- compass-core emblem (covers the chest "AI" logo)
const compass = group('Compass', body, { t: [0, -0.214, 0.648], r: [-0.22, 0, 0] });
let needle;
{
  meshNode('CompassBezel', new THREE.TorusGeometry(0.148, 0.021, 18, 72), M.gold, compass);
  meshNode('CompassFace', new THREE.CylinderGeometry(0.148, 0.148, 0.022, 72).rotateX(Math.PI / 2), M.ink, compass);
  const rose = new THREE.Shape();
  for (let k = 0; k < 16; k++) {
    const rr = k % 4 === 0 ? 0.118 : k % 2 === 0 ? 0.07 : 0.03, a = (k / 16) * Math.PI * 2 + Math.PI / 2;
    k === 0 ? rose.moveTo(Math.cos(a) * rr, Math.sin(a) * rr) : rose.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  rose.closePath();
  meshNode('CompassRose', new THREE.ShapeGeometry(rose).translate(0, 0, 0.0115), M.roseInk, compass);
  const ticks = [];
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * Math.PI * 2;
    ticks.push(new THREE.CircleGeometry(0.009, 12).translate(Math.sin(a) * 0.128, Math.cos(a) * 0.128, 0.0125).toNonIndexed());
  }
  meshNode('CompassTicks', mergeGeometries(ticks), M.paper, compass);

  needle = group('Needle', compass, { t: [0, 0, 0.016] });
  const tri = (tipY) => { const s = new THREE.Shape(); s.moveTo(0, tipY); s.lineTo(0.026, 0); s.lineTo(-0.026, 0); s.closePath(); return s; };
  const ext = { depth: 0.008, bevelEnabled: true, bevelThickness: 0.002, bevelSize: 0.002, bevelSegments: 1 };
  meshNode('NeedleNorth', new THREE.ExtrudeGeometry(tri(0.112), ext), M.needleN, needle);
  meshNode('NeedleSouth', new THREE.ExtrudeGeometry(tri(-0.09), ext), M.paper, needle);
  meshNode('NeedleCap', new THREE.SphereGeometry(0.017, 16, 12).translate(0, 0, 0.012), M.gold, needle);
}

// ---------------------------------------------------------------- expressive face
{
  const face = group('Face', body);
  // visor plate + skirt down to the original surface so no gap is visible
  const R = 18, T = 72, P = [], I = [];
  const ring = (r) => { for (let k = 0; k < T; k++) { const a = (k / T) * Math.PI * 2; const x = FACE.cx + FACE.a * r * Math.cos(a), y = FACE.cy + FACE.b * r * Math.sin(a); P.push(x, y, plate.z(x, y)); } };
  P.push(FACE.cx, FACE.cy, plate.z(FACE.cx, FACE.cy));
  for (let i = 1; i <= R; i++) ring(i / R);
  for (let k = 0; k < T; k++) I.push(0, 1 + k, 1 + ((k + 1) % T));
  for (let i = 0; i < R - 1; i++) for (let k = 0; k < T; k++) {
    const a = 1 + i * T + k, b = 1 + i * T + ((k + 1) % T), c = a + T, d = b + T;
    I.push(a, c, b, b, c, d);
  }
  const edge = 1 + (R - 1) * T, skirt = P.length / 3;
  for (let k = 0; k < T; k++) {
    const a = (k / T) * Math.PI * 2, x = FACE.cx + FACE.a * 1.03 * Math.cos(a), y = FACE.cy + FACE.b * 1.03 * Math.sin(a);
    const zs = hf.sample(x, y);
    P.push(x, y, (Number.isFinite(zs) ? zs : plate.z(x, y)) - 0.02);
  }
  for (let k = 0; k < T; k++) { const a = edge + k, b = edge + ((k + 1) % T), c = skirt + k, d = skirt + ((k + 1) % T); I.push(a, c, b, b, c, d); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
  g.setIndex(I);
  g.computeVertexNormals();
  meshNode('VisorPlate', g, M.visor, face);

  // band shapes: outer/inner loop sampled on t∈[0,1); projected onto the plate
  const N = 48;
  const tri = (t) => 1 - Math.abs(2 * t - 1);
  const project = (x, y) => { const n = plate.normal(x, y); const z = plate.z(x, y); return [x + n.x * 0.004, y + n.y * 0.004, z + n.z * 0.004]; };
  const bandPositions = (shape) => {
    const out = [];
    for (let k = 0; k < N; k++) { const { o, i } = shape(k / N); out.push(...project(...o), ...project(...i)); }
    return new Float32Array(out);
  };
  const bandIndices = () => { const I2 = []; for (let k = 0; k < N; k++) { const a = k * 2, b = ((k + 1) % N) * 2; I2.push(a, a + 1, b, a + 1, b + 1, b); } return new Uint32Array(I2); };
  const morphMesh = (name, base, targets) => {
    const basePos = bandPositions(base);
    const normals = new Float32Array(basePos.length);
    for (let k = 0; k < basePos.length; k += 3) { const n = plate.normal(basePos[k], basePos[k + 1]); normals.set([n.x, n.y, n.z], k); }
    const prim = doc.createPrimitive()
      .setAttribute('POSITION', accessor('VEC3', basePos))
      .setAttribute('NORMAL', accessor('VEC3', normals))
      .setIndices(accessor('SCALAR', bandIndices()))
      .setMaterial(M.glow);
    for (const [targetName, shape] of targets) {
      const p = bandPositions(shape);
      for (let k = 0; k < p.length; k++) p[k] -= basePos[k];
      // glTF-Transform writes mesh.extras.targetNames from the target names (three.js reads them)
      prim.addTarget(doc.createPrimitiveTarget(targetName).setAttribute('POSITION', accessor('VEC3', p)));
    }
    const mesh = doc.createMesh(name).addPrimitive(prim).setWeights(targets.map(() => 0)).setExtras({ targetNames: targets.map(([n]) => n) });
    const node = doc.createNode(name).setMesh(mesh);
    face.addChild(node);
    return node;
  };

  const eye = (cx, side) => {
    const cy = 0.482, a = 0.05, b = 0.068;
    const at = (x, y) => [cx + x, cy + y];
    const ell = (sa, sb, dy = 0, dx = 0) => (t) => { const th = t * Math.PI * 2; return { o: at(dx + sa * Math.cos(th), dy + sb * Math.sin(th)), i: at(dx, dy) }; };
    const targets = [
      ['blink', (t) => { const th = t * Math.PI * 2; return { o: at(a * 1.15 * Math.cos(th), 0.009 * Math.sin(th) - 0.014), i: at(0, -0.014) }; }],
      ['happy', (t) => { const f = Math.PI * tri(t), R2 = 0.056; return { o: at(R2 * Math.cos(f), R2 * Math.sin(f) - 0.03), i: at((R2 - 0.024) * Math.cos(f), (R2 - 0.024) * Math.sin(f) - 0.03) }; }],
      ['lookUp', ell(a * 0.95, b * 0.88, 0.03, -side * 0.012)],
      ['concerned', (t) => {
        const th = t * Math.PI * 2, x = a * Math.cos(th), s = Math.sin(th);
        const outward = (x * side / a + 1) / 2;
        return { o: at(x, s > 0 ? b * 0.72 * s - 0.024 * outward : b * 0.85 * s), i: at(0, -0.006) };
      }],
      ['sleepy', (t) => { const th = t * Math.PI * 2, s = Math.sin(th); return { o: at(a * 1.05 * Math.cos(th), (s < 0 ? b * 0.42 * s : 0.006 * s) - 0.016), i: at(0, -0.02) }; }],
      ['wide', ell(a * 1.13, b * 1.1)],
    ];
    return morphMesh(side < 0 ? 'EyeL' : 'EyeR', ell(a, b), targets);
  };
  eye(-0.205, -1);
  eye(0.205, 1);

  const arc = (cx, cy, R2, w, f0, f1) => (t) => {
    const f = f0 + (f1 - f0) * tri(t);
    return { o: [cx + R2 * Math.cos(f), cy + R2 * Math.sin(f)], i: [cx + (R2 - w) * Math.cos(f), cy + (R2 - w) * Math.sin(f)] };
  };
  morphMesh('Mouth', arc(0, 0.378, 0.072, 0.019, Math.PI + 0.62, Math.PI * 2 - 0.62), [
    ['talk', (t) => { const th = t * Math.PI * 2; return { o: [0.046 * Math.cos(th), 0.314 + 0.036 * Math.sin(th)], i: [0, 0.314] }; }],
    ['frown', arc(0, 0.262, 0.07, 0.018, 0.66, Math.PI - 0.66)],
    ['flat', (t) => { const x = -0.045 + 0.09 * tri(t); return { o: [x, 0.326], i: [x, 0.31] }; }],
    ['ooh', (t) => { const th = t * Math.PI * 2; return { o: [0.03 * Math.cos(th), 0.318 + 0.03 * Math.sin(th)], i: [0.015 * Math.cos(th), 0.318 + 0.015 * Math.sin(th)] }; }],
    ['grin', arc(0, 0.39, 0.092, 0.034, Math.PI + 0.45, Math.PI * 2 - 0.45)],
  ]);
}

// ---------------------------------------------------------------- animation clips
const byName = (n) => root.listNodes().find((x) => x.getName() === n);
const N_ = { body, hat, beacon, needle, tails: byName('ScarfTails'), eyeL: byName('EyeL'), eyeR: byName('EyeR'), mouth: byName('Mouth') };
const EYE = ['blink', 'happy', 'lookUp', 'concerned', 'sleepy', 'wide'];
const MOUTH = ['talk', 'frown', 'flat', 'ooh', 'grin'];
const TAILS_REST = N_.tails.getTranslation();

const smooth = (x) => x * x * (3 - 2 * x);
const pulse = (t, at, len) => { const d = (t - at) / len; return d < 0 || d > 1 ? 0 : Math.sin(d * Math.PI); };
const blinkAt = (t, ...times) => Math.max(0, ...times.map((b) => pulse(t, b, 0.18)));
const hatRest = new THREE.Euler(...HAT_REST.r, 'XYZ');

// pose(t) → { bodyT, bodyR, hatR (delta), tailR, beaconS, needleZ, eye{}, mouth{} }
const CLIPS = {
  idle_float: { dur: 4, pose: (t) => ({
    bodyT: [0, 0.035 * Math.sin((t / 4) * Math.PI * 2), 0],
    bodyR: [0, 0.06 * Math.sin((t / 4) * Math.PI * 2 + 1), 0.025 * Math.sin((t / 4) * Math.PI * 2)],
    hatR: [0, 0, 0.02 * Math.sin((t / 4) * Math.PI * 4)],
    tailR: [0.05 * Math.sin(t * 3.1), 0.12 * Math.sin(t * 2.4), 0.06 * Math.sin(t * 1.7)],
    beaconS: 1 + 0.12 * (0.5 + 0.5 * Math.sin((t / 4) * Math.PI * 4)),
    needleZ: 0.12 * Math.sin((t / 4) * Math.PI * 2 * 2) + 0.05 * Math.sin(t * 7),
    eye: { blink: blinkAt(t, 1.4, 3.3) }, mouth: {},
  }) },
  listening: { dur: 3, pose: (t) => ({
    bodyT: [0, 0.02 * Math.sin((t / 3) * Math.PI * 2), 0.03],
    bodyR: [-0.05, 0, 0.14 + 0.02 * Math.sin((t / 3) * Math.PI * 2)],
    hatR: [0, 0, 0.03],
    tailR: [0.03 * Math.sin(t * 2.2), 0.08 * Math.sin(t * 1.9), 0.04 * Math.sin(t * 1.3)],
    beaconS: 1 + 0.3 * (0.5 + 0.5 * Math.sin((t / 3) * Math.PI * 6)),
    needleZ: 0,
    eye: { wide: 0.8, blink: blinkAt(t, 2.2) }, mouth: { ooh: 0.35 },
  }) },
  thinking: { dur: 3, pose: (t) => ({
    bodyT: [0, 0.03 * Math.sin((t / 3) * Math.PI * 2), 0],
    bodyR: [0.04, -0.12, -0.09],
    hatR: [0, 0, -0.03],
    tailR: [0.03 * Math.sin(t * 2), 0.06 * Math.sin(t * 1.6), 0],
    beaconS: 1 + 0.35 * (0.5 + 0.5 * Math.sin((t / 3) * Math.PI * 8)),
    needleZ: -(t / 3) * Math.PI * 2, // compass searches while Ari thinks
    eye: { lookUp: 1 }, mouth: { flat: 0.55, ooh: 0.2 },
  }) },
  talking: { dur: 1.6, pose: (t) => {
    const s = (t / 1.6) * Math.PI * 2;
    const open = Math.max(0, Math.sin(s * 3)) * 0.75 + Math.max(0, Math.sin(s * 5 + 1)) * 0.25;
    return {
      bodyT: [0, 0.02 * Math.abs(Math.sin(s * 2)), 0],
      bodyR: [0.03 * Math.sin(s * 2), 0.05 * Math.sin(s), 0.03 * Math.sin(s)],
      hatR: [0.015 * Math.sin(s * 2), 0, 0],
      tailR: [0.04 * Math.sin(t * 3), 0.1 * Math.sin(t * 2.6), 0.04 * Math.sin(t * 2)],
      beaconS: 1 + 0.2 * open,
      needleZ: 0.08 * Math.sin(s),
      eye: { blink: blinkAt(t, 0.9) }, mouth: { talk: open * 0.9 },
    };
  } },
  pointing: { dur: 2, pose: (t) => {
    const k = smooth(Math.min(1, t / 0.5)), s = (t / 2) * Math.PI * 2;
    return {
      bodyT: [0.04 * k, 0.02 * Math.sin(s), 0],
      bodyR: [0, 0.42 * k, -0.12 * k],
      hatR: [0, 0, -0.03 * k],
      tailR: [0.03 * Math.sin(t * 2.5), 0.1 * Math.sin(t * 2.1), 0.04 * Math.sin(t * 1.4)],
      beaconS: 1 + 0.15 * (0.5 + 0.5 * Math.sin(s * 2)),
      needleZ: -Math.PI / 2 * k, // needle swings toward the target
      eye: { happy: 0.25 * k }, mouth: { grin: 0.35 * k },
    };
  } },
  warning: { dur: 2, pose: (t) => {
    const s = (t / 2) * Math.PI * 2;
    return {
      bodyT: [0, 0.015 * Math.sin(s), 0],
      bodyR: [0.05, 0.1 * Math.sin(s * 3) * Math.exp(-((t % 1) * 3)), 0],
      hatR: [0.02, 0, 0],
      tailR: [0.02 * Math.sin(t * 2), 0.05 * Math.sin(t * 1.5), 0],
      beaconS: 1 + 0.4 * (Math.sin(s * 4) > 0 ? 1 : 0),
      needleZ: 0.35 * Math.sin(s * 3),
      eye: { concerned: 1 }, mouth: { frown: 0.8 },
    };
  } },
  excited: { dur: 1.6, pose: (t) => {
    const hop = Math.max(0, Math.sin((t / 0.8) * Math.PI)); // two hops
    const spin = smooth(Math.min(1, t / 1.2)) * Math.PI * 2;
    return {
      bodyT: [0, 0.22 * hop, 0],
      bodyR: [0, spin, 0.08 * Math.sin((t / 1.6) * Math.PI * 4)],
      hatR: [0.05 * hop, 0, 0.04 * hop],
      tailR: [0.1 * Math.sin(t * 6), 0.3 * Math.sin(t * 5), 0.12 * Math.sin(t * 4)],
      beaconS: 1 + 0.5 * hop,
      needleZ: spin * 2,
      eye: { happy: 1 }, mouth: { grin: 1 },
    };
  } },
  offline: { dur: 4, pose: (t) => ({
    bodyT: [0, -0.05 + 0.012 * Math.sin((t / 4) * Math.PI * 2), 0],
    bodyR: [0.12, 0, 0.04],
    hatR: [0.1, 0, 0],
    tailR: [0.25, 0, 0.35],
    beaconS: 0.55,
    needleZ: 0.6,
    eye: { sleepy: 1 }, mouth: { flat: 1 },
  }) },
};

const FPS = 24;
function addClip(name, { dur, pose }) {
  const anim = doc.createAnimation(name);
  const n = Math.round(dur * FPS) + 1;
  const times = new Float32Array(n);
  const tracks = { bodyT: [], bodyR: [], hatR: [], tailR: [], beaconS: [], needleR: [], eyeW: [], mouthW: [] };
  for (let k = 0; k < n; k++) {
    const t = (k / (n - 1)) * dur;
    times[k] = t;
    const p = pose(t);
    tracks.bodyT.push(...p.bodyT);
    tracks.bodyR.push(...quat(p.bodyR));
    const hq = new THREE.Quaternion().setFromEuler(hatRest).multiply(new THREE.Quaternion(...quat(p.hatR)));
    tracks.hatR.push(...hq.toArray());
    tracks.tailR.push(...quat(p.tailR));
    tracks.beaconS.push(p.beaconS, p.beaconS, p.beaconS);
    tracks.needleR.push(...quat([0, 0, p.needleZ]));
    tracks.eyeW.push(...EYE.map((e) => Math.min(1, p.eye[e] ?? 0)));
    tracks.mouthW.push(...MOUTH.map((m) => Math.min(1, p.mouth[m] ?? 0)));
  }
  const input = accessor('SCALAR', times);
  const channel = (node, path, type, values) => {
    const sampler = doc.createAnimationSampler().setInput(input).setOutput(accessor(type, new Float32Array(values))).setInterpolation('LINEAR');
    anim.addSampler(sampler).addChannel(doc.createAnimationChannel().setTargetNode(node).setTargetPath(path).setSampler(sampler));
  };
  channel(N_.body, 'translation', 'VEC3', tracks.bodyT);
  channel(N_.body, 'rotation', 'VEC4', tracks.bodyR);
  channel(N_.hat, 'rotation', 'VEC4', tracks.hatR);
  channel(N_.tails, 'rotation', 'VEC4', tracks.tailR);
  channel(N_.beacon, 'scale', 'VEC3', tracks.beaconS);
  channel(N_.needle, 'rotation', 'VEC4', tracks.needleR);
  channel(N_.eyeL, 'weights', 'SCALAR', tracks.eyeW);
  channel(N_.eyeR, 'weights', 'SCALAR', tracks.eyeW);
  channel(N_.mouth, 'weights', 'SCALAR', tracks.mouthW);
}
for (const [name, clip] of Object.entries(CLIPS)) addClip(name, clip);
void TAILS_REST;

// ---------------------------------------------------------------- attribution + optimize + write
root.getAsset().generator = 'arivo-mascot-forge';
root.getAsset().extras = {
  title: 'Ari — Arivo explorer mascot',
  derivedFrom: 'Miibot 3D Model by itsmejhade (https://sketchfab.com/3d-models/miibot-3d-model-7606b66321934033a5dcfecf0f7925e5)',
  license: 'CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)',
  changes: 'Added explorer hat, boarding pass, signal beacon, scarf, compass emblem, expressive face and animation clips (Arivo).',
};

if (!RAW) {
  // Only the dense body shell is simplified; hand-built gear and the face bands keep their exact topology.
  const shellPrim = root.listMeshes().find((m) => m.getName() === 'Shell')?.listPrimitives()[0];
  if (shellPrim) simplifyPrimitive(shellPrim, { simplifier: MeshoptSimplifier, ratio: 0.3, error: 0.0008 });
  await doc.transform(
    dedup(),
    prune(),
    textureCompress({ encoder: sharp, targetFormat: 'webp', quality: 86, resize: [1024, 1024] }),
    quantize(),
    meshopt({ encoder: MeshoptEncoder, level: 'medium' }),
  );
}

await mkdir(OUT_DIR, { recursive: true });
const outFile = resolve(OUT_DIR, RAW ? 'ari_explorer.raw.glb' : 'ari_explorer.glb');
const bytes = await io.writeBinary(doc);
await writeFile(outFile, bytes);

const meta = {
  file: 'ari_explorer.glb',
  bytes: bytes.byteLength,
  states: Object.keys(CLIPS),
  clipDurations: Object.fromEntries(Object.entries(CLIPS).map(([k, v]) => [k, v.dur])),
  morphTargets: { EyeL: EYE, EyeR: EYE, Mouth: MOUTH },
  nodes: ['Ari', 'Body', 'Hat', 'Beacon', 'ScarfTails', 'Compass', 'Needle', 'Face', 'EyeL', 'EyeR', 'Mouth'],
  attribution: root.getAsset().extras,
};
await writeFile(resolve(OUT_DIR, 'ari_explorer.meta.json'), JSON.stringify(meta, null, 2));
console.log(`wrote ${outFile} (${(bytes.byteLength / 1024 / 1024).toFixed(2)} MB)`);
