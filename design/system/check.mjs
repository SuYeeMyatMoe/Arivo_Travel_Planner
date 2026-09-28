// Local render check: builds design/system/.check/index.html with every preview in both themes.
// tokens.css here is an approximation of what the artifact page compiles (enough to eyeball components).
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
const P = resolve(import.meta.dirname, 'project');
const t = JSON.parse(await readFile(resolve(P, 'tokens.json'), 'utf8'));
const themes = t.color.themes.map((x) => x.id);
const val = (tok, th) => {
  let v = typeof tok.value === 'string' ? tok.value : tok.value[th] ?? tok.value[themes[0]];
  if (/^\{.*\}$/.test(v)) v = `var(--${v.slice(1, -1)})`;
  return v;
};
let css = '';
for (const th of themes) {
  css += `[data-theme="${th}"]{` + t.color.tokens.map((k) => `--${k.name}:${val(k, th)};`).join('') + t.shadow.tokens.map((k) => `--${k.name}:${val(k, th)};`).join('') + '}\n';
}
css += ':root{' + [...t.spacing.tokens, ...t.radius.tokens, ...t.duration.tokens, ...t.easing.tokens].map((k) => `--${k.name}:${k.value};`).join('') +
  Object.entries(t.type.families).map(([k, v]) => `--font-${k}:${v};`).join('') + '}\n';
for (const g of t.type.groups) for (const s of g.styles) css += `.${s.name}{font-family:var(--font-${s.family ?? g.family});font-size:${s.fontSize};line-height:${s.lineHeight};font-weight:${s.fontWeight};${s.letterSpacing ? `letter-spacing:${s.letterSpacing};` : ''}}\n`;
const bundle = await readFile(resolve(P, 'components/bundle.js'), 'utf8');
const bcss = await readFile(resolve(P, 'components/bundle.css'), 'utf8');
const comps = (await readdir(resolve(P, 'components'), { withFileTypes: true })).filter((d) => d.isDirectory()).map((d) => d.name);
let frames = '';
for (const c of comps) {
  const src = await readFile(resolve(P, 'components', c, 'preview.html'), 'utf8');
  const script = /<script>([\s\S]*?)<\/script>/.exec(src)[1].replace("document.getElementById('root')", `document.getElementById('R_${c}_THEME')`);
  for (const th of themes) frames += `<section data-theme="${th}" style="background:var(--surface);color:var(--text);padding:16px;border-radius:12px"><h5 style="margin:0 0 8px;font:600 11px monospace;opacity:.6">${c} · ${th}</h5><div id="R_${c}_${th}"></div></section><script>${script.replace('_THEME', '_' + th)}</script>\n`;
}
const html = `<!doctype html><html><head><meta charset="utf-8"><title>DS check</title>
<script src="https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js"></script>
<style>${css}${bcss.replace(/body \{[^}]*\}/, '')} body{margin:0;padding:16px;background:#888;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;font-family:var(--font-ui)}</style>
<script>${bundle}</script></head><body>${frames}</body></html>`;
await writeFile(resolve(import.meta.dirname, '.check/index.html'), html);
console.log('check page written');
