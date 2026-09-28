// Tiny static server for the mascot viewer. Serves the forge directory, repo assets and three.js from node_modules.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const REPO = resolve(ROOT, '../..');
const PORT = Number(process.env.PORT ?? 5178);
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.glb': 'model/gltf-binary', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.css': 'text/css' };

function mapPath(urlPath) {
  const p = normalize(decodeURIComponent(urlPath)).replace(/^[/\\]+/, '');
  if (p.startsWith('assets')) return join(REPO, p);
  if (p === '' || p === '.') return join(ROOT, 'viewer', 'index.html');
  return join(ROOT, p);
}

http.createServer(async (req, res) => {
  // POST /capture?name=foo.png  body = data URL → saved to tools/mascot-forge/out/captures/
  if (req.method === 'POST' && req.url.startsWith('/capture')) {
    const name = new URL(req.url, 'http://x').searchParams.get('name') ?? 'capture.png';
    if (!/^[\w.-]+\.(png|webp)$/.test(name)) { res.writeHead(400).end('bad name'); return; }
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const dataUrl = Buffer.concat(chunks).toString();
    const { mkdir, writeFile } = await import('node:fs/promises');
    const dir = join(ROOT, 'out', 'captures');
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, name), Buffer.from(dataUrl.split(',')[1], 'base64'));
    res.writeHead(200).end('saved');
    return;
  }
  const file = mapPath(new URL(req.url, 'http://x').pathname);
  if (!file.startsWith(REPO)) { res.writeHead(403).end(); return; }
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-store' });
    res.end(body);
  } catch { res.writeHead(404).end('not found'); }
}).listen(PORT, () => console.log(`mascot viewer on http://localhost:${PORT}`));
