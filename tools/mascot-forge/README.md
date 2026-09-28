# mascot-forge

Reproducible pipeline that turns `assets/mascot/source/miibot_source.glb` into Ari (`assets/mascot/ari_explorer.glb`).

```bash
npm install
npm run inspect          # node tree, bounds, materials of the source model
node src/profile.mjs     # silhouette slices (used to place gear)
node src/facemap.mjs     # visor / eye / chest-logo positions from the texture
npm run build            # optimized GLB + meta.json   (node src/forge.mjs --raw for a fast unoptimized build)
npm run preview          # viewer on http://localhost:5178
```

Viewer query params: `src`, `clip`, `bg` (hex or `none` for transparent), `size` (render px).

In the browser console:

```js
__ari.renderer.setAnimationLoop(null);
await __ari.capture('bust', 'talking', 0.2, 'sp_talking_00.png'); // saves to out/captures
```

Then run `node src/sprites.mjs` to pack sprite sheets and posters into `assets/mascot`.

Environment knobs: `BODY=textured` keeps the original texture; `SMOOTH` sets the number of Taubin passes (default 280); `LAMBDA` and `MU` set the smoothing weights.
