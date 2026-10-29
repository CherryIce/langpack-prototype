const test = require('node:test');
const assert = require('node:assert/strict');
const { createBackupClient, createClient } = require('../web/translation-service.js');

const reply = (text, status = 200, body) => ({ status, ok: status >= 200 && status < 300, headers: { get: () => null }, json: async () => body || { text, provider: 'ZTAITrans' } });
const fail = (code, extra = {}) => Object.assign(new Error(code), { code, ...extra });
const quota = extra => fail('QUOTA', { quota: true, ...extra });
const tick = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }

test('backup only calls a same-origin POST endpoint and never sends credentials in a request body or authorization headers', async () => {
  const calls = [];
  const client = createBackupClient({ fetchImpl: async (url, options) => { calls.push({ url, options }); return reply('Hello'); } });
  const result = await client.translate('你好', 'en');
  assert.equal(result.text, 'Hello'); assert.equal(result.provider, 'ZTAITrans'); assert.equal(result.requestCount, 1);
  assert.equal(calls[0].url, '/api/translation/backup'); assert.equal(calls[0].options.method, 'POST');
  assert.equal(calls[0].options.credentials, 'same-origin');
  assert.deepEqual(JSON.parse(calls[0].options.body), { content: '你好', locale: 'en' });
  assert.deepEqual(Object.keys(calls[0].options.headers).sort(), ['Accept', 'Content-Type']);
  assert.throws(() => createBackupClient({ endpoint: 'https://example.com/secret' }), /同源/);
  assert.throws(() => createBackupClient({ endpoint: '//example.com/secret' }), /同源/);
  assert.throws(() => createBackupClient({ endpoint: '/\\example.com/secret' }), /同源/);
});

test('placeholder occurrences, literal marker-like text, CRLF and outer whitespace survive a whole-paragraph request', async () => {
  let content;
  const source = '  你好{name}、{name}，{{ count }}，%s，%1$s，%%。ZXQPH0QXZ\r\n下一行\n末行\t ';
  const client = createBackupClient({ fetchImpl: async (_, options) => { content = JSON.parse(options.body).content; return reply(content); } });
  const result = await client.translate(source, 'en');
  assert.equal(result.text, source);
  assert.equal(content.includes('{name}'), false); assert.equal(content.includes('\n'), false);
  assert.equal(result.requestCount, 1);
});

test('long paragraphs are sent whole instead of MyMemory-sized chunks', async () => {
  const source = '这是较长的中文段落。'.repeat(150);
  const sizes = [];
  const client = createBackupClient({ fetchImpl: async (_, options) => { const content = JSON.parse(options.body).content; sizes.push(Buffer.byteLength(content)); return reply('A complete translated paragraph.'); } });
  assert.equal((await client.translate(source, 'en')).text, 'A complete translated paragraph.');
  assert.deepEqual(sizes, [Buffer.byteLength(source)]); assert.ok(sizes[0] > 500);
});

test('missing, duplicate or unexpected placeholder markers are rejected and not cached', async () => {
  for (const transform of [text => text.replace(/ZXQPH\d+QXZ/, ''), text => text + ' ZXQPH0QXZ', text => text + ' {extra}']) {
    let calls = 0;
    const client = createBackupClient({ fetchImpl: async (_, options) => { calls++; return reply(transform(JSON.parse(options.body).content)); } });
    await assert.rejects(client.translate('欢迎{name}', 'en'), { code: 'PLACEHOLDER' });
    await assert.rejects(client.translate('欢迎{name}', 'en'), { code: 'PLACEHOLDER' });
    assert.equal(calls, 2);
  }
});

test('a lost newline marker fails rather than silently flattening the source document', async () => {
  const client = createBackupClient({ fetchImpl: async (_, options) => reply(JSON.parse(options.body).content.replace(/ZXQNL\d+QXZ/, ' ')) });
  await assert.rejects(client.translate('第一段\n第二段', 'en'), { code: 'PLACEHOLDER' });
});

test('marker casing and spacing normalization restores placeholders', async () => {
  const client = createBackupClient({ fetchImpl: async (_, options) => reply(JSON.parse(options.body).content.replace(/ZXQPH(\d+)QXZ/g, (_, n) => 'zxq ph ' + n + ' qxz')) });
  assert.equal((await client.translate('欢迎{name}', 'en')).text, '欢迎{name}');
});

