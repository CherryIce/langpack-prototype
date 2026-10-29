import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../worker/handler.js', import.meta.url), 'utf8');
const { createHandler } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const SECRET = 'fixture-private-api-key-never-return';
const env = { TRANSLATION_API_KEY: SECRET };
const origin = 'https://example.chatgpt.site';
function request(body = { content: '登录', locale: 'en' }, options = {}) {
  return new Request(origin + '/api/translation/backup', { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body), ...options, headers: { 'Content-Type': 'application/json', Origin: origin, ...options.headers }, signal: options.signal });
}
function result(text = 'Log in', extras = {}) { return new Response(JSON.stringify({ targetLanguage: 'English', model: 'fast', items: [{ id: 'segment-1', originalText: '登录', translatedText: text }], ...extras }), { headers: { 'Content-Type': 'application/json' } }); }
async function payload(response, expectedStatus) {
  assert.equal(response.status, expectedStatus);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
  const body = await response.json();
  assert.ok(!JSON.stringify(body).includes(SECRET));
  return body;
}

test('status exposes configuration boolean only and unknown routes fall through', async () => {
  const handler = createHandler({ fetchImpl: () => assert.fail('must not call upstream') });
  assert.deepEqual(await payload(await handler(new Request(origin + '/api/translation/status'), env), 200), { backupConfigured: true, backupProvider: 'ZTAITrans' });
  assert.deepEqual(await payload(await handler(new Request(origin + '/api/translation/status'), {}), 200), { backupConfigured: false, backupProvider: 'ZTAITrans' });
  assert.equal(await handler(new Request(origin + '/index.html'), env), null);
});

test('proxy sends the secret only to fixed HTTPS endpoint with fixed fast model and ID', async () => {
  let called = 0;
  const handler = createHandler({ fetchImpl: async (url, init) => {
    called++;
    assert.equal(url, 'https://aitrans-iqwek72342.futureinvest.id/api/translate/text');
    assert.equal(init.headers['X-Api-Key'], SECRET); assert.equal(init.redirect, 'manual');
    assert.deepEqual(JSON.parse(init.body), { model: 'fast', targetLanguage: 'English', items: [{ id: 'segment-1', content: '登录' }] });
    return result();
  } });
  assert.deepEqual(await payload(await handler(request(), env), 200), { text: 'Log in', provider: 'ZTAITrans', model: 'fast' });
  assert.equal(called, 1);
});

test('Workers-compatible manual redirects never forward the secret to a redirect destination', async () => {
  let called = 0;
  const handler = createHandler({ fetchImpl: async (url, init) => {
    called++;
    assert.equal(init.redirect, 'manual');
    assert.equal(url, 'https://aitrans-iqwek72342.futureinvest.id/api/translate/text');
    return new Response(null, { status: 302, headers: { Location: 'https://unrelated.invalid/collect' } });
  } });
  assert.equal((await payload(await handler(request(), env), 400)).code, 'BACKUP_REQUEST');
  assert.equal(called, 1);
});

test('observed deployed response with single-item ID "1" is accepted only with an exact original source echo', async () => {
  const observed = { originalText: '登录', translatedText: 'Log in', targetLanguage: 'English', model: 'fast', items: [{ id: '1', originalText: '登录', translatedText: 'Log in' }] };
  const handler = createHandler({ fetchImpl: async (_, init) => {
    assert.deepEqual(JSON.parse(init.body).items, [{ id: 'segment-1', content: '登录' }]);
    return new Response(JSON.stringify(observed));
  } });
  assert.deepEqual(await payload(await handler(request(), env), 200), { text: 'Log in', provider: 'ZTAITrans', model: 'fast' });
});

test('single-item ID compatibility cannot bypass source, count, language, model or unrelated-ID checks', async () => {
  const row = { id: '1', originalText: '登录', translatedText: 'Log in' };
  const cases = [
    { items: [{ id: '1', translatedText: 'Log in' }] },
    { items: [{ ...row, originalText: 'other source' }] },
    { items: [{ ...row, id: 1 }] },
    { items: [{ ...row, id: '2' }] },
    { items: [{ ...row, id: 'anything-else' }] },
    { items: [row, row] },
    { originalText: 'other source', items: [row] },
    { targetLanguage: 'Japanese', items: [row] },
    { model: 'best', items: [row] }
  ];
  for (const body of cases) {
    const handler = createHandler({ fetchImpl: async () => new Response(JSON.stringify(body)) });
    assert.equal((await payload(await handler(request(), env), 502)).code, 'BACKUP_RESPONSE');
  }
});

