const { test } = require('node:test');
const assert = require('node:assert/strict');
const M = require('../web/mymemory.js');

function response(text, { status = 200, serviceStatus = 200, details = '', quotaFinished = false, retryAfter = null } = {}) {
  return {
    status, ok: status >= 200 && status < 300,
    headers: { get: name => name.toLowerCase() === 'retry-after' ? retryAfter : null },
    json: async () => ({ responseData: { translatedText: text }, responseStatus: serviceStatus, responseDetails: details, quotaFinished })
  };
}
const options = extra => ({ minIntervalMs: 0, retryBaseMs: 0, sleep: async () => {}, ...extra });

test('UTF-8 splitting is lossless for Chinese, emoji, whitespace and sentence boundaries', () => {
  const source = '  ' + '甲'.repeat(140) + '。' + '乙😀'.repeat(120) + '\r\n\r\n结束。  ';
  const pieces = M.splitText(source);
  assert.equal(pieces.join(''), source);
  assert.ok(pieces.every(p => M.utf8Length(p) <= 480));
  assert.ok(pieces[0].endsWith('。'));
  assert.ok(pieces.every(p => Array.from(p).every(c => c.length === 2 || !(c.charCodeAt(0) >= 0xd800 && c.charCodeAt(0) <= 0xdfff))));
  assert.equal(M.utf8Length('登录😀'), 10);
  assert.throws(() => M.splitText('x', 501), RangeError);
});

test('real endpoint, language mapping and credential-free request options are correct', async () => {
  let seen;
  const client = M.createClient(options({ fetchImpl: async (url, init) => { seen = { url: new URL(url), init }; return response('登入'); } }));
  const result = await client.translate('登录', 'zh-Hant');
  assert.equal(seen.url.origin + seen.url.pathname, 'https://api.mymemory.translated.net/get');
  assert.equal(seen.url.searchParams.get('langpair'), 'zh-CN|zh-TW');
  assert.equal(seen.url.searchParams.get('q'), '登录');
  assert.equal(seen.url.searchParams.has('de'), false);
  assert.equal(seen.init.credentials, 'omit');
  assert.equal(result.text, '登入');
  assert.equal(result.provider, 'MyMemory');
  assert.equal(result.requestCount, 1);
});

test('anonymous MyMemory requests never put private credentials into a browser GET URL', async () => {
  let seen;
  const client = M.createClient(options({ fetchImpl: async url => { seen = new URL(url); return response('Log in'); } }));
  await client.translate('login', 'en');
  assert.equal(seen.searchParams.has('key'), false);
  for (const config of [{ apiKey: 'fixture-private-memory' }, { key: 'fixture-legacy-option' }]) assert.throws(() => M.createClient(options(config)), { code: 'CONFIG', fatal: true });
});

test('all supported placeholder forms and duplicate occurrences survive marker protection', async () => {
  const client = M.createClient(options({ fetchImpl: async url => {
    const q = new URL(url).searchParams.get('q');
    assert.ok(!q.includes('{name}'));
    return response(q.replace('你好', 'Hello').replace(/ZXQPH(\d+)QXZ/g, (_, n) => 'zxqph ' + n + ' qxz'));
  } }));
  const source = '你好 {name}、{name}、{{ count }}、%s、%1$s、%%';
  assert.equal((await client.translate(source, 'en')).text, source.replace('你好', 'Hello'));
});

test('missing or duplicated placeholder markers are rejected without being cached', async () => {
  let calls = 0;
  const client = M.createClient(options({ fetchImpl: async url => { calls++; return response(new URL(url).searchParams.get('q').replace(/ZXQPH\d+QXZ/, '')); } }));
  await assert.rejects(client.translate('你好 {name}', 'en'), { code: 'PLACEHOLDER', retryable: false });
  await assert.rejects(client.translate('你好 {name}', 'en'), { code: 'PLACEHOLDER' });
  assert.equal(calls, 2);
  assert.equal(client.getUsage().cacheEntries, 0);
});

test('new unexpected placeholders from a provider are rejected before chunk caching', async () => {
  const client = M.createClient(options({ fetchImpl: async () => response('Hello {unexpected}') }));
  await assert.rejects(client.translate('你好', 'en'), { code: 'PLACEHOLDER' });
  assert.equal(client.getUsage().cacheEntries, 0);
});

