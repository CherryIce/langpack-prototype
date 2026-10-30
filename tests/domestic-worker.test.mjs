import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createHandler } from '../worker/handler.js';
import providers from '../web/providers.js';

// All fetches below are injected fixtures. No provider network is reachable.
const credentials = {
  Baidu: { appId: '2015063000000001', secretKey: 'fixture-baidu-secret' },
  Tencent: { secretId: 'fixture-tencent-id', secretKey: 'fixture-tencent-secret', region: 'ap-guangzhou' },
  Alibaba: { accessKeyId: 'fixture-alibaba-id', accessKeySecret: 'fixture-alibaba-secret' }
};
const request = (provider, content = '登录', locale = 'en', value = credentials[provider]) => new Request('https://example.test/api/translation/provider', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: 'https://example.test' }, body: JSON.stringify({ provider, content, locale, credentials: value }) });
const response = (value, status = 200) => new Response(JSON.stringify(value), { status });
const sha256 = text => createHash('sha256').update(text).digest('hex');
const hmac = (key, text) => createHmac('sha256', key).update(text).digest();
const encode = value => encodeURIComponent(value).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
const sorted = value => Object.keys(value).sort().map(key => encode(key) + '=' + encode(value[key])).join('&');
const baiduTargets = { 'zh-Hant':'cht',en:'en',ms:'may',th:'th',fr:'fra',es:'spa',ar:'ara',fil:'fil',vi:'vie',ru:'ru',tr:'tr',id:'id',ja:'jp',ko:'kor',de:'de',hi:'hi',hu:'hu',it:'it',ro:'rom',sv:'swe',bg:'bul',pl:'pl',da:'dan',fi:'fin',nl:'nl',cs:'cs',sk:'sk',uk:'ukr',el:'el',nb:'nob',hr:'hrv',si:'sin' };
const tencentTargets = { 'zh-Hant':'zh-TW',en:'en',ms:'ms',th:'th',fr:'fr',es:'es',ar:'ar',vi:'vi',ru:'ru',tr:'tr',id:'id',ja:'ja',ko:'ko',de:'de',it:'it' };
const locales = ['zh-Hant','en','pt-BR','pt-PT','ms','th','fr','es','ar','fil','vi','ru','tr','id','ja','ko','de','hi','hu','it','ro','sv','bg','pl','da','fi','nl','cs','sk','uk','el','nb','hr','si'];
function success(provider, content, target, text = 'Translated') {
  if (provider === 'Baidu') return { from: 'zh', to: target, trans_result: [{ src: content, dst: text }] };
  if (provider === 'Tencent') return { Response: { Source: 'zh', Target: target, TargetText: text, RequestId: 'fixture' } };
  return { Code: '200', Message: 'success', Data: { Translated: text } };
}

test('Baidu MD5 matches the official golden vector and independent UTF-8 digest vectors', async () => {
  const source = await readFile(new URL('../worker/handler.js', import.meta.url), 'utf8');
  const { baiduMD5 } = await import('data:text/javascript;base64,' + Buffer.from(source + '\nexport { baiduMD5 };').toString('base64'));
  assert.equal(baiduMD5('2015063000000001apple143566028812345678'), 'f89f9594663708c1605f3d736d01d2d4');
  for (const value of ['', 'a', 'abc', '你好😀\r\n{value}', '汉'.repeat(1000)]) assert.equal(baiduMD5(value), createHash('md5').update(value).digest('hex'));
});

test('Baidu signs original unencoded UTF-8 and sends only fixed POST form fields', async () => {
  for (const content of ['登录', "你好 😀 & = + !'()*~", 'line one\nline two']) {
    const handle = createHandler({ fetchImpl: async (url, init) => {
      assert.equal(url, 'https://fanyi-api.baidu.com/api/trans/vip/translate');
      assert.equal(init.method, 'POST'); assert.equal(init.redirect, 'manual');
      assert.equal(init.headers['Content-Type'], 'application/x-www-form-urlencoded');
      const form = Object.fromEntries(new URLSearchParams(init.body));
      assert.deepEqual(Object.keys(form).sort(), ['appid','from','q','salt','sign','to']);
      assert.equal(form.q, content); assert.equal(form.from, 'zh'); assert.equal(form.to, 'en');
      assert.equal(form.sign, createHash('md5').update(credentials.Baidu.appId + content + form.salt + credentials.Baidu.secretKey).digest('hex'));
      assert.ok(!init.body.includes(credentials.Baidu.secretKey));
      return response(success('Baidu', content, 'en'));
    } });
    assert.equal((await handle(request('Baidu', content))).status, 200);
  }
});

