const { test } = require('node:test');
const assert = require('node:assert/strict');
const P = require('../web/providers.js');
const T = require('../web/translation-service.js');
const Jobs = require('../web/translation-jobs.js');
const storage = () => { const values = new Map(); return { values, getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, String(value)), removeItem: key => values.delete(key) }; };
const response = (provider, text, status = 200, extra = {}) => ({ status, ok: status < 400, headers: { get: () => null }, json: async () => ({ provider, text, ...extra }) });
const deferred = () => { let resolve; const promise = new Promise(yes => { resolve = yes; }); return { promise, resolve }; };

test('provider vault defaults to tab session and explicitly remembered secrets stay outside the project storage record', () => {
  const local = storage(), session = storage(); local.setItem('langpack-prototype-v1', '{"projects":[]}');
  const vault = P.createVault({ localStorage: local, sessionStorage: session });
  vault.set('DeepL', { apiKey: 'fixture-deepl-key', plan: 'free' });
  assert.equal(local.getItem(P.LOCAL_KEY), null); assert.match(session.getItem(P.SESSION_KEY), /fixture-deepl-key/);
  assert.deepEqual(P.createVault({ localStorage: local, sessionStorage: session }).get('DeepL'), { apiKey: 'fixture-deepl-key', plan: 'free' });
  assert.equal(P.createVault({ localStorage: local, sessionStorage: storage() }).has('DeepL'), false);
  vault.set('DeepL', { apiKey: 'fixture-replacement-key', plan: 'pro' }, true);
  assert.equal(session.getItem(P.SESSION_KEY), null); assert.doesNotMatch(local.getItem(P.LOCAL_KEY), /fixture-deepl-key/);
  assert.equal(P.createVault({ localStorage: local, sessionStorage: storage() }).get('DeepL').plan, 'pro');
  vault.set('DeepL', { apiKey: 'fixture-session-again', plan: 'free' }, false);
  assert.equal(local.getItem(P.LOCAL_KEY), null);
  vault.remove('DeepL'); assert.equal(session.getItem(P.SESSION_KEY), null); assert.equal(vault.has('DeepL'), false);
  assert.equal(local.getItem('langpack-prototype-v1'), '{"projects":[]}');
});

test('five exact providers and explicit language capabilities preserve the 34 resource language distinctions', () => {
  assert.deepEqual(P.names, ['MyMemory', 'ZTAITrans', 'DeepL', 'Azure', 'Google']);
  assert.deepEqual(P.normalizeOrder(['DeepL', 'MyMemory', 'DeepL', 'arbitrary']), ['DeepL', 'MyMemory']);
  for (const locale of ['pt-BR', 'pt-PT', 'nb', 'zh-Hant', 'ms']) assert.equal(P.supports('DeepL', locale), true);
  for (const locale of ['fil', 'si']) assert.equal(P.supports('DeepL', locale), false);
  assert.equal(P.supports('Google', 'nb'), false); assert.equal(P.supports('Azure', 'nb'), true);
  assert.deepEqual(P.cleanCredentials('ZTAITrans', { developerToken: ' fixture-developer ', tenantId: 'must-not-send' }), { developerToken: 'fixture-developer' });
});

test('vault reports failed deletion of an old persistent or session copy and clear still visits every provider', () => {
  const local = storage(), session = storage();
  const vault = P.createVault({ localStorage: local, sessionStorage: session });
  vault.set('DeepL', { apiKey: 'fixture-old-local' }, true);
  local.removeItem = () => { throw new Error('blocked deletion'); };
  assert.equal(vault.set('DeepL', { apiKey: 'fixture-new-session' }, false), false);
  assert.match(local.getItem(P.LOCAL_KEY), /fixture-old-local/);
  session.removeItem = () => { throw new Error('blocked session deletion'); };
  assert.equal(vault.set('DeepL', { apiKey: 'fixture-next-local' }, true), false);
  vault.set('Google', { apiKey: 'fixture-google' }, false);
  assert.equal(vault.clear(), false);
  assert.equal(vault.has('DeepL'), false); assert.equal(vault.has('Google'), false);
});

test('unconfigured proxy clients never call the endpoint; credentials are used only in a same-origin POST body', async () => {
  const calls = [];
  const client = T.createProviderClient({ provider: 'DeepL', getCredentials: () => ({ apiKey: 'fixture-user-key', plan: 'free' }), fetchImpl: async (url, options) => { calls.push({ url, options }); return response('DeepL', 'Bonjour'); } });
  assert.equal((await client.translate('你好', 'fr')).text, 'Bonjour');
  assert.equal(calls[0].url, '/api/translation/provider');
  assert.equal(calls[0].options.method, 'POST'); assert.equal(calls[0].options.referrerPolicy, 'no-referrer');
  assert.deepEqual(JSON.parse(calls[0].options.body), { provider: 'DeepL', content: '你好', locale: 'fr', credentials: { apiKey: 'fixture-user-key', plan: 'free' } });
  assert.equal(calls[0].options.headers.Authorization, undefined);
  const missing = T.createProviderClient({ provider: 'ZTAITrans', fetchImpl: () => assert.fail('Missing BYOK must not use a shared account') });
  await assert.rejects(missing.translate('登录', 'en'), { code: 'PROVIDER_CONFIG', fatal: true });
});