test('a provider duplicating one protected marker cannot pass validation', async () => {
  const client = M.createClient(options({ fetchImpl: async url => {
    const q = new URL(url).searchParams.get('q');
    return response(q.replace(/ZXQPH\d+QXZ/, token => token + token));
  } }));
  await assert.rejects(client.translate('你好 {name}', 'en'), { code: 'PLACEHOLDER' });
  assert.equal(client.getUsage().cacheEntries, 0);
});

test('long paragraphs keep Unicode, original line endings and margins while every request stays within 500 bytes', async () => {
  const queries = [];
  const client = M.createClient(options({ fetchImpl: async url => { const q = new URL(url).searchParams.get('q'); queries.push(q); return response(q); } }));
  const source = '  ' + '中文内容😀。'.repeat(65) + '\r\n\r\n  ' + '下一行。'.repeat(50) + '  ';
  const result = await client.translate(source, 'ja');
  assert.equal(result.text, source);
  assert.ok(queries.length > 3);
  assert.ok(queries.every(q => M.utf8Length(q) <= 480));
  assert.ok(queries.every(q => !q.includes('\n') && !q.includes('\r')));
});

test('word-based target languages get a separator between adjoining translated chunks', async () => {
  const client = M.createClient(options({ fetchImpl: async () => response('A translated sentence.') }));
  const result = await client.translate('一'.repeat(300), 'en');
  assert.equal(result.text, 'A translated sentence. A translated sentence.');
});

test('transient HTTP and body-status failures retry with finite exponential delays', async () => {
  let calls = 0;
  const delays = [], events = [];
  const client = M.createClient(options({ retryBaseMs: 10, sleep: async ms => delays.push(ms), fetchImpl: async () => {
    calls++;
    return calls === 1 ? response('', { status: 503 }) : calls === 2 ? response('', { serviceStatus: 500 }) : response('Log in');
  } }));
  const result = await client.translate('登录', 'en', { onRetry: event => events.push(event) });
  assert.equal(result.text, 'Log in');
  assert.equal(result.requestCount, 3);
  assert.deepEqual(delays, [10, 20]);
  assert.deepEqual(events.map(e => e.attempt), [1, 2]);
});

test('network failures with a native error code still receive finite retries', async () => {
  let calls = 0;
  const client = M.createClient(options({ fetchImpl: async () => {
    if (++calls === 1) { const failure = new Error('connection reset'); failure.code = 'ECONNRESET'; throw failure; }
    return response('Log in');
  } }));
  assert.equal((await client.translate('登录', 'en')).text, 'Log in');
  assert.equal(calls, 2);
});

test('HTTP 200 business-level rate limiting honors Retry-After', async () => {
  let calls = 0;
  const delays = [];
  const client = M.createClient(options({ sleep: async ms => delays.push(ms), fetchImpl: async () => ++calls === 1 ? response('', { serviceStatus: 429, retryAfter: '0.05' }) : response('Log in') }));
  await client.translate('登录', 'en');
  assert.deepEqual(delays, [50]);
  assert.equal(calls, 2);
});

test('observed MyMemory daily quota response is never translated or automatically retried', async () => {
  let calls = 0;
  const warning = 'MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY. NEXT AVAILABLE IN 01 HOURS 16 MINUTES 50 SECONDS';
  const client = M.createClient(options({ fetchImpl: async () => { calls++; return response(warning, { status: 429, serviceStatus: 429, details: warning, quotaFinished: null, retryAfter: '58610' }); } }));
  await assert.rejects(client.translate('登录', 'en'), { code: 'QUOTA', quota: true, retryable: false, retryAfterMs: 58610000 });
  assert.equal(calls, 1);
  assert.equal(client.getUsage().cacheEntries, 0);
});

test('quotaFinished on an HTTP 200 response also halts without retry', async () => {
  const client = M.createClient(options({ fetchImpl: async () => response('warning', { quotaFinished: true }) }));
  await assert.rejects(client.translate('登录', 'en'), { code: 'QUOTA' });
  assert.equal(client.getUsage().requestCount, 1);
});