test('Tencent TC3 is independently recomputed from exact body and signed action headers', async () => {
  const handle = createHandler({ fetchImpl: async (url, init) => {
    assert.equal(url, 'https://tmt.tencentcloudapi.com/'); assert.equal(init.redirect, 'manual');
    const headers = init.headers, data = JSON.parse(init.body), timestamp = headers['X-TC-Timestamp'];
    assert.deepEqual(data, { SourceText: '登录', Source: 'zh', Target: 'ja', ProjectId: 0 });
    assert.equal(headers['X-TC-Version'], '2018-03-21'); assert.equal(headers['X-TC-Region'], 'ap-guangzhou');
    const date = new Date(Number(timestamp) * 1000).toISOString().slice(0, 10), scope = date + '/tmt/tc3_request';
    const canonical = ['POST','/','', 'content-type:application/json; charset=utf-8\nhost:tmt.tencentcloudapi.com\nx-tc-action:texttranslate\n', 'content-type;host;x-tc-action', sha256(init.body)].join('\n');
    const signing = hmac(hmac(hmac('TC3' + credentials.Tencent.secretKey, date), 'tmt'), 'tc3_request');
    const signature = hmac(signing, ['TC3-HMAC-SHA256',timestamp,scope,sha256(canonical)].join('\n')).toString('hex');
    assert.equal(headers.Authorization, 'TC3-HMAC-SHA256 Credential=' + credentials.Tencent.secretId + '/' + scope + ', SignedHeaders=content-type;host;x-tc-action, Signature=' + signature);
    assert.ok(!JSON.stringify(init).includes(credentials.Tencent.secretKey));
    return response(success('Tencent', '登录', 'ja'));
  } });
  assert.equal((await handle(request('Tencent', '登录', 'ja'))).status, 200);
});

