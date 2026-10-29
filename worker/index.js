import { createHandler } from './handler.js';

export function createWorker(assets, options = {}) {
  const api = createHandler(options);
  return {
    async fetch(request, env, ctx) {
      const result = await api(request, env, ctx);
      if (result) return result;
      const url = new URL(request.url);
      if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', { status: 405 });
      const asset = assets[url.pathname === '/' ? '/index.html' : url.pathname];
      if (!asset) return new Response('Not found', { status: 404 });
      const headers = { 'Content-Type': asset.type, 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
      return new Response(request.method === 'HEAD' ? null : asset.body, { headers });
    }
  };
}