test('successful business translations containing quota phrases remain usable and cacheable', async t => {
  for (const text of ['Next available in 10 minutes', 'Out of quota', 'Daily quota reached', 'Quota exceeded', 'Free quota exhausted', 'Daily translation limit reached', 'You used all available free translations', 'Quota has been exhausted']) {
    await t.test(text, async () => {
      let calls = 0;
      const client = M.createClient(options({ fetchImpl: async () => { calls++; return response(text, { status: 200, serviceStatus: 200, quotaFinished: false, details: '' }); } }));
      assert.equal((await client.translate('状态提示', 'en')).text, text);
      assert.equal((await client.translate('状态提示', 'en')).cached, true);
      assert.equal(calls, 1);
      assert.equal(client.getUsage().cacheEntries, 1);
    });
  }
});

test('trusted quota flags, service diagnostics and prefixed warnings still halt on HTTP 200 without retry', async t => {
  const warning = 'MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY. NEXT AVAILABLE IN 01 HOURS 16 MINUTES 50 SECONDS';
  for (const [name, text, fields] of [
    ['boolean quota flag', 'Log in', { quotaFinished: true }],
    ['string quota flag', 'Log in', { quotaFinished: 'true' }],
    ['numeric quota flag', 'Log in', { quotaFinished: 1 }],
    ['service diagnostic', 'Log in', { details: 'Daily quota reached', quotaFinished: false }],
    ['provider warning in translated field', warning, { details: '', quotaFinished: false }],
    ['leading whitespace and case-compatible warning prefix', ' \n mymemory warning: Out of quota', { details: '', quotaFinished: false }]
  ]) await t.test(name, async () => {
    let calls = 0;
    const client = M.createClient(options({ fetchImpl: async () => { calls++; return response(text, { status: 200, serviceStatus: 200, ...fields }); } }));
    await assert.rejects(client.translate('登录', 'en'), { code: 'QUOTA', quota: true, retryable: false });
    assert.equal(calls, 1); assert.equal(client.getUsage().cacheEntries, 0);
  });
});

test('transport authentication and service 401 stop before contradictory quota flags, while observed service 403 quota remains compatible', async t => {
  const warning = 'MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY';
  for (const [name, fields, expected] of [
    ['HTTP 401', { status: 401, quotaFinished: true }, { code: 'REQUEST', fatal: true, quota: false }],
    ['HTTP 403', { status: 403, quotaFinished: true, details: warning }, { code: 'REQUEST', fatal: true, quota: false }],
    ['service 401', { status: 200, serviceStatus: 401, quotaFinished: true, details: warning }, { code: 'REQUEST', fatal: true, quota: false }],
    ['service 403 authentication', { status: 200, serviceStatus: 403, quotaFinished: false }, { code: 'REQUEST', fatal: true, quota: false }],
    ['observed service 403 quota', { status: 200, serviceStatus: 403, quotaFinished: true, details: warning }, { code: 'QUOTA', fatal: false, quota: true }]
  ]) await t.test(name, async () => {
    let calls = 0;
    const text = name === 'service 403 authentication' ? 'Access denied' : warning;
    const client = M.createClient(options({ fetchImpl: async () => { calls++; return response(text, fields); } }));
    await assert.rejects(client.translate('登录', 'en'), expected);
    assert.equal(calls, 1);
  });
});

test('ordinary rate limits with quota-like candidate text keep bounded retries rather than becoming exhausted quota', async () => {
  let calls = 0;
  const delays = [];
  const client = M.createClient(options({ maxRetries: 1, sleep: async ms => delays.push(ms), fetchImpl: async () => { calls++; return response('Next available in 10 minutes', { status: 429, serviceStatus: 429, details: 'Too many requests', retryAfter: '0.05' }); } }));
  await assert.rejects(client.translate('登录', 'en'), { code: 'RATE_LIMIT', retryable: true, quota: false });
  assert.equal(calls, 2); assert.deepEqual(delays, [50]); assert.equal(client.getUsage().cacheEntries, 0);
});

test('unrelated provider warnings and malformed payloads do not become quota or cached translations', async t => {
  const cases = [
    ['ordinary provider warning', () => response('MYMEMORY WARNING: PLEASE SELECT TWO DISTINCT LANGUAGES'), 'RESPONSE'],
    ['unprefixed failure candidate', () => response('Out of quota', { status: 400, serviceStatus: 400 }), 'REQUEST'],
    ['null payload', () => ({ ok: true, status: 200, json: async () => null }), 'RESPONSE'],
    ['invalid quota metadata type', () => ({ ok: true, status: 200, json: async () => ({ responseStatus: 200, quotaFinished: { value: true }, responseDetails: { message: 'Out of quota' }, responseData: { translatedText: '' } }) }), 'EMPTY']
  ];
  for (const [name, fetchImpl, code] of cases) await t.test(name, async () => {
    const client = M.createClient(options({ maxRetries: 0, fetchImpl }));
    await assert.rejects(client.translate('登录', 'en'), { code, quota: false });
    assert.equal(client.getUsage().requestCount, 1); assert.equal(client.getUsage().cacheEntries, 0);
  });
});

