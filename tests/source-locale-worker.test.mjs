import test from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../worker/handler.js';

const endpoint = 'https://example.test/api/translation/provider';
const credentials = {
  MyMemory: { apiKey: 'fixture-key' },
  ZTAITrans: { apiKey: 'fixture-key' },
  DeepL: { apiKey: 'fixture-key', plan: 'free' },
  Azure: { apiKey: 'fixture-key' },
  Google: { apiKey: 'fixture-key' },
  Baidu: { appId: '123456', secretKey: 'fixture-key' },
  Tencent: { secretId: 'fixture-id', secretKey: 'fixture-key' },
  Alibaba: { accessKeyId: 'fixture-id', accessKeySecret: 'fixture-key' }
};
const request = (provider, sourceLocale = 'en', locale = 'zh-Hans') => new Request(endpoint, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Origin: 'https://example.test' },
  body: JSON.stringify({ provider, credentials: credentials[provider], content: 'Sign in', sourceLocale, locale })
});
const response = payload => new Response(JSON.stringify(payload));

test('English source reaches every provider with the correct Simplified Chinese target', async () => {
  for (const provider of Object.keys(credentials)) {
    const handler = createHandler({ fetchImpl: async (url, init) => {
      if (provider === 'MyMemory') {
        assert.equal(new URL(url).searchParams.get('langpair'), 'en|zh-CN');
        return response({ responseStatus: 200, responseData: { translatedText: '登录' } });
      }
      if (provider === 'ZTAITrans') {
        const body = JSON.parse(init.body);
        assert.equal(body.targetLanguage, 'Simplified Chinese');
        assert.deepEqual(body.items, [{ id: 'segment-1', content: 'Sign in' }]);
        return response({ targetLanguage: 'Simplified Chinese', model: 'fast', items: [{ id: 'segment-1', originalText: 'Sign in', translatedText: '登录' }] });
      }
      if (provider === 'DeepL') {
        const body = JSON.parse(init.body);
        assert.equal(body.source_lang, 'EN'); assert.equal(body.target_lang, 'ZH-HANS');
        return response({ translations: [{ text: '登录' }] });
      }
      if (provider === 'Azure') {
        const params = new URL(url).searchParams;
        assert.equal(params.get('from'), 'en'); assert.equal(params.get('to'), 'zh-Hans');
        return response([{ translations: [{ text: '登录', to: 'zh-Hans' }] }]);
      }
      if (provider === 'Google') {
        const body = JSON.parse(init.body);
        assert.equal(body.source, 'en'); assert.equal(body.target, 'zh-CN');
        return response({ data: { translations: [{ translatedText: '登录' }] } });
      }
      if (provider === 'Baidu') {
        const body = Object.fromEntries(new URLSearchParams(init.body));
        assert.equal(body.from, 'en'); assert.equal(body.to, 'zh');
        return response({ from: 'en', to: 'zh', trans_result: [{ src: 'Sign in', dst: '登录' }] });
      }
      if (provider === 'Tencent') {
        const body = JSON.parse(init.body);
        assert.equal(body.Source, 'en'); assert.equal(body.Target, 'zh');
        return response({ Response: { Source: 'en', Target: 'zh', TargetText: '登录' } });
      }
      const body = Object.fromEntries(new URLSearchParams(init.body));
      assert.equal(body.SourceLanguage, 'en'); assert.equal(body.TargetLanguage, 'zh');
      return response({ Code: '200', Data: { Translated: '登录' } });
    } });
    const result = await handler(request(provider));
    assert.equal(result.status, 200, provider);
    assert.equal((await result.json()).text, '登录', provider);
  }
});

test('invalid or same source and target languages are rejected before an upstream call', async () => {
  const handler = createHandler({ fetchImpl: () => assert.fail('invalid request reached upstream') });
  for (const sourceLocale of ['fr', 'zh-CN', '__proto__', null]) {
    const result = await handler(request('Google', sourceLocale));
    assert.equal(result.status, 400);
    assert.equal((await result.json()).unsupported, true);
  }
  for (const locale of ['en', 'zh-Hans']) {
    const result = await handler(request('Google', locale, locale));
    assert.equal(result.status, 400);
    assert.equal((await result.json()).unsupported, true);
  }
});

test('English source refuses a domestic response that reports Chinese source', async () => {
  for (const provider of ['Baidu', 'Tencent']) {
    const handler = createHandler({ fetchImpl: async () => response(provider === 'Baidu'
      ? { from: 'zh', to: 'zh', trans_result: [{ src: 'Sign in', dst: '登录' }] }
      : { Response: { Source: 'zh', Target: 'zh', TargetText: '登录' } }) });
    const result = await handler(request(provider));
    assert.equal(result.status, 502, provider);
    assert.equal((await result.json()).code, 'PROVIDER_RESPONSE');
  }
});

test('authenticated backup accepts English source and Simplified Chinese target', async () => {
  const token = 'fixture-developer-access-token-32-characters';
  const handler = createHandler({ fetchImpl: async (_, init) => {
    const body = JSON.parse(init.body);
    assert.equal(body.targetLanguage, 'Simplified Chinese');
    assert.deepEqual(body.items, [{ id: 'segment-1', content: 'Sign in' }]);
    return response({ targetLanguage: 'zh-CN', model: 'fast', items: [{ id: 'segment-1', originalText: 'Sign in', translatedText: '登录' }] });
  } });
  const result = await handler(new Request('https://example.test/api/translation/backup', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://example.test', 'X-LangPack-Developer-Token': token },
    body: JSON.stringify({ content: 'Sign in', sourceLocale: 'en', locale: 'zh-Hans' })
  }), { TRANSLATION_API_KEY: 'fixture-upstream-key', LANGPACK_DEVELOPER_TOKEN: token });
  assert.equal(result.status, 200);
  assert.equal((await result.json()).text, '登录');
});