test('Alibaba RPC signature includes all form fields once with RFC3986 escaping and unique nonce', async () => {
  const nonces = new Set(), content = "你好 😀 & = + !'()*~\nnext";
  const handle = createHandler({ fetchImpl: async (url, init) => {
    assert.equal(url, 'https://mt.cn-hangzhou.aliyuncs.com/'); assert.equal(init.redirect, 'manual');
    assert.equal(init.headers['Content-Type'], 'application/x-www-form-urlencoded');
    const params = new URLSearchParams(init.body), data = Object.fromEntries(params);
    assert.equal([...params].length, Object.keys(data).length);
    assert.equal(data.Action, 'TranslateGeneral'); assert.equal(data.Version, '2018-10-12');
    assert.equal(data.SourceText, content); assert.equal(data.SourceLanguage, 'zh'); assert.equal(data.TargetLanguage, 'fil');
    assert.equal(data.FormatType, 'text'); assert.equal(data.Scene, 'general'); assert.equal(data.RegionId, 'cn-hangzhou');
    assert.equal(data.SignatureMethod, 'HMAC-SHA1'); assert.equal(data.SignatureVersion, '1.0');
    assert.match(data.Timestamp, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    assert.ok(!nonces.has(data.SignatureNonce)); nonces.add(data.SignatureNonce);
    const signature = data.Signature; delete data.Signature;
    const expected = createHmac('sha1', credentials.Alibaba.accessKeySecret + '&').update('POST&%2F&' + encode(sorted(data))).digest('base64');
    assert.equal(signature, expected); assert.ok(!init.body.includes(credentials.Alibaba.accessKeySecret));
    return response(success('Alibaba', content, 'fil'));
  } });
  for (let i = 0; i < 2; i++) assert.equal((await handle(request('Alibaba', content, 'fil'))).status, 200);
});

test('all domestic target mappings agree with clients and unsupported variants never call upstream', async () => {
  for (const provider of Object.keys(credentials)) {
    let calls = 0;
    for (const locale of locales) {
      const target = provider === 'Baidu' ? baiduTargets[locale] : provider === 'Tencent' ? tencentTargets[locale] : ['pt-BR','pt-PT','nb','hr','uk'].includes(locale) ? undefined : locale === 'zh-Hant' ? 'zh-tw' : locale;
      assert.equal(providers.supports(provider, locale), !!target, provider + ' ' + locale);
      const handle = createHandler({ fetchImpl: async (_, init) => {
        calls++; const data = provider === 'Tencent' ? JSON.parse(init.body) : Object.fromEntries(new URLSearchParams(init.body));
        assert.equal(provider === 'Baidu' ? data.to : provider === 'Tencent' ? data.Target : data.TargetLanguage, target);
        return response(success(provider, '登录', target));
      } });
      const result = await handle(request(provider, '登录', locale)); assert.equal(result.status, target ? 200 : 400);
      if (!target) assert.equal((await result.json()).unsupported, true);
    }
    assert.equal(calls, { Baidu:32,Tencent:15,Alibaba:29 }[provider]);
  }
});

test('domestic credentials, unsupported injection fields and source limits fail before signing or fetching', async () => {
  const handle = createHandler({ fetchImpl: () => assert.fail('invalid request reached upstream') });
  for (const provider of Object.keys(credentials)) {
    for (const invalid of [{}, { apiKey: 'some-other-key' }, { ...credentials[provider], endpoint: 'https://evil.test' }]) assert.equal((await handle(request(provider, '登录', 'en', invalid))).status, 400);
    const limit = { Baidu:1000,Tencent:2000,Alibaba:5000 }[provider];
    assert.equal((await handle(request(provider, '😀'.repeat(limit + 1)))).status, 413);
  }
  assert.equal((await handle(request('Baidu', '登录', 'en', { appId:'123\r\nX: y',secretKey:'secret' }))).status, 400);
  assert.equal((await handle(request('Tencent', '登录', 'en', { ...credentials.Tencent, region:'ap-guangzhou\r\nX: y' }))).status, 400);
});

test('business error codes distinguish resource exhaustion, auth, unavailable service, languages and rate limits', async () => {
  const cases = [
    ['Baidu','54004',402,'PROVIDER_QUOTA'], ['Baidu','58001',400,'PROVIDER_UNSUPPORTED'],
    ['Baidu','54001',401,'PROVIDER_AUTH'], ['Baidu','58003',401,'PROVIDER_AUTH'], ['Baidu','58002',400,'PROVIDER_CONFIG'],
    ['Baidu','54003',429,'PROVIDER_RATE_LIMIT'], ['Baidu','54005',429,'PROVIDER_RATE_LIMIT'], ['Baidu','52002',502,'PROVIDER_SERVICE'],
    ['Tencent','FailedOperation.NoFreeAmount',402,'PROVIDER_QUOTA'], ['Tencent','AuthFailure.SignatureFailure',401,'PROVIDER_AUTH'],
    ['Tencent','UnauthorizedOperation',401,'PROVIDER_AUTH'], ['Tencent','RequestLimitExceeded',429,'PROVIDER_RATE_LIMIT'],
    ['Tencent','FailedOperation.ServiceIsolate',400,'PROVIDER_CONFIG'], ['Tencent','InternalError',502,'PROVIDER_SERVICE'],
    ['Tencent','ActionOffline',400,'PROVIDER_CONFIG'], ['Tencent','FailedOperation.UserNotRegistered',400,'PROVIDER_CONFIG'], ['Tencent','FailedOperation.StopUsing',400,'PROVIDER_CONFIG'],
    ['Tencent','IpInBlacklist',401,'PROVIDER_AUTH'], ['Tencent','IpNotInWhitelist',401,'PROVIDER_AUTH'], ['Tencent','FailedOperation.ErrorUserArea',400,'PROVIDER_CONFIG'], ['Tencent','ServiceUnavailable',502,'PROVIDER_SERVICE'],
    ['Tencent','UnsupportedOperation.UnSupportedTargetLanguage',400,'PROVIDER_UNSUPPORTED'], ['Tencent','UnsupportedOperation.UnsupportedSourceLanguage',400,'PROVIDER_UNSUPPORTED'],
    ['Alibaba','10005',400,'PROVIDER_UNSUPPORTED'], ['Alibaba','10009',401,'PROVIDER_AUTH'], ['Alibaba','10013',400,'PROVIDER_CONFIG'],
    ['Alibaba','SignatureDoesNotMatch',401,'PROVIDER_AUTH'], ['Alibaba','Throttling.User',429,'PROVIDER_RATE_LIMIT'], ['Alibaba','10002',502,'PROVIDER_SERVICE']
  ];
  for (const [provider, code, status, normalized] of cases) {
    const payload = provider === 'Baidu' ? {error_code:code,error_msg:credentials.Baidu.secretKey} : provider === 'Tencent' ? {Response:{Error:{Code:code,Message:credentials.Tencent.secretKey}}} : {Code:code,Message:credentials.Alibaba.accessKeySecret};
    const handle = createHandler({ fetchImpl: async () => response(payload) });
    const r = await handle(request(provider)); assert.equal(r.status, status, provider + ' ' + code);
    const data = await r.json(); assert.equal(data.code, normalized); assert.equal(!!data.quota, status === 402); assert.equal(!!data.fatal, ['PROVIDER_AUTH','PROVIDER_CONFIG'].includes(normalized));
    for (const value of Object.values(credentials[provider])) assert.ok(!JSON.stringify(data).includes(value));
  }
});

test('redirects, mismatched result identity, partial rows and reflected credential fields are never saved', async () => {
  for (const provider of Object.keys(credentials)) {
    const invalids = Object.entries(credentials[provider]).filter(([name]) => name !== 'region').map(([, value]) => success(provider, '登录', 'en', value));
    if (provider === 'Baidu') invalids.push(success(provider, 'unrelated', 'en'), success(provider,'登录','jp'), {from:'zh',to:'en',trans_result:[{src:'登录',dst:'okay'}, {src:'extra',dst:''}]});
    if (provider === 'Tencent') invalids.push(success(provider, '登录', 'ja'), {Response:{TargetText:'missing identity'}});
    for (const invalid of invalids) {
      const handle = createHandler({ fetchImpl: async () => response(invalid) });
      const r = await handle(request(provider)); assert.equal(r.status, 502); assert.equal((await r.json()).code, 'PROVIDER_RESPONSE');
    }
    let calls = 0;
    const redirect = createHandler({ fetchImpl: async (_, init) => { calls++; assert.equal(init.redirect, 'manual'); return new Response(null,{status:302,headers:{Location:'https://evil.test'}}); } });
    assert.equal((await redirect(request(provider))).status, 400); assert.equal(calls, 1);
  }
});
