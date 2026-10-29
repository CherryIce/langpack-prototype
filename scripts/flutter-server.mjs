// Flutter Web and its server-only backup proxy share one origin.
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHandler } from '../worker/handler.js';

const webRoot = resolve(fileURLToPath(new URL('../flutter_app/build/web/', import.meta.url)));
const handler = createHandler();
const port = Number(process.env.PORT || 4180);
const host = process.env.HOST || '127.0.0.1';
const publicOrigin = process.env.PUBLIC_ORIGIN ? new URL(process.env.PUBLIC_ORIGIN) : null;
if (publicOrigin && (publicOrigin.protocol !== 'https:' || publicOrigin.username || publicOrigin.password ||
  publicOrigin.pathname !== '/' || publicOrigin.search || publicOrigin.hash)) {
  throw new Error('PUBLIC_ORIGIN must be an HTTPS origin without a path, credentials or query.');
}
const types = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.ico': 'image/x-icon', '.ttf': 'font/ttf', '.otf': 'font/otf', '.bin': 'application/octet-stream',
  '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };

const server = http.createServer(async (req, res) => {
  const controller = new AbortController();
  req.on('aborted', () => controller.abort());
  res.on('close', () => { if (!res.writableEnded) controller.abort(); });
  try {
    // Browser Origin is compared to the actual requested host, including Android's
    // emulator address. No permissive CORS or client credential is introduced.
    const origin = publicOrigin?.origin || ('http://' + (req.headers.host || `127.0.0.1:${port}`));
    const url = new URL(req.url, origin);
    if (url.pathname.startsWith('/api/')) {
      const chunks = []; let length = 0;
      for await (const chunk of req) {
        length += chunk.length;
        if (length > 270000) { res.writeHead(413); res.end('Request too large'); return; }
        chunks.push(chunk);
      }
      const request = new Request(url, { method: req.method, headers: req.headers, signal: controller.signal,
        ...(!['GET', 'HEAD'].includes(req.method) ? { body: Buffer.concat(chunks) } : {}) });
      const response = await handler(request, { TRANSLATION_API_KEY: process.env.TRANSLATION_API_KEY || '' });
      if (!response) { res.writeHead(404); res.end('Not found'); return; }
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
      return;
    }
    if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405); res.end(); return; }
    let path = resolve(webRoot, '.' + decodeURIComponent(url.pathname));
    if (path !== webRoot && !path.startsWith(webRoot + sep)) { res.writeHead(403); res.end(); return; }
    if (url.pathname.endsWith('/')) path = resolve(path, 'index.html');
    let bytes;
    try {
      if (!(await stat(path)).isFile()) throw new Error('Not a file');
      bytes = await readFile(path);
    } catch {
      if (extname(url.pathname)) { res.writeHead(404); res.end('Not found'); return; }
      path = resolve(webRoot, 'index.html'); bytes = await readFile(path);
    }
    res.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream',
      'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff' });
    res.end(req.method === 'HEAD' ? undefined : bytes);
  } catch {
    if (!res.headersSent) res.writeHead(500);
    res.end('Service unavailable. Build Flutter Web before starting this server.');
  }
});
server.requestTimeout = 650000;
server.listen(port, host, () => console.log(`LangPack Flutter: http://${host}:${port}`));