test('long Retry-After is surfaced rather than silently shortened or waited on', async () => {
  let calls = 0;
  const client = M.createClient(options({ fetchImpl: async () => { calls++; return response('', { status: 429, retryAfter: '90' }); } }));
  await assert.rejects(client.translate('登录', 'en'), { code: 'RATE_LIMIT', retryable: true, retryAfterMs: 90000 });
  assert.equal(calls, 1);
});

test('authentication/invalid-request errors are not retried', async () => {
  const client = M.createClient(options({ fetchImpl: async () => response('', { serviceStatus: 403 }) }));
  await assert.rejects(client.translate('登录', 'en'), { code: 'REQUEST', retryable: false });
  assert.equal(client.getUsage().requestCount, 1);
});

test('empty results and broken JSON never become successful translations', async () => {
  const empty = M.createClient(options({ maxRetries: 1, fetchImpl: async () => response('   ') }));
  await assert.rejects(empty.translate('登录', 'en'), { code: 'EMPTY' });
  assert.equal(empty.getUsage().requestCount, 2);
  const broken = M.createClient(options({ maxRetries: 0, fetchImpl: async () => ({ ok: true, status: 200, json: async () => { throw new SyntaxError('bad json'); } }) }));
  await assert.rejects(broken.translate('登录', 'en'), { code: 'RESPONSE' });
});

test('HTML entities are decoded once without interpreting HTML as markup', async () => {
  const client = M.createClient(options({ fetchImpl: async () => response('Hello &amp; &quot;test&quot; &#39;x&#39; &#x1F600; &lt;b&gt;') }));
  assert.equal((await client.translate('测试', 'en')).text, 'Hello & "test" \'x\' 😀 <b>');
});

test('completed long-paragraph chunks survive a later failure and are reused on manual retry', async () => {
  let calls = 0;
  const client = M.createClient(options({ maxRetries: 0, fetchImpl: async url => { calls++; return calls === 2 ? response('', { status: 503 }) : response(new URL(url).searchParams.get('q')); } }));
  const source = '第一段。'.repeat(50);
  await assert.rejects(client.translate(source, 'ja'), { code: 'SERVICE' });
  const second = await client.translate(source, 'ja');
  assert.equal(second.text, source);
  assert.equal(second.requestCount, 1);
  assert.equal(calls, 3);
  assert.equal((await client.translate(source, 'ja')).cached, true);
  assert.equal((await client.translate(source, 'ja', { bypassCache: true })).requestCount, 2);
});

test('requests are serialized even when callers translate concurrently', async () => {
  let active = 0, maxActive = 0;
  const client = M.createClient(options({ fetchImpl: async () => { active++; maxActive = Math.max(maxActive, active); await new Promise(resolve => setTimeout(resolve, 3)); active--; return response('translated'); } }));
  await Promise.all([client.translate('第一条', 'en'), client.translate('第二条', 'fr')]);
  assert.equal(maxActive, 1);
});

test('timeouts abort fetch and remain bounded by maxRetries', async () => {
  let aborts = 0;
  const client = M.createClient(options({ timeoutMs: 3, maxRetries: 1, fetchImpl: async (_, init) => { init.signal.addEventListener('abort', () => aborts++); return new Promise(() => {}); } }));
  await assert.rejects(client.translate('登录', 'en'), { code: 'TIMEOUT' });
  assert.equal(aborts, 2);
  assert.equal(client.getUsage().requestCount, 2);
});

test('external cancellation interrupts active fetch immediately', async () => {
  const controller = new AbortController();
  const client = M.createClient(options({ fetchImpl: async () => { controller.abort(); return new Promise(() => {}); } }));
  await assert.rejects(client.translate('登录', 'en', { signal: controller.signal }), { code: 'ABORTED', name: 'AbortError' });
  assert.equal(client.getUsage().requestCount, 1);
});