test('missing key, unsupported methods and content type do not reach upstream', async () => {
  const handler = createHandler({ fetchImpl: () => assert.fail('must not call upstream') });
  assert.equal((await payload(await handler(request(), {}), 503)).code, 'BACKUP_NOT_CONFIGURED');
  assert.equal((await payload(await handler(new Request(origin + '/api/translation/backup'), env), 405)).code, 'METHOD_NOT_ALLOWED');
  assert.equal((await payload(await handler(new Request(origin + '/api/translation/status', { method: 'POST' }), env), 405)).code, 'METHOD_NOT_ALLOWED');
  assert.equal((await payload(await handler(new Request(origin + '/api/translation/backup', { method: 'POST', body: 'text' }), env), 415)).code, 'BACKUP_CONTENT_TYPE');
});

test('cross-origin, null origin and same-site cross-origin calls are rejected', async () => {
  const handler = createHandler({ fetchImpl: () => assert.fail('must not call upstream') });
  for (const headers of [{ Origin: 'https://evil.example' }, { Origin: 'null' }, { 'Sec-Fetch-Site': 'cross-site' }, { 'Sec-Fetch-Site': 'same-site' }]) {
    assert.equal((await payload(await handler(request(undefined, { headers }), env), 403)).code, 'BACKUP_ORIGIN');
  }
});

test('invalid JSON, arbitrary URL/model/tenant fields and unsupported languages cannot influence the proxy', async () => {
  const handler = createHandler({ fetchImpl: () => assert.fail('must not call upstream') });
  const cases = ['{bad', null, [], { content: '', locale: 'en' }, { content: 12, locale: 'en' }, { content: '你好', locale: 'file:///etc/passwd' }, { content: '你好', locale: '__proto__' }, { content: '你好', locale: 'en', url: 'https://evil.example' }, { content: '你好', locale: 'en', model: 'best' }, { content: '你好', locale: 'en', tenantId: 'other' }];
  for (const body of cases) { const response = await handler(request(body), env); await payload(response, 400); }
});

test('declared, streamed byte limits and Unicode character limits are enforced before any upstream call', async () => {
  const handler = createHandler({ fetchImpl: () => assert.fail('must not call upstream') });
  await payload(await handler(request({ content: 'x'.repeat(50001), locale: 'en' }), env), 413);
  await payload(await handler(request({ content: 'a'.repeat(270000), locale: 'en' }), env), 413);
  await payload(await handler(request(undefined, { headers: { 'Content-Length': String(300000) } }), env), 413);
  let cancelled = false;
  const stream = new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(140000)); controller.enqueue(new Uint8Array(140000)); }, cancel() { cancelled = true; } });
  const streamed = new Request(origin + '/api/translation/backup', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: stream, duplex: 'half' });
  await payload(await handler(streamed, env), 413); assert.equal(cancelled, true);
});

test('all seven target language names are fixed and response aliases are accepted', async () => {
  const names = { en: 'English', ja: 'Japanese', ko: 'Korean', fr: 'French', de: 'German', es: 'Spanish', 'zh-Hant': 'Traditional Chinese' };
  for (const [locale, name] of Object.entries(names)) {
    const handler = createHandler({ fetchImpl: async (_, init) => {
      assert.equal(JSON.parse(init.body).targetLanguage, name);
      return result('translated', { targetLanguage: locale, items: [{ id: 'segment-1', translatedText: 'translated' }] });
    } });
    await payload(await handler(request({ content: '你好', locale }), env), 200);
  }
});