test('temporary service or network failure retries at most once with provider-tagged notifications', async () => {
  for (const mode of ['service', 'network']) {
    let calls = 0; const waits = [], retries = [];
    const client = createBackupClient({ sleep: async ms => waits.push(ms), fetchImpl: async () => {
      calls++; if (calls === 1) { if (mode === 'network') throw new TypeError('network down'); return reply('', 502, { code: 'TRANSLATE_ALL_MODELS_FAILED' }); }
      return reply('Translation');
    } });
    const result = await client.translate('测试', 'en', { onRetry: value => retries.push(value) });
    assert.equal(result.requestCount, 2); assert.equal(calls, 2); assert.deepEqual(waits, [1000]);
    assert.equal(retries.length, 1); assert.equal(retries[0].provider, 'ZTAITrans');
  }
  let failures = 0;
  const client = createBackupClient({ maxRetries: 8, sleep: async () => {}, fetchImpl: async () => { failures++; throw new TypeError('offline'); } });
  await assert.rejects(client.translate('测试', 'en'), { code: 'NETWORK', provider: 'ZTAITrans' });
  assert.equal(failures, 2);
});

test('auth, budget and disabled/configuration errors never retry even when HTTP status is 503', async () => {
  for (const [status, code] of [[401, 'UNAUTHORIZED'], [402, 'TRANSLATE_BUDGET_EXCEEDED'], [503, 'TRANSLATE_DISABLED'], [503, 'TRANSLATE_NOT_CONFIGURED'], [503, 'BACKUP_NOT_CONFIGURED']]) {
    let calls = 0;
    const client = createBackupClient({ fetchImpl: async () => { calls++; return reply('', status, { code, message: 'upstream detail' }); }, sleep: async () => assert.fail('must not back off') });
    await assert.rejects(client.translate('测试', 'en'), error => error.code === code && error.provider === 'ZTAITrans' && error.retryable === false && (status !== 402 || error.quota === true));
    assert.equal(calls, 1);
  }
});

test('business error codes in HTTP 200 and malformed/empty responses do not become translations', async () => {
  for (const response of [reply('', 200, { code: 'TRANSLATE_DISABLED' }), reply('', 200, {}), reply(''), reply('...'), reply('<译文>'), reply('MYMEMORY WARNING: quota'), reply('Internal Server Error')]) {
    let calls = 0;
    const client = createBackupClient({ fetchImpl: async () => { calls++; return response; } });
    await assert.rejects(client.translate('测试', 'en'));
    assert.equal(calls, 1);
  }
});

test('normalized backend auth, disabled and configuration codes are fatal and never retry across HTTP/body combinations', async () => {
  for (const status of [200, 401, 503]) {
    for (const code of ['BACKUP_AUTH', 'BACKUP_DISABLED', 'BACKUP_NOT_CONFIGURED']) {
      let calls = 0;
      const client = createBackupClient({ fetchImpl: async () => { calls++; return reply('', status, { code, retryable: true, message: 'arbitrary upstream detail and credential must not leak' }); }, sleep: async () => assert.fail('must not retry a fatal configuration error') });
      await assert.rejects(client.translate('测试', 'en'), error => error.code === code && error.provider === 'ZTAITrans' && error.fatal === true && error.retryable === false && !error.message.includes('credential') && !error.message.includes('arbitrary'));
      assert.equal(calls, 1);
    }
  }
});

test('normalized backend budget code remains quota without automatic retry', async () => {
  for (const status of [200, 402, 503]) {
    let calls = 0;
    const client = createBackupClient({ fetchImpl: async () => { calls++; return reply('', status, { code: 'BACKUP_BUDGET', retryable: true, message: 'private budget detail' }); }, sleep: async () => assert.fail('must not retry exhausted budget') });
    await assert.rejects(client.translate('测试', 'en'), error => error.code === 'BACKUP_BUDGET' && error.provider === 'ZTAITrans' && error.quota === true && error.retryable === false && !error.message.includes('private'));
    assert.equal(calls, 1);
  }
});

test('trusted backend retryable:false suppresses retries for service and timeout codes', async () => {
  for (const [status, code] of [[200, 'BACKUP_SERVICE'], [503, 'BACKUP_SERVICE'], [504, 'BACKUP_TIMEOUT']]) {
    let calls = 0;
    const client = createBackupClient({ fetchImpl: async () => { calls++; return reply('', status, { code, retryable: false, message: 'upstream stack trace' }); }, sleep: async () => assert.fail('must honor retryable:false') });
    await assert.rejects(client.translate('测试', 'en'), error => error.code === code && error.retryable === false && !error.message.includes('stack trace'));
    assert.equal(calls, 1);
  }
});