test('MyMemory private keys use the same-origin JSON proxy and every protected chunk stays within 480 UTF-8 bytes', async () => {
  const secret = 'fixture-private-memory-key', calls = [];
  const source = '  ' + '中文😀'.repeat(170) + '{name}\r\n末行  ';
  const client = T.createProviderClient({ provider: 'MyMemory', getCredentials: () => ({ apiKey: secret, email: 'owner@example.com' }), fetchImpl: async (url, options) => { const body = JSON.parse(options.body); calls.push({ url, body }); return response('MyMemory', body.content); } });
  assert.equal((await client.translate(source, 'en')).text, source);
  assert.ok(calls.length > 1); assert.ok(calls.every(call => call.url === '/api/translation/provider' && !call.url.includes(secret)));
  assert.ok(calls.every(call => Buffer.byteLength(call.body.content) <= 480));
  assert.deepEqual(calls[0].body.credentials, { apiKey: secret, email: 'owner@example.com' });
  const missing = T.createProviderClient({ provider: 'MyMemory', fetchImpl: () => assert.fail('Anonymous MyMemory must stay direct') });
  await assert.rejects(missing.translate('登录', 'en'), { code: 'PROVIDER_CONFIG', fatal: true });
});

test('DeepL and Google safely split long paragraphs without splitting markers or losing source whitespace and newlines', async () => {
  const source = '  ' + '甲'.repeat(3998) + '{name}' + '😀乙'.repeat(2200) + '\r\n\n末行 %1$s  ';
  for (const provider of ['DeepL', 'Google']) {
    const chunks = [];
    const client = T.createProviderClient({ provider, getCredentials: () => ({ apiKey: 'fixture-key', plan: 'free' }), fetchImpl: async (_, options) => { const body = JSON.parse(options.body); chunks.push(body.content); return response(provider, body.content); } });
    assert.equal((await client.translate(source, 'en')).text, source);
    assert.ok(chunks.length > 2); assert.ok(chunks.every(chunk => Array.from(chunk).length <= 4000));
    assert.ok(chunks.every(chunk => !chunk.includes('\n') && !chunk.includes('\r')));
    assert.ok(chunks.every(chunk => !/ZXQ(?:PH|NL)\d*$|^\d+QXZ/.test(chunk)));
    assert.equal((await client.translate(source, 'en')).cached, true);
  }
  const complete = [];
  const ztai = T.createProviderClient({ provider: 'ZTAITrans', getCredentials: () => ({ developerToken: 'fixture-developer' }), fetchImpl: async (_, options) => { const body = JSON.parse(options.body); complete.push(body); return response('ZTAITrans', body.content); } });
  assert.equal((await ztai.translate(source, 'ja')).text, source);
  assert.equal(complete.length, 1); assert.deepEqual(complete[0].credentials, { developerToken: 'fixture-developer' });
});

test('proxy credentials and malformed upstream payloads never enter returned errors or successful translation text', async () => {
  const secret = 'fixture-private-provider-secret';
  for (const fetchImpl of [async () => { throw new Error(secret); }, async () => response('DeepL', '', 400, { code: secret, message: secret }), async () => response('DeepL', secret)]) {
    const client = T.createProviderClient({ provider: 'DeepL', getCredentials: () => ({ apiKey: secret }), maxRetries: 0, fetchImpl });
    await assert.rejects(client.translate('登录', 'en'), error => !JSON.stringify(error).includes(secret) && !error.message.includes(secret));
  }
});

test('provider cache is isolated by credential revision; late old-account results are rejected', async () => {
  let revision = 0, key = 'fixture-old'; const pending = deferred(); let calls = 0;
  const client = T.createProviderClient({ provider: 'Azure', getRevision: () => revision, getCredentials: () => ({ apiKey: key, region: 'eastasia' }), maxRetries: 0, fetchImpl: async () => { calls++; if (calls === 1) return pending.promise; return response('Azure', 'New account'); } });
  const old = client.translate('登录', 'en'); revision++; key = 'fixture-new'; pending.resolve(response('Azure', 'Old account'));
  await assert.rejects(old, { code: 'PROVIDER_CONFIG', fatal: true });
  assert.equal((await client.translate('登录', 'en')).text, 'New account');
  assert.equal((await client.translate('登录', 'en')).cached, true); assert.equal(calls, 2);
});

