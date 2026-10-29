import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
const root = resolve(new URL('..', import.meta.url).pathname);
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'application/javascript; charset=utf-8' };
const assets = {};
for (const name of (await readdir(resolve(root, 'web'))).sort()) {
  if (!types[extname(name)]) continue;
  assets['/' + name] = { type: types[extname(name)], body: await readFile(resolve(root, 'web', name), 'utf8') };
}
const handler = (await readFile(resolve(root, 'worker/handler.js'), 'utf8')).replace(/^export default[^\n]*;?\s*$/gm, '').replace(/^export /gm, '');
const entry = (await readFile(resolve(root, 'worker/index.js'), 'utf8')).replace(/^import[^\n]*\n/gm, '').replace(/^export /gm, '');
const source = `// Generated from web/ and worker/. No runtime secrets are embedded.\nconst STATIC_ASSETS = ${JSON.stringify(assets)};\n${handler}\n${entry}\nexport default createWorker(STATIC_ASSETS);\n`;
await mkdir(resolve(root, 'dist/server'), { recursive: true });
await mkdir(resolve(root, 'dist/.openai'), { recursive: true });
await writeFile(resolve(root, 'dist/server/index.js'), source);
await writeFile(resolve(root, 'dist/.openai/hosting.json'), await readFile(resolve(root, '.openai/hosting.json')));
console.log(`Built Worker with ${Object.keys(assets).length} assets.`);