test('normalized BACKUP_ABORTED remains a pause and is not retried or converted into a service failure', async () => {
  for (const status of [200, 499, 503]) {
    let calls = 0;
    const backup = createBackupClient({ fetchImpl: async () => { calls++; return reply('', status, { code: 'BACKUP_ABORTED', retryable: true }); }, sleep: async () => assert.fail('must not retry a paused request') });
    const client = createClient({ circuit: { until: Date.now() + 1000 }, primary: { translate: async () => assert.fail('circuit is open') }, backup });
    await assert.rejects(client.translate('测试', 'en'), { name: 'AbortError', code: 'BACKUP_ABORTED', provider: 'ZTAITrans', retryable: false });
    assert.equal(calls, 1);
  }
});

test('trusted retryAfterMs combines with headers and cooldowns above 60 seconds are surfaced', async () => {
  for (const [header, body, expected] of [['2', 4000, 4000], ['5', 3000, 5000]]) {
    const waits = []; let calls = 0;
    const client = createBackupClient({ sleep: async ms => waits.push(ms), fetchImpl: async () => {
      calls++; if (calls > 1) return reply('translated');
      const response = reply('', 503, { code: 'BACKUP_SERVICE', retryable: true, retryAfterMs: body });
      response.headers.get = () => header;
      return response;
    } });
    assert.equal((await client.translate('测试', 'en')).text, 'translated');
    assert.deepEqual(waits, [expected]); assert.equal(calls, 2);
  }
  let calls = 0;
  const client = createBackupClient({ fetchImpl: async () => { calls++; return reply('', 504, { code: 'BACKUP_TIMEOUT', retryable: true, retryAfterMs: 60001 }); }, sleep: async () => assert.fail('must not shorten a long cooldown') });
  await assert.rejects(client.translate('测试', 'en'), { code: 'BACKUP_TIMEOUT', retryAfterMs: 60001, retryable: true });
  assert.equal(calls, 1);
});

test('successful backup cache is bounded and bypassCache requests a fresh result', async () => {
  let calls = 0;
  const client = createBackupClient({ maxCacheEntries: 1, fetchImpl: async () => { calls++; return reply('translated'); } });
  assert.equal((await client.translate('一', 'en')).cached, false);
  assert.equal((await client.translate('一', 'en')).cached, true);
  assert.equal((await client.translate('一', 'en', { bypassCache: true })).cached, false);
  await client.translate('二', 'en'); await client.translate('一', 'en');
  assert.equal(calls, 4);
});

test('abort interrupts fetch immediately and an ignored late response is never cached', async () => {
  const late = deferred(); let calls = 0;
  const client = createBackupClient({ fetchImpl: async () => { calls++; return calls === 1 ? late.promise : reply('new result'); } });
  const controller = new AbortController();
  const pending = client.translate('测试', 'en', { signal: controller.signal });
  await tick(); controller.abort();
  await assert.rejects(pending, { code: 'ABORTED' });
  late.resolve(reply('old result')); await tick();
  assert.equal((await client.translate('测试', 'en')).text, 'new result');
  assert.equal(calls, 2);
});

test('timeout is finite and aborting backoff prevents the retry request', async () => {
  const timed = createBackupClient({ timeoutMs: 5, maxRetries: 0, fetchImpl: async () => new Promise(() => {}) });
  await assert.rejects(timed.translate('测试', 'en'), { code: 'TIMEOUT', retryable: true });
  let calls = 0; const controller = new AbortController(); const waiting = deferred();
  const client = createBackupClient({ fetchImpl: async () => { calls++; throw new Error('offline'); }, sleep: async () => waiting.promise });
  const pending = client.translate('测试', 'en', { signal: controller.signal, onRetry: () => controller.abort() });
  await assert.rejects(pending, { code: 'ABORTED' }); assert.equal(calls, 1); waiting.resolve();
});

test('quota switches once and the same circuit sends subsequent entries directly to backup', async () => {
  let primaryCalls = 0, backupCalls = 0; const events = [], circuit = { until: 0 };
  const client = createClient({ now: () => 1000, circuit, onFallback: event => events.push(event), primary: { translate: async () => { primaryCalls++; throw quota(); } }, backup: { translate: async () => { backupCalls++; return { text: 'ok', provider: 'ZTAITrans' }; } } });
  assert.equal((await client.translate('一', 'en')).provider, 'ZTAITrans');
  assert.equal((await client.translate('二', 'ja')).provider, 'ZTAITrans');
  assert.equal(primaryCalls, 1); assert.equal(backupCalls, 2); assert.equal(events.length, 1);
  assert.deepEqual(events[0], { from: 'MyMemory', to: 'ZTAITrans', reason: 'QUOTA', until: 3601000 });
  assert.equal(circuit.until, events[0].until);
});