test('proxy cancellation ignores late results and broken placeholders never cache', async () => {
  const pending = deferred(), controller = new AbortController(); let calls = 0;
  const client = T.createProviderClient({ provider: 'Google', getCredentials: () => ({ apiKey: 'fixture-key' }), maxRetries: 0, fetchImpl: async () => { calls++; return pending.promise; } });
  const work = client.translate('你好{name}', 'en', { signal: controller.signal }); controller.abort();
  await assert.rejects(work, { name: 'AbortError' }); pending.resolve(response('Google', 'Hello')); assert.equal(calls, 1);
  const broken = T.createProviderClient({ provider: 'Google', getCredentials: () => ({ apiKey: 'fixture-key' }), maxRetries: 0, fetchImpl: async () => response('Google', 'Missing marker') });
  await assert.rejects(broken.translate('你好{name}', 'en'), { code: 'PLACEHOLDER' });
});

test('ordered routing uses the chosen platform, retries only transient errors and advances only for explicit quota or unsupported targets', async () => {
  let time = 1000, first = true; const calls = [], switches = [], circuits = {};
  const clients = {
    DeepL: { async translate() { calls.push('DeepL'); if (first) { first = false; throw Object.assign(new Error('quota'), { provider: 'DeepL', quota: true, retryAfterMs: 2000 }); } return { provider: 'DeepL', text: 'restored' }; } },
    Azure: { async translate() { calls.push('Azure'); return { provider: 'Azure', text: 'fallback' }; } }
  };
  const client = T.createOrderedClient({ order: ['DeepL', 'Azure'], clients, circuits, now: () => time, onFallback: value => switches.push(value) });
  assert.equal((await client.translate('一', 'en')).provider, 'Azure');
  assert.equal((await client.translate('二', 'en')).provider, 'Azure'); assert.equal(circuits.DeepL.until, 3000);
  time = 3000; assert.equal((await client.translate('三', 'en')).provider, 'DeepL');
  assert.deepEqual(calls, ['DeepL', 'Azure', 'Azure', 'DeepL']);
  assert.equal((await client.translate('四', 'fil')).provider, 'Azure'); assert.equal(switches.at(-1).reason, 'unsupported');
  const noFallback = T.createOrderedClient({ order: ['DeepL', 'Azure'], fallback: false, clients });
  await assert.rejects(noFallback.translate('五', 'si'), { unsupported: true });
});

test('authentication, missing configuration, ordinary request failures and rate limits never spend another platform quota', async () => {
  for (const code of ['PROVIDER_AUTH', 'PROVIDER_CONFIG', 'PROVIDER_RATE_LIMIT', 'PROVIDER_REQUEST']) {
    let secondCalls = 0;
    const primary = T.createProviderClient({ provider: 'DeepL', getCredentials: () => ({ apiKey: 'fixture-key' }), maxRetries: 1, sleep: async () => {}, fetchImpl: async () => response('DeepL', '', code === 'PROVIDER_RATE_LIMIT' ? 429 : 400, { code }) });
    const client = T.createOrderedClient({ order: ['DeepL', 'Azure'], clients: { DeepL: primary, Azure: { async translate() { secondCalls++; } } } });
    await assert.rejects(client.translate('一', 'en'), { code }); assert.equal(secondCalls, 0);
  }
});

test('actual anonymous MyMemory authentication wins over contradictory quota flags without routing to another configured account', async () => {
  const M = require('../web/mymemory.js');
  for (const fields of [{ status: 401, responseStatus: 200 }, { status: 403, responseStatus: 200 }, { status: 200, responseStatus: 401 }]) {
    let nextCalls = 0;
    const circuits = {};
    const primary = M.createClient({ minIntervalMs: 0, maxRetries: 0, fetchImpl: async () => ({ ok: fields.status < 400, status: fields.status, headers: { get: () => null }, json: async () => ({ responseStatus: fields.responseStatus, quotaFinished: true, responseDetails: 'Daily quota reached', responseData: { translatedText: 'MYMEMORY WARNING: Out of quota' } }) }) });
    const client = T.createOrderedClient({ order: ['MyMemory', 'Azure'], clients: { MyMemory: primary, Azure: { async translate() { nextCalls++; return { provider: 'Azure', text: 'must not spend' }; } } }, circuits });
    await assert.rejects(client.translate('登录', 'en'), { fatal: true, quota: false });
    assert.equal(nextCalls, 0); assert.equal(circuits.MyMemory.until, 0);
  }
});

test('all five successful provider results remain recognized and reusable without provider changes forcing a new request', async () => {
  for (const provider of P.names) {
    const row = { id: provider, key: 'login', source: '登录', translations: {}, reviewed: {} };
    const job = Jobs.createJob({ entries: [row], locales: ['en'] });
    await Jobs.run(job, { client: { async translate() { return { provider, text: provider + ' result' }; } } });
    assert.equal(row.translationMeta.en.provider, provider);
    const again = Jobs.createJob({ entries: [row], locales: ['en'] });
    await Jobs.run(again, { client: { async translate() { assert.fail('Provider switch must not discard existing valid translations'); } } });
    assert.equal(again.items[0].reused, true);
  }
});
