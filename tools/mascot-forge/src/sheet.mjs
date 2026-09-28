// Combines captures into a horizontal contact sheet: node src/sheet.mjs out.png a.png b.png ...
import sharp from 'sharp';
const [out, ...inputs] = process.argv.slice(2);
const S = 512;
const imgs = await Promise.all(inputs.map((n) => sharp(n).resize(S, S).toBuffer()));
await sharp({ create: { width: S * imgs.length, height: S, channels: 4, background: '#0E1426' } })
  .composite(imgs.map((b, i) => ({ input: b, left: i * S, top: 0 }))).png().toFile(out);
