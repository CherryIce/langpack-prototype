import test from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../worker/handler.js';

const owner = 'test-owner-access-token-32-bytes-long';
const env = { TRANSLATION_API_KEY: 'test-owner-upstream-secret', LANGPACK_DEVELOPER_TOKEN: owner };
const key = 'test-user-platform-key';
const origin = 'https://example.test';
const request = (body, headers = {}) => new Request(origin + '/api/translation/provider', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: origin, ...headers }, body: JSON.stringify(body) });
const body = (provider, credentials = { apiKey: key }, locale = 'en') => ({ provider, credentials, locale, content: '登录' });
const response = data => new Response(JSON.stringify(data));
const ztai = () => response({ targetLanguage: 'English', model: 'fast', items: [{ id: 'segment-1', originalText: '登录', translatedText: 'Log in' }] });

test('old endpoint is closed to anonymous, wrong token and unset developer configuration before upstream', async () => {
  const handle = createHandler({ fetchImpl: () => assert.fail('unauthorized upstream') });
  for (const [runtime, token] of [[env, ''], [env, 'wrong'], [{ TRANSLATION_API_KEY: env.TRANSLATION_API_KEY }, owner], [{ LANGPACK_DEVELOPER_TOKEN: owner }, owner]]) {
    const req = new Request(origin + '/api/translation/backup', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-LangPack-Developer-Token': token }, body: JSON.stringify({ content: '登录', locale: 'en' }) });
    const r = await handle(req, runtime); assert.equal(r.status, 401); assert.equal((await r.json()).fatal, true);
  }
});

test('developer validation uses only local configuration and never exposes credentials', async () => {
  const handle = createHandler({ fetchImpl: () => assert.fail('status must be free') });
  for (const [token, allowed] of [[owner, true], ['wrong', false], ['', false]]) {
    const r = await handle(new Request(origin + '/api/translation/status', { headers: { 'X-LangPack-Developer-Token': token } }), env);
    const data = await r.json(); assert.equal(data.backupConfigured, allowed); assert.equal(data.developerConfigured, true);
    assert.ok(!JSON.stringify(data).includes(owner)); assert.ok(!JSON.stringify(data).includes(env.TRANSLATION_API_KEY));
  }
});

test('explicit developer ZTAI mode uses environment key, while BYOK never borrows it', async () => {
  const seen = [];
  const handle = createHandler({ fetchImpl: async (_, init) => { seen.push(init.headers['X-Api-Key']); return ztai(); } });
  assert.equal((await handle(request(body('ZTAITrans', { developerToken: owner })), env)).status, 200);
  assert.equal((await handle(request(body('ZTAITrans')), env)).status, 200);
  assert.deepEqual(seen, [env.TRANSLATION_API_KEY, key]);
  const blocked = await handle(request(body('ZTAITrans', {})), env); assert.equal(blocked.status, 400); assert.equal(seen.length, 2);
  assert.equal((await handle(request(body('ZTAITrans', { developerToken: 'wrong' })), env)).status, 401); assert.equal(seen.length, 2);
});

test('provider endpoints, credential headers, models and exact regional mappings are fixed', async () => {
  const cases = [
    ['Azure', 'pt-BR', { apiKey: key, region: 'eastasia' }, 'api.cognitive.microsofttranslator.com', 'Ocp-Apim-Subscription-Key', 'pt'],
    ['Azure', 'pt-PT', { apiKey: key }, 'api.cognitive.microsofttranslator.com', 'Ocp-Apim-Subscription-Key', 'pt-pt'],
    ['Azure', 'nb', { apiKey: key }, 'api.cognitive.microsofttranslator.com', 'Ocp-Apim-Subscription-Key', 'nb'],
    ['Google', 'pt-PT', { apiKey: key }, 'translation.googleapis.com', 'X-Goog-Api-Key', 'pt-PT'],
    ['DeepL', 'pt-BR', { apiKey: key, plan: 'free' }, 'api-free.deepl.com', 'Authorization', 'PT-BR'],
    ['DeepL', 'nb', { apiKey: key, plan: 'pro' }, 'api.deepl.com', 'Authorization', 'NB']
  ];
  for (const [provider, locale, credentials, host, header, target] of cases) {
    const handle = createHandler({ fetchImpl: async (url, init) => {
      const u = new URL(url), payload = JSON.parse(init.body);
      assert.equal(u.host, host); assert.equal(u.protocol, 'https:'); assert.equal(init.redirect, 'manual'); assert.ok(init.headers[header].includes(key)); assert.ok(!u.href.includes(key));
      if (provider === 'Azure') { assert.equal(u.searchParams.get('to'), target); assert.equal(u.searchParams.get('from'), 'zh-Hans'); assert.deepEqual(payload, [{ Text: '登录' }]); return response([{ translations: [{ text: 'Log in', to: target }] }]); }
      if (provider === 'DeepL') { assert.equal(payload.target_lang, target); assert.equal(payload.source_lang, 'ZH'); return response({ translations: [{ text: 'Log in' }] }); }
      assert.equal(payload.target, target); assert.equal(payload.model, 'nmt'); assert.equal(payload.format, 'text'); return response({ data: { translations: [{ translatedText: 'Log &amp; in' }] } });
    } });
    const r = await handle(request(body(provider, credentials, locale)), env); assert.equal(r.status, 200); const data = await r.json(); assert.equal(data.provider, provider); assert.equal(data.text, provider === 'Google' ? 'Log & in' : 'Log in');
  }
});

test('unsupported exact languages and fixed source are refused without provider calls', async () => {
  const handle = createHandler({ fetchImpl: () => assert.fail('unsupported language upstream') });
  for (const [provider, locale] of [['DeepL', 'fil'], ['DeepL', 'si'], ['Google', 'nb'], ['Azure', 'zh-Hans'], ['Azure', 'no'], ['Google', 'pt']]) {
    const r = await handle(request(body(provider, { apiKey: key }, locale)), env); assert.equal(r.status, 400); assert.equal((await r.json()).unsupported, true);
  }
});

test('arbitrary endpoints, fields, plans, forged header credentials and developer tenant selection cannot alter upstream', async () => {
  const handle = createHandler({ fetchImpl: () => assert.fail('invalid upstream') });
  const cases = [
    { ...body('Google'), endpoint: 'https://evil.test' },
    body('DeepL', { apiKey: key, plan: 'auto' }), body('DeepL', { apiKey: key, endpoint: 'https://evil.test' }),
    body('Azure', { apiKey: key, region: 'x\r\nInjected: yes' }), body('Azure', { apiKey: 'x\r\nInjected: yes' }),
    body('ZTAITrans', { developerToken: owner, tenantId: 'other' }), body('ZTAITrans', { apiKey: key, developerToken: owner }),
    body('ZTAITrans', { apiKey: key, tenantId: '../other' }), body('Google', { apiKey: '' }), body('__proto__')
  ];
  for (const value of cases) { const r = await handle(request(value), env); assert.equal(r.status, 400); }
});

test('quota, auth and rate limits use trusted provider codes, with sanitized errors', async () => {
  const cases = [
    ['DeepL', 456, {}, 402, true], ['Azure', 403, { error: { code: 403001 } }, 402, true],
    ['Google', 403, { error: { errors: [{ reason: 'dailyLimitExceeded' }] } }, 402, true],
    ['Google', 403, { error: { errors: [{ reason: 'userRateLimitExceeded' }] } }, 429, false],
    ['Google', 403, { error: { errors: [{ reason: 'rateLimitExceeded' }] } }, 429, false],
    ['Google', 403, { error: { errors: [{ reason: 'keyInvalid' }], message: key } }, 401, false],
    ['Azure', 403, { error: { code: 403000, message: key } }, 401, false],
    ['DeepL', 429, { message: key }, 429, false]
    ,['ZTAITrans', 402, { code: 'TRANSLATE_BUDGET_EXCEEDED', message: key }, 402, true]
    ,['ZTAITrans', 401, { code: 'UNAUTHORIZED', message: key }, 401, false]
    ,['ZTAITrans', 503, { code: 'TRANSLATE_DISABLED', message: key }, 400, false]
  ];
  for (const [provider, status, data, expected, quota] of cases) {
    const handle = createHandler({ fetchImpl: async () => new Response(JSON.stringify(data), { status }) });
    const r = await handle(request(body(provider)), env); assert.equal(r.status, expected); const output = await r.json();
    assert.equal(!!output.quota, quota); assert.ok(!JSON.stringify(output).includes(key)); assert.ok(!JSON.stringify(output).includes(env.TRANSLATION_API_KEY));
    if (expected === 429) { assert.equal(output.retryable, true); assert.equal(output.code, 'PROVIDER_RATE_LIMIT'); }
    if (expected === 402) assert.equal(output.code, 'PROVIDER_QUOTA');
  }
});

test('upstream redirects never trigger another call and cannot forward user credentials', async () => {
  for (const provider of ['ZTAITrans', 'DeepL', 'Azure', 'Google']) {
    let calls = 0; const handle = createHandler({ fetchImpl: async (_, init) => { calls++; assert.equal(init.redirect, 'manual'); return new Response(null, { status: 302, headers: { Location: 'https://evil.test' } }); } });
    const r = await handle(request(body(provider)), env); assert.equal(r.status, 400); assert.equal(calls, 1);
  }
});

test('malformed successes, wrong target echoes and reflected secrets are rejected', async () => {
  for (const [provider, data] of [['DeepL', { translations: [{ text: key }] }], ['Google', { data: { translations: [{ translatedText: key }] } }], ['Azure', [{ translations: [{ text: 'wrong', to: 'pt' }] }]], ['DeepL', { translations: [{ text: 'one' }, { text: 'two' }] }], ['Google', '<html>']]) {
    const handle = createHandler({ fetchImpl: async () => response(data) });
    const r = await handle(request(body(provider)), env); assert.equal(r.status, 502); const output = await r.json(); assert.equal(output.code, 'PROVIDER_RESPONSE'); assert.ok(!JSON.stringify(output).includes(key));
  }
});

test('every supported canonical language reaches the expected exact provider target without losing regional distinctions', async () => {
  const locales = ['zh-Hant','en','pt-BR','pt-PT','ms','th','fr','es','ar','fil','vi','ru','tr','id','ja','ko','de','hi','hu','it','ro','sv','bg','pl','da','fi','nl','cs','sk','uk','el','nb','hr','si'];
  for (const provider of ['Azure', 'Google', 'DeepL']) {
    let count = 0;
    for (const locale of locales.filter(code => provider === 'Azure' || provider === 'Google' && code !== 'nb' || provider === 'DeepL' && !['fil','si'].includes(code))) {
      const expected = provider === 'Azure' ? ({'pt-BR':'pt','pt-PT':'pt-pt'})[locale] || locale : provider === 'Google' ? ({'zh-Hant':'zh-TW'})[locale] || locale : ({'zh-Hant':'ZH-HANT',en:'EN-US','pt-BR':'PT-BR','pt-PT':'PT-PT'})[locale] || locale.toUpperCase();
      const handle = createHandler({ fetchImpl: async (url, init) => {
        count++; const data = JSON.parse(init.body);
        if (provider === 'Azure') { assert.equal(new URL(url).searchParams.get('to'), expected); return response([{ translations: [{ text: 'translated', to: expected }] }]); }
        if (provider === 'Google') { assert.equal(data.target, expected); return response({ data: { translations: [{ translatedText: 'translated' }] } }); }
        assert.equal(data.target_lang, expected); return response({ translations: [{ text: 'translated' }] });
      } });
      assert.equal((await handle(request(body(provider, { apiKey: key }, locale)), {})).status, 200);
    }
    assert.equal(count, ({ Azure: 34, Google: 33, DeepL: 32 })[provider]);
  }
});

test('provider-specific byte limits, global character limit and cross-origin rejection happen before upstream', async () => {
  const handle = createHandler({ fetchImpl: () => assert.fail('invalid content reached upstream') });
  for (const provider of ['Google', 'DeepL']) {
    const payload = { ...body(provider), content: '汉'.repeat(50000) };
    assert.equal((await handle(request(payload), {})).status, 413);
  }
  assert.equal((await handle(request({ ...body('Azure'), content: '😀'.repeat(50001) }), {})).status, 413);
  assert.equal((await handle(request(body('Google'), { Origin: 'https://evil.test' }), env)).status, 403);
  assert.equal((await handle(request(body('Google'), { 'Sec-Fetch-Site': 'cross-site' }), env)).status, 403);
});

test('new provider timeout and cancellation abort upstream without leaking credentials', async () => {
  let upstreamSignal;
  const timeout = createHandler({ timeoutMs: 3, fetchImpl: async (_, init) => { upstreamSignal = init.signal; return new Promise(() => {}); } });
  const r = await timeout(request(body('Google')), {}); assert.equal(r.status, 504); assert.equal((await r.json()).code, 'PROVIDER_TIMEOUT'); assert.equal(upstreamSignal.aborted, true);
  const controller = new AbortController(); let start;
  const started = new Promise(resolve => { start = resolve; });
  const cancel = createHandler({ fetchImpl: async (_, init) => { upstreamSignal = init.signal; start(); return new Promise(() => {}); } });
  const req = new Request(request(body('Azure')), { signal: controller.signal });
  const pending = cancel(req, {}); await started; controller.abort();
  const aborted = await pending; assert.equal(aborted.status, 499); assert.equal((await aborted.json()).code, 'PROVIDER_ABORTED'); assert.equal(upstreamSignal.aborted, true);
});

test('private MyMemory key stays in the same-origin POST and only reaches the fixed official GET upstream', async () => {
  let calls = 0;
  const handle = createHandler({ fetchImpl: async (url, init) => {
    calls++; const u = new URL(url);
    assert.equal(u.origin + u.pathname, 'https://api.mymemory.translated.net/get');
    assert.equal(init.method, 'GET'); assert.equal(init.body, undefined); assert.equal(init.redirect, 'manual');
    assert.equal(u.searchParams.get('key'), key); assert.equal(u.searchParams.get('q'), '登录');
    assert.equal(u.searchParams.get('de'), 'fixture@example.test'); assert.equal(u.searchParams.get('langpair'), 'zh-CN|zh-TW');
    assert.equal(u.searchParams.has('ip'), false, 'Node must not forward a spoofed visitor IP');
    return response({ responseStatus: 200, quotaFinished: false, responseDetails: '', responseData: { translatedText: '登入' } });
  } });
  const req = request(body('MyMemory', { apiKey: key, email: 'fixture@example.test' }, 'zh-Hant'), { 'CF-Connecting-IP': '1.2.3.4' });
  assert.ok(!req.url.includes(key));
  const r = await handle(req, env); assert.equal(r.status, 200); assert.deepEqual(await r.json(), { text: '登入', provider: 'MyMemory' }); assert.equal(calls, 1);
});

test('private MyMemory ordinary quota text is accepted but real provider warnings still open quota', async () => {
  const warning = 'MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS. NEXT AVAILABLE IN 1 HOUR';
  for (const [translatedText, quota] of [['Next available in 10 minutes', false], ['Out of quota', false], ['Daily quota reached', false], [warning, true]]) {
    const handle = createHandler({ fetchImpl: async () => response({ responseStatus: 200, quotaFinished: false, responseDetails: '', responseData: { translatedText } }) });
    const r = await handle(request(body('MyMemory')), {}); assert.equal(r.status, quota ? 402 : 200);
    const data = await r.json(); if (quota) { assert.equal(data.code, 'PROVIDER_QUOTA'); assert.equal(data.quota, true); } else assert.equal(data.text, translatedText);
  }
});

test('private MyMemory requires an explicit private key and preserves the 480-byte and exact-language boundaries', async () => {
  let calls = 0;
  const handle = createHandler({ fetchImpl: async () => { calls++; return response({ responseStatus: 200, responseData: { translatedText: 'translated' } }); } });
  assert.equal((await handle(request(body('MyMemory', {})), env)).status, 400);
  assert.equal((await handle(request(body('MyMemory', { apiKey: key, email: 'bad-email' })), env)).status, 400);
  assert.equal((await handle(request(body('MyMemory', { apiKey: key }, 'pt-BR')), env)).status, 400);
  assert.equal((await handle(request({ ...body('MyMemory'), content: '汉'.repeat(161) }), env)).status, 413);
  assert.equal(calls, 0);
  assert.equal((await handle(request({ ...body('MyMemory'), content: '汉'.repeat(160) }), env)).status, 200);
  assert.equal(calls, 1);
});

test('private MyMemory authorization failures outrank contradictory quota metadata', async () => {
  for (const [httpStatus, serviceStatus] of [[401, 200], [403, 429], [200, 401]]) {
    const handle = createHandler({ fetchImpl: async () => new Response(JSON.stringify({ responseStatus: serviceStatus, quotaFinished: true, responseDetails: 'Out of quota', responseData: { translatedText: 'Log in' } }), { status: httpStatus }) });
    const r = await handle(request(body('MyMemory')), {}); assert.equal(r.status, 401);
    const data = await r.json(); assert.equal(data.code, 'PROVIDER_AUTH'); assert.equal(data.fatal, true); assert.equal(!!data.quota, false);
  }
  const exhausted = createHandler({ fetchImpl: async () => response({ responseStatus: 403, quotaFinished: true, responseDetails: 'Daily quota reached', responseData: { translatedText: '' } }) });
  const quota = await exhausted(request(body('MyMemory')), {}); assert.equal(quota.status, 402); assert.equal((await quota.json()).quota, true);
  const forbidden = createHandler({ fetchImpl: async () => response({ responseStatus: 403, quotaFinished: false, responseDetails: 'Forbidden', responseData: { translatedText: '' } }) });
  const auth = await forbidden(request(body('MyMemory')), {}); assert.equal(auth.status, 401); assert.equal((await auth.json()).fatal, true);
});