test('malformed, shifted, truncated, mismatched and secret-reflecting successes are refused', async () => {
  const cases = [
    {}, { translatedText: 'unaccounted single legacy response' },
    { items: [] }, { items: [{ id: 'wrong', translatedText: 'Wrong item' }] },
    { items: [{ id: 'segment-1', translatedText: '' }] },
    { items: [{ id: 'segment-1', translatedText: '...' }] },
    { items: [{ id: 'segment-1', translatedText: '<译文>' }] },
    { items: [{ id: 'segment-1', originalText: 'other source', translatedText: 'Wrong source' }] },
    { items: [{ id: 'segment-1', translatedText: 'a' }, { id: 'segment-1', translatedText: 'b' }] },
    { targetLanguage: 'Japanese', items: [{ id: 'segment-1', translatedText: 'Other language' }] },
    { model: 'best', items: [{ id: 'segment-1', translatedText: 'Other model' }] },
    { items: [{ id: 'segment-1', translatedText: SECRET }] }
  ];
  for (const body of cases) {
    const handler = createHandler({ fetchImpl: async () => new Response(JSON.stringify(body)) });
    assert.equal((await payload(await handler(request(), env), 502)).code, 'BACKUP_RESPONSE');
  }
});

test('upstream auth/budget/disabled/config errors are sanitized and never disclose body, headers or credentials', async () => {
  const cases = [[401, 'UNAUTHORIZED', 'BACKUP_AUTH', 401], [402, 'TRANSLATE_BUDGET_EXCEEDED', 'BACKUP_BUDGET', 402], [503, 'TRANSLATE_DISABLED', 'BACKUP_DISABLED', 503], [503, 'TRANSLATE_NOT_CONFIGURED', 'BACKUP_NOT_CONFIGURED', 503]];
  for (const [status, code, expected, outputStatus] of cases) {
    const handler = createHandler({ fetchImpl: async () => new Response(JSON.stringify({ code, message: SECRET, stack: SECRET }), { status, headers: { 'X-Secret': SECRET } }) });
    const body = await payload(await handler(request(), env), outputStatus);
    assert.equal(body.code, expected); assert.equal(body.retryable, false);
    if (status === 402) assert.equal(body.quota, true);
  }
});

test('temporary errors expose only fixed friendly errors and bounded cooldown', async () => {
  for (const status of [429, 500, 502, 503]) {
    const handler = createHandler({ fetchImpl: async () => new Response(SECRET, { status, headers: { 'Retry-After': '999999999' } }) });
    const body = await payload(await handler(request(), env), status === 429 ? 429 : 502);
    assert.equal(body.retryable, true);
    if (status === 429) assert.equal(body.retryAfterMs, 86400000);
  }
});

test('network errors and malformed response JSON do not leak upstream exceptions', async () => {
  const network = createHandler({ fetchImpl: () => { throw new Error(SECRET); } });
  assert.equal((await payload(await network(request(), env), 502)).code, 'BACKUP_SERVICE');
  const malformed = createHandler({ fetchImpl: async () => new Response('<html>' + SECRET) });
  assert.equal((await payload(await malformed(request(), env), 502)).code, 'BACKUP_RESPONSE');
});

test('client cancellation aborts upstream and ignores a provider that returns late', async () => {
  const controller = new AbortController(); let upstreamSignal;
  const handler = createHandler({ fetchImpl: (_, init) => { upstreamSignal = init.signal; return new Promise(resolve => setTimeout(() => resolve(result()), 20)); } });
  const pending = handler(request(undefined, { signal: controller.signal }), env);
  await new Promise(resolve => setImmediate(resolve)); controller.abort();
  assert.equal((await payload(await pending, 499)).code, 'BACKUP_ABORTED');
  assert.equal(upstreamSignal.aborted, true);
});

test('already-aborted requests do not start upstream and timeouts remain bounded', async () => {
  const controller = new AbortController(); controller.abort();
  const early = createHandler({ fetchImpl: () => assert.fail('must not call upstream') });
  await payload(await early(request(undefined, { signal: controller.signal }), env), 499);
  let signal;
  const timeout = createHandler({ timeoutMs: 3, fetchImpl: (_, init) => { signal = init.signal; return new Promise(() => {}); } });
  const body = await payload(await timeout(request(), env), 504);
  assert.equal(body.code, 'BACKUP_TIMEOUT'); assert.equal(body.retryable, true); assert.equal(signal.aborted, true);
});