test('quota after partial primary progress causes the full original paragraph to be retransmitted', async () => {
  const source = '完整的长段落。'.repeat(100); const inputs = [], progress = [];
  const client = createClient({ primary: { translate: async (text, locale, options) => { assert.equal(text, source); options.onProgress({ completed: 2, total: 4 }); throw quota(); } }, backup: { translate: async (text, locale, options) => { inputs.push(text); options.onProgress({ completed: 1, total: 1 }); return { text: 'Complete backup result', provider: 'ZTAITrans' }; } } });
  const result = await client.translate(source, 'en', { onProgress: value => progress.push(value) });
  assert.equal(result.text, 'Complete backup result'); assert.deepEqual(inputs, [source]);
  assert.deepEqual(progress.map(p => p.provider), ['MyMemory', 'ZTAITrans']);
});

test('ordinary errors and rate limits do not trigger fallback', async () => {
  for (const error of [fail('REQUEST'), fail('LANGUAGE'), fail('PLACEHOLDER'), fail('RATE_LIMIT', { retryable: true }), fail('NETWORK', { retryable: true })]) {
    let backupCalls = 0; const circuit = { until: 0 };
    const client = createClient({ circuit, primary: { translate: async () => { throw error; } }, backup: { translate: async () => { backupCalls++; } } });
    await assert.rejects(client.translate('测试', 'en'), result => result === error && result.provider === 'MyMemory');
    assert.equal(backupCalls, 0); assert.equal(circuit.until, 0);
  }
});

test('cancellation before or during primary never opens a circuit or calls backup', async () => {
  let backupCalls = 0, primaryCalls = 0; const late = deferred(), circuit = { until: 0 };
  const client = createClient({ circuit, primary: { translate: async () => { primaryCalls++; return late.promise; } }, backup: { translate: async () => { backupCalls++; } } });
  const before = new AbortController(); before.abort();
  await assert.rejects(client.translate('测试', 'en', { signal: before.signal }), { code: 'ABORTED' });
  assert.equal(primaryCalls, 0);
  const during = new AbortController(); const pending = client.translate('测试', 'en', { signal: during.signal }); during.abort();
  await assert.rejects(pending, { code: 'ABORTED' }); late.reject(quota()); await tick();
  assert.equal(backupCalls, 0); assert.equal(circuit.until, 0);
});

test('backup failure retains its code and provider and never loops back to primary', async () => {
  let primaryCalls = 0, backupCalls = 0;
  const client = createClient({ primary: { translate: async () => { primaryCalls++; throw quota(); } }, backup: { translate: async () => { backupCalls++; throw fail('TRANSLATE_BUDGET_EXCEEDED', { quota: true }); } } });
  await assert.rejects(client.translate('测试', 'en'), { code: 'TRANSLATE_BUDGET_EXCEEDED', provider: 'ZTAITrans' });
  await assert.rejects(client.translate('下一条', 'en'), { code: 'TRANSLATE_BUDGET_EXCEEDED', provider: 'ZTAITrans' });
  assert.equal(primaryCalls, 1); assert.equal(backupCalls, 2);
});

test('circuit honors cooldown, caps it at 24 hours and expires back to primary', async () => {
  let time = 1000, count = 0; const circuit = { until: 0 };
  const client = createClient({ now: () => time, circuit, primary: { translate: async () => { count++; if (count === 1) throw quota({ retryAfterMs: 4 * 24 * 3600 * 1000 }); return { text: 'primary', provider: 'MyMemory' }; } }, backup: { translate: async () => ({ text: 'backup', provider: 'ZTAITrans' }) } });
  assert.equal((await client.translate('一', 'en')).provider, 'ZTAITrans');
  assert.equal(circuit.until, time + 24 * 3600 * 1000);
  time = circuit.until;
  assert.equal((await client.translate('二', 'en')).provider, 'MyMemory');
  assert.equal(count, 2);
});

test('provider-tagged retry callbacks and options reach the actual selected provider', async () => {
  const seen = [], circuit = { until: 5000 };
  const client = createClient({ now: () => 1000, circuit, primary: { translate: async () => assert.fail('circuit is open') }, backup: { translate: async (source, locale, options) => { assert.equal(options.bypassCache, true); options.onRetry({ attempt: 1 }); return { text: 'ok', provider: 'ZTAITrans', requestCount: 2 }; } } });
  assert.equal((await client.translate('测试', 'en', { bypassCache: true, onRetry: event => seen.push(event) })).provider, 'ZTAITrans');
  assert.deepEqual(seen, [{ attempt: 1, provider: 'ZTAITrans' }]);
});
