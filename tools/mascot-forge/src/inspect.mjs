// Prints the structure of a GLB: node tree, transforms, per-primitive bounds and texture info.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { getBounds } from '@gltf-transform/core';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(process.argv[2]);
const root = doc.getRoot();

const fmt = (v) => v.map((n) => n.toFixed(3)).join(', ');
function walk(node, depth) {
  const pad = '  '.repeat(depth);
  console.log(`${pad}- ${node.getName()}  T[${fmt(node.getTranslation())}] R[${fmt(node.getRotation())}] S[${fmt(node.getScale())}]`);
  const mesh = node.getMesh();
  if (mesh) {
    for (const prim of mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION');
      const min = pos.getMinNormalized ? pos.getMin([]) : [];
      const max = pos.getMax([]);
      console.log(`${pad}    prim: verts=${pos.getCount()} idx=${prim.getIndices()?.getCount()} attrs=${prim.listSemantics().join('|')} min[${fmt(min)}] max[${fmt(max)}] mat=${prim.getMaterial()?.getName()}`);
    }
  }
  node.listChildren().forEach((c) => walk(c, depth + 1));
}
for (const scene of root.listScenes()) {
  console.log(`scene ${scene.getName()} world bounds:`, getBounds(scene));
  scene.listChildren().forEach((n) => walk(n, 0));
}
for (const tex of root.listTextures()) {
  console.log(`texture ${tex.getName()} ${tex.getMimeType()} ${tex.getSize()} bytes=${tex.getImage()?.byteLength}`);
}
for (const m of root.listMaterials()) {
  console.log(`material ${m.getName()} base=${m.getBaseColorFactor()} metal=${m.getMetallicFactor()} rough=${m.getRoughnessFactor()} emissive=${m.getEmissiveFactor()} baseTex=${!!m.getBaseColorTexture()} normalTex=${!!m.getNormalTexture()} mrTex=${!!m.getMetallicRoughnessTexture()} emTex=${!!m.getEmissiveTexture()}`);
}
