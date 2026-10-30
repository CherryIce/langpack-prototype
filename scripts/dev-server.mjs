import http from 'node:http';
import { execFileSync } from 'node:child_process';
import { readFile, readdir } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
import { createWorker } from '../worker/index.js';

// Optional one-line JSON on stdin keeps provided credentials out of files and argv.
if (!process.env.TRANSLATION_API_KEY && process.stdin.isTTY) execFileSync('stty', ['-echo'], { stdio: 'inherit' });
const line = process.env.TRANSLATION_API_KEY ? '' : await new Promise(resolveLine => {
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => { input += chunk; if (input.includes('\n')) { process.stdin.removeAllListeners('data'); resolveLine(input.split('\n')[0]); } });
  process.stdin.on('end', () => resolveLine(input));
});
const settings = line ? JSON.parse(line) : {};
if (process.stdin.isTTY) execFileSync('stty', ['echo'], { stdio: 'inherit' });
process.stdin.pause(); process.stdin.unref?.();
const env = { TRANSLATION_API_KEY: process.env.TRANSLATION_API_KEY || settings.key || '', LANGPACK_DEVELOPER_TOKEN: process.env.LANGPACK_DEVELOPER_TOKEN || settings.developerToken || '' };
const root = resolve(new URL('..', import.meta.url).pathname);
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'application/javascript; charset=utf-8' };
const assets = {};
for (const name of (await readdir(resolve(root, 'web'))).sort()) {
  if (types[extname(name)]) assets['/' + name] = { type: types[extname(name)], body: await readFile(resolve(root, 'web', name), 'utf8') };
}
const worker = createWorker(assets);
const port = Number(process.env.PORT || 4173);
http.createServer(async (req, res) => {
  const controller = new AbortController();
  req.on('aborted', () => controller.abort());
  res.on('close', () => { if (!res.writableEnded) controller.abort(); });
  try {
    const buffers = []; let size = 0;
    for await (const chunk of req) { size += chunk.length; if (size > 270000) { res.writeHead(413); res.end('Request too large'); return; } buffers.push(chunk); }
    const origin = 'http://127.0.0.1:' + port;
    const request = new Request(origin + req.url, { method: req.method, headers: req.headers, signal: controller.signal, ...(!['GET', 'HEAD'].includes(req.method) ? { body: Buffer.concat(buffers) } : {}) });
    const response = await worker.fetch(request, env, {});
    res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(Buffer.from(await response.arrayBuffer()));
  } catch { if (!res.headersSent) res.writeHead(500); res.end('Request failed'); }
}).listen(port, '127.0.0.1', () => console.log(`Local: http://127.0.0.1:${port}`));