test('external cancellation during backoff stops additional attempts', async () => {
  const controller = new AbortController();
  const client = M.createClient(options({ fetchImpl: async () => response('', { status: 503 }) }));
  await assert.rejects(client.translate('登录', 'en', { signal: controller.signal, onRetry: () => controller.abort() }), { code: 'ABORTED' });
  assert.equal(client.getUsage().requestCount, 1);
});

test('cancellation interrupts an already-active throttle wait without issuing another request', async () => {
  const controller = new AbortController();
  let calls = 0;
  const client = M.createClient({ minIntervalMs: 10000, fetchImpl: async () => { calls++; return response('translated'); } });
  await client.translate('第一条', 'en');
  const pending = client.translate('第二条', 'en', { signal: controller.signal });
  setTimeout(() => controller.abort(), 3);
  await assert.rejects(pending, { code: 'ABORTED' });
  assert.equal(calls, 1);
});

test('unsupported languages, blanks and invalid contact email do not send requests', async () => {
  let calls = 0;
  const client = M.createClient(options({ fetchImpl: async () => { calls++; return response('x'); } }));
  await assert.rejects(client.translate('登录', 'xx'), { code: 'LANGUAGE' });
  assert.equal((await client.translate('  \n ', 'en')).text, '  \n ');
  assert.equal((await client.translate('  %s\n%%{name}', 'en')).text, '  %s\n%%{name}');
  assert.equal(calls, 0);
  assert.throws(() => M.createClient({ email: 'invalid' }), { code: 'EMAIL' });
});

test('cache is bounded and bypassCache performs a fresh request', async () => {
  let calls = 0;
  const client = M.createClient(options({ maxCacheEntries: 2, fetchImpl: async url => { calls++; return response(new URL(url).searchParams.get('q')); } }));
  for (const source of ['第一条', '第二条', '第三条']) await client.translate(source, 'en');
  assert.equal(client.getUsage().cacheEntries, 2);
  await client.translate('第一条', 'en');
  assert.equal(calls, 4);
  assert.equal((await client.translate('第一条', 'en')).cached, true);
  assert.equal((await client.translate('第一条', 'en', { bypassCache: true })).cached, false);
});

test('every supported primary language uses its exact adapter code; fixed source and backup-only variants never request MyMemory', async () => {
  const Languages = require('../web/languages.js');
  const calls = [];
  const client = M.createClient(options({ fetchImpl: async url => { calls.push(new URL(url).searchParams.get('langpair')); return response('translated'); } }));
  for (const [code, target] of Object.entries(Languages.primaryMap)) {
    await client.translate('登录', code);
    assert.equal(calls.at(-1), 'zh-CN|' + target);
  }
  assert.equal(calls.length, 31);
  for (const code of ['zh-Hans', 'pt-BR', 'fil', 'nb', 'xx', 'toString']) await assert.rejects(client.translate('登录', code), { code: 'LANGUAGE' });
  assert.equal(calls.length, 31);
});

test('expanded word-based target scripts keep a separator at chunk boundaries including combining marks', async () => {
  const source = '文'.repeat(200);
  for (const [locale, text] of [['pt-PT', 'palavra'], ['ru', 'слово'], ['ar', 'كلمة'], ['hi', 'हिन्दी'], ['si', 'සිංහල']]) {
    const client = M.createClient(options({ fetchImpl: async () => response(text) }));
    assert.equal((await client.translate(source, locale)).text, text + ' ' + text);
  }
  for (const [locale, text] of [['zh-Hant', '譯文'], ['ja', '翻訳'], ['th', 'คำ']]) {
    const client = M.createClient(options({ fetchImpl: async () => response(text) }));
    assert.equal((await client.translate(source, locale)).text, text + text);
  }
});

test('English source uses en to Simplified Chinese direction and keeps source directions separate in cache', async () => {
  const pairs = [];
  const client = M.createClient(options({ fetchImpl: async url => {
    pairs.push(new URL(url).searchParams.get('langpair'));
    return response('translated');
  } }));
  await client.translate('Welcome', 'zh-Hans', { sourceLocale: 'en' });
  await client.translate('Welcome', 'ja', { sourceLocale: 'en' });
  await client.translate('Welcome', 'ja');
  assert.deepEqual(pairs, ['en|zh-CN', 'en|ja', 'zh-CN|ja']);
  await assert.rejects(client.translate('Welcome', 'en', { sourceLocale: 'en' }), { code: 'LANGUAGE' });
});
