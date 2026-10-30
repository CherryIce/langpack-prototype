// Server-only translation proxy. The API key is supplied by the hosted runtime.
const UPSTREAM = 'https://aitrans-iqwek72342.futureinvest.id/api/translate/text';
const MAX_REQUEST_BYTES = 256 * 1024;
const MAX_RESPONSE_BYTES = 1024 * 1024;
const MAX_CONTENT_CHARACTERS = 50000;
// Resource/export codes align with MediaServiceClient. The chosen source is excluded per request.
const TARGETS = Object.freeze({
  'zh-Hans': 'Simplified Chinese', 'zh-Hant': 'Traditional Chinese', en: 'English',
  'pt-BR': 'Portuguese (Brazil)', 'pt-PT': 'Portuguese (Portugal)',
  ms: 'Malay', th: 'Thai', fr: 'French', es: 'Spanish', ar: 'Arabic',
  fil: 'Filipino', vi: 'Vietnamese', ru: 'Russian', tr: 'Turkish',
  id: 'Indonesian', ja: 'Japanese', ko: 'Korean', de: 'German', hi: 'Hindi',
  hu: 'Hungarian', it: 'Italian', ro: 'Romanian', sv: 'Swedish', bg: 'Bulgarian',
  pl: 'Polish', da: 'Danish', fi: 'Finnish', nl: 'Dutch', cs: 'Czech',
  sk: 'Slovak', uk: 'Ukrainian', el: 'Greek', nb: 'Norwegian Bokmål',
  hr: 'Croatian', si: 'Sinhala'
});
const TARGET_ALIASES = Object.freeze({
  'zh-Hans': ['simplified chinese', 'zh-hans', 'zh-cn', 'zh_cn', '简体中文', '簡體中文'],
  en: ['english', 'en', 'en-us', 'en_us', 'en-gb', 'en_gb', '英语'],
  ja: ['japanese', 'ja', 'ja-jp', 'ja_jp', '日语'],
  ko: ['korean', 'ko', 'ko-kr', 'ko_kr', '韩语'],
  fr: ['french', 'fr', 'fr-fr', 'fr_fr', '法语'],
  de: ['german', 'de', 'de-de', 'de_de', '德语'],
  es: ['spanish', 'es', 'es-es', 'es_es', '西班牙语'],
  'zh-Hant': ['traditional chinese', 'zh-hant', 'zh-tw', 'zh_tw', '繁体中文', '繁體中文'],
  'pt-BR': ['portuguese (brazil)', 'brazilian portuguese', 'pt-br', 'pt_br', '葡萄牙语（巴西）'],
  'pt-PT': ['portuguese (portugal)', 'european portuguese', 'pt-pt', 'pt_pt', '葡萄牙语（葡萄牙）'],
  ms: ['malay', 'ms', 'ms-my', 'ms_my', '马来语'],
  th: ['thai', 'th', 'th-th', 'th_th', '泰语'],
  ar: ['arabic', 'ar', 'ar-sa', 'ar_sa', '阿拉伯语'],
  fil: ['filipino', 'fil', 'fil-ph', 'fil_ph', '菲律宾语'],
  vi: ['vietnamese', 'vi', 'vi-vn', 'vi_vn', '越南语'],
  ru: ['russian', 'ru', 'ru-ru', 'ru_ru', '俄语'],
  tr: ['turkish', 'tr', 'tr-tr', 'tr_tr', '土耳其语'],
  id: ['indonesian', 'id', 'id-id', 'id_id', '印度尼西亚语'],
  hi: ['hindi', 'hi', 'hi-in', 'hi_in', '印地语'],
  hu: ['hungarian', 'hu', 'hu-hu', 'hu_hu', '匈牙利语'],
  it: ['italian', 'it', 'it-it', 'it_it', '意大利语'],
  ro: ['romanian', 'ro', 'ro-ro', 'ro_ro', '罗马尼亚语'],
  sv: ['swedish', 'sv', 'sv-se', 'sv_se', '瑞典语'],
  bg: ['bulgarian', 'bg', 'bg-bg', 'bg_bg', '保加利亚语'],
  pl: ['polish', 'pl', 'pl-pl', 'pl_pl', '波兰语'],
  da: ['danish', 'da', 'da-dk', 'da_dk', '丹麦语'],
  fi: ['finnish', 'fi', 'fi-fi', 'fi_fi', '芬兰语'],
  nl: ['dutch', 'nl', 'nl-nl', 'nl_nl', '荷兰语'],
  cs: ['czech', 'cs', 'cs-cz', 'cs_cz', '捷克语'],
  sk: ['slovak', 'sk', 'sk-sk', 'sk_sk', '斯洛伐克语'],
  uk: ['ukrainian', 'uk', 'uk-ua', 'uk_ua', '乌克兰语'],
  el: ['greek', 'el', 'el-gr', 'el_gr', '希腊语'],
  nb: ['norwegian bokmål', 'norwegian bokmal', 'bokmål', 'nb', 'nb-no', 'nb_no', '书面挪威语'],
  hr: ['croatian', 'hr', 'hr-hr', 'hr_hr', '克罗地亚语'],
  si: ['sinhala', 'sinhalese', 'si', 'si-lk', 'si_lk', '僧伽罗语']
});

function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...extraHeaders } });
}
function problem(status, code, message, extra = {}) {
  return json({ code, message, provider: 'ZTAITrans', retryable: false, ...extra }, status);
}
function fault(code) { return Object.assign(new Error(code), { code }); }
function abortRace(promise, signal) {
  if (signal.aborted) return Promise.reject(fault('ABORTED'));
  return new Promise((resolve, reject) => {
    const onAbort = () => { signal.removeEventListener('abort', onAbort); reject(fault('ABORTED')); };
    signal.addEventListener('abort', onAbort, { once: true });
    Promise.resolve(promise).then(value => { signal.removeEventListener('abort', onAbort); resolve(value); }, error => { signal.removeEventListener('abort', onAbort); reject(error); });
  });
}
async function readBounded(source, maximum, signal) {
  const contentLength = Number(source.headers.get('Content-Length'));
  if (Number.isFinite(contentLength) && contentLength > maximum) throw fault('TOO_LARGE');
  if (!source.body) return '';
  const reader = source.body.getReader();
  const parts = []; let length = 0;
  const onAbort = () => { reader.cancel().catch(() => {}); };
  signal?.addEventListener('abort', onAbort, { once: true });
  try {
    for (;;) {
      if (signal?.aborted) throw fault('ABORTED');
      const result = await reader.read();
      if (signal?.aborted) throw fault('ABORTED');
      if (result.done) break;
      length += result.value.byteLength;
      if (length > maximum) { reader.cancel().catch(() => {}); throw fault('TOO_LARGE'); }
      parts.push(result.value);
    }
    const bytes = new Uint8Array(length); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } finally { signal?.removeEventListener('abort', onAbort); reader.releaseLock(); }
}
function cooldown(response) {
  const raw = response.headers.get('Retry-After');
  if (!raw) return 0;
  const seconds = Number(raw);
  const value = Number.isFinite(seconds) ? seconds * 1000 : Date.parse(raw) - Date.now();
  return Number.isFinite(value) ? Math.min(86400000, Math.max(0, value)) : 0;
}
function upstreamFailure(response, payload) {
  const code = typeof payload?.code === 'string' ? payload.code : '';
  if (code === 'TRANSLATE_DISABLED') return problem(503, 'BACKUP_DISABLED', '备用翻译服务当前已关闭，请联系服务提供方。');
  if (code === 'TRANSLATE_NOT_CONFIGURED') return problem(503, 'BACKUP_NOT_CONFIGURED', '备用服务尚未配置翻译模型，请联系服务提供方。');
  if (response.status === 401 || response.status === 403 || code === 'UNAUTHORIZED') return problem(401, 'BACKUP_AUTH', '备用翻译服务的授权不可用，请检查服务端配置。');
  if (response.status === 402 || code === 'TRANSLATE_BUDGET_EXCEEDED') return problem(402, 'BACKUP_BUDGET', '备用翻译服务的授权预算已用完，任务已停止。', { quota: true });
  if (response.status === 429) return problem(429, 'BACKUP_RATE_LIMIT', '备用翻译服务请求过于频繁，请稍后重试。', { retryable: true, retryAfterMs: cooldown(response) });
  if (response.status >= 500 || code === 'TRANSLATE_ALL_MODELS_FAILED') return problem(502, 'BACKUP_SERVICE', '备用翻译服务暂时无法完成请求，请稍后重试。', { retryable: true });
  if (!response.ok || code) return problem(400, 'BACKUP_REQUEST', '备用翻译服务拒绝了这条请求，请检查原文和目标语言。');
  return null;
}
function validOutput(payload, source, locale, secret) {
  // The deployed service may renumber a single item as "1". That compatibility
  // branch requires an exact source echo so it cannot accept an unrelated row.
  if (!payload || !Array.isArray(payload.items) || payload.items.length !== 1) return null;
  const item = payload.items[0];
  if (!item || !['segment-1', '1'].includes(item.id) || typeof item.translatedText !== 'string' || !item.translatedText.trim()) return null;
  if (item.id === '1' && item.originalText !== source) return null;
  if (item.originalText !== undefined && item.originalText !== source) return null;
  if (payload.originalText !== undefined && payload.originalText !== source) return null;
  if (payload.targetLanguage !== undefined && (typeof payload.targetLanguage !== 'string' || !TARGET_ALIASES[locale].includes(payload.targetLanguage.trim().toLowerCase()))) return null;
  if (payload.model !== undefined && (typeof payload.model !== 'string' || payload.model.toLowerCase() !== 'fast')) return null;
  if (/^(?:\s*[.…]\s*)+$/u.test(item.translatedText) || item.translatedText.trim() === '<译文>') return null;
  if (secret && item.translatedText.includes(secret)) return null;
  return item.translatedText;
}

const PROVIDER_LOCALES = Object.freeze({
  MyMemory: Object.freeze(Object.fromEntries(Object.keys(TARGETS).filter(code => !['pt-BR', 'fil', 'nb'].includes(code)).map(code => [code, ({ 'zh-Hans': 'zh-CN', 'zh-Hant': 'zh-TW', si: 'si-LK' })[code] || code]))),
  Azure: Object.freeze(Object.fromEntries(Object.keys(TARGETS).map(code => [code, ({ 'pt-BR': 'pt', 'pt-PT': 'pt-pt' })[code] || code]))),
  Google: Object.freeze(Object.fromEntries(Object.keys(TARGETS).filter(code => code !== 'nb').map(code => [code, ({ 'zh-Hans': 'zh-CN', 'zh-Hant': 'zh-TW' })[code] || code]))),
  DeepL: Object.freeze(Object.fromEntries(Object.keys(TARGETS).filter(code => !['fil', 'si'].includes(code)).map(code => [code, ({ 'zh-Hans': 'ZH-HANS', 'zh-Hant': 'ZH-HANT', en: 'EN-US', 'pt-BR': 'PT-BR', 'pt-PT': 'PT-PT' })[code] || code.toUpperCase()]))),
  Alibaba: Object.freeze(Object.fromEntries(Object.keys(TARGETS).filter(code => !['pt-BR', 'pt-PT', 'nb', 'hr', 'uk'].includes(code)).map(code => [code, code === 'zh-Hans' ? 'zh' : code === 'zh-Hant' ? 'zh-tw' : code]))),
  Baidu: Object.freeze({ 'zh-Hans': 'zh', 'zh-Hant': 'cht', en: 'en', ms: 'may', th: 'th', fr: 'fra', es: 'spa', ar: 'ara', fil: 'fil', vi: 'vie', ru: 'ru', tr: 'tr', id: 'id', ja: 'jp', ko: 'kor', de: 'de', hi: 'hi', hu: 'hu', it: 'it', ro: 'rom', sv: 'swe', bg: 'bul', pl: 'pl', da: 'dan', fi: 'fin', nl: 'nl', cs: 'cs', sk: 'sk', uk: 'ukr', el: 'el', nb: 'nob', hr: 'hrv', si: 'sin' }),
  Tencent: Object.freeze({ 'zh-Hans': 'zh', 'zh-Hant': 'zh-TW', en: 'en', ms: 'ms', th: 'th', fr: 'fr', es: 'es', ar: 'ar', vi: 'vi', ru: 'ru', tr: 'tr', id: 'id', ja: 'ja', ko: 'ko', de: 'de', it: 'it' })
});
const PROVIDER_NAMES = ['MyMemory', 'ZTAITrans', 'DeepL', 'Azure', 'Google', 'Baidu', 'Tencent', 'Alibaba'];
const plainObject = value => value && typeof value === 'object' && !Array.isArray(value);
const safeCredential = value => typeof value === 'string' && /^[\x21-\x7e]{1,2048}$/.test(value);
function providerProblem(provider, status, code, message, flags = {}) {
  return problem(status, code, message, { provider, ...flags });
}
async function developerAuthorized(token, env) {
  const expected = env.LANGPACK_DEVELOPER_TOKEN;
  if (typeof expected !== 'string' || expected.length < 24 || typeof token !== 'string' || token.length > 2048) return false;
  const digest = async value => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  const a = await digest(expected), b = await digest(token);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}
function credentialShape(provider, value) {
  if (!plainObject(value)) return false;
  const fields = { MyMemory: ['apiKey', 'email'], ZTAITrans: ['apiKey', 'tenantId', 'developerToken'], DeepL: ['apiKey', 'plan'], Azure: ['apiKey', 'region'], Google: ['apiKey'], Baidu: ['appId', 'secretKey'], Tencent: ['secretId', 'secretKey', 'region'], Alibaba: ['accessKeyId', 'accessKeySecret'] }[provider];
  if (!fields || Object.keys(value).some(key => !fields.includes(key))) return false;
  if (provider === 'ZTAITrans' && value.developerToken !== undefined) return Object.keys(value).length === 1 && safeCredential(value.developerToken);
  if (provider === 'Baidu') return typeof value.appId === 'string' && /^\d{1,64}$/.test(value.appId) && safeCredential(value.secretKey);
  if (provider === 'Tencent') return safeCredential(value.secretId) && safeCredential(value.secretKey) && (value.region === undefined || typeof value.region === 'string' && /^[a-z]{2}-[a-z0-9-]{1,48}$/.test(value.region));
  if (provider === 'Alibaba') return safeCredential(value.accessKeyId) && safeCredential(value.accessKeySecret);
  if (!safeCredential(value.apiKey)) return false;
  if (provider === 'MyMemory' && value.email !== undefined && (typeof value.email !== 'string' || value.email.length > 254 || value.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.email))) return false;
  if (provider === 'DeepL' && value.plan !== undefined && !['free', 'pro'].includes(value.plan)) return false;
  if (provider === 'Azure' && value.region !== undefined && (typeof value.region !== 'string' || value.region && !/^[a-z0-9-]{1,64}$/.test(value.region))) return false;
  if (provider === 'ZTAITrans' && value.tenantId !== undefined && (typeof value.tenantId !== 'string' || !/^[a-zA-Z0-9_.-]{1,128}$/.test(value.tenantId))) return false;
  return true;
}
// Baidu's documented protocol requires MD5. This small UTF-8 implementation also
// runs in Node, whose Web Crypto deliberately does not expose the legacy digest.
function baiduMD5(value) {
  const source = new TextEncoder().encode(value), length = Math.ceil((source.length + 9) / 64) * 64;
  const bytes = new Uint8Array(length); bytes.set(source); bytes[source.length] = 0x80;
  const view = new DataView(bytes.buffer); view.setUint32(length - 8, source.length * 8, true); view.setUint32(length - 4, Math.floor(source.length / 0x20000000), true);
  const shifts = [7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21];
  const constants = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000) >>> 0);
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  for (let offset = 0; offset < length; offset += 64) {
    let a = a0, b = b0, c = c0, d = d0;
    for (let i = 0; i < 64; i++) {
      const round = Math.floor(i / 16), shift = shifts[round * 4 + i % 4];
      const f = round === 0 ? (b & c) | (~b & d) : round === 1 ? (d & b) | (~d & c) : round === 2 ? b ^ c ^ d : c ^ (b | ~d);
      const index = round === 0 ? i : round === 1 ? (5 * i + 1) % 16 : round === 2 ? (3 * i + 5) % 16 : (7 * i) % 16;
      const n = (a + f + constants[i] + view.getUint32(offset + index * 4, true)) >>> 0;
      const next = (b + ((n << shift) | (n >>> (32 - shift)))) >>> 0;
      a = d; d = c; c = b; b = next;
    }
    a0 = (a0 + a) >>> 0; b0 = (b0 + b) >>> 0; c0 = (c0 + c) >>> 0; d0 = (d0 + d) >>> 0;
  }
  const result = new DataView(new ArrayBuffer(16)); [a0, b0, c0, d0].forEach((n, i) => result.setUint32(i * 4, n, true));
  return Array.from(new Uint8Array(result.buffer), n => n.toString(16).padStart(2, '0')).join('');
}
const utf8 = value => new TextEncoder().encode(value);
const hex = bytes => Array.from(new Uint8Array(bytes), n => n.toString(16).padStart(2, '0')).join('');
const sha256 = async value => hex(await crypto.subtle.digest('SHA-256', utf8(value)));
async function hmac(hash, key, value) {
  const imported = await crypto.subtle.importKey('raw', typeof key === 'string' ? utf8(key) : key, { name: 'HMAC', hash }, false, ['sign']);
  return crypto.subtle.sign('HMAC', imported, utf8(value));
}
const rpcEncode = value => encodeURIComponent(value).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
const rpcForm = values => Object.keys(values).sort().map(key => rpcEncode(key) + '=' + rpcEncode(values[key])).join('&');
async function providerUpstream(provider, credentials, content, locale, sourceLocale = 'zh-Hans') {
  const headers = { 'Content-Type': 'application/json' };
  const chineseSource = sourceLocale === 'zh-Hans';
  if (provider === 'Baidu') {
    const salt = String(crypto.getRandomValues(new Uint32Array(1))[0]);
    const form = { q: content, from: chineseSource ? 'zh' : 'en', to: PROVIDER_LOCALES.Baidu[locale], appid: credentials.appId, salt, sign: baiduMD5(credentials.appId + content + salt + credentials.secretKey) };
    return { url: 'https://fanyi-api.baidu.com/api/trans/vip/translate', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, encodedBody: new URLSearchParams(form).toString() };
  }
  if (provider === 'Tencent') {
    const timestamp = Math.floor(Date.now() / 1000), date = new Date(timestamp * 1000).toISOString().slice(0, 10);
    const host = 'tmt.tencentcloudapi.com', type = 'application/json; charset=utf-8';
    const encodedBody = JSON.stringify({ SourceText: content, Source: chineseSource ? 'zh' : 'en', Target: PROVIDER_LOCALES.Tencent[locale], ProjectId: 0 });
    const canonical = 'POST\n/\n\ncontent-type:' + type + '\nhost:' + host + '\nx-tc-action:texttranslate\n\ncontent-type;host;x-tc-action\n' + await sha256(encodedBody);
    const scope = date + '/tmt/tc3_request', toSign = 'TC3-HMAC-SHA256\n' + timestamp + '\n' + scope + '\n' + await sha256(canonical);
    const dateKey = await hmac('SHA-256', 'TC3' + credentials.secretKey, date);
    const serviceKey = await hmac('SHA-256', dateKey, 'tmt'), signingKey = await hmac('SHA-256', serviceKey, 'tc3_request');
    const signature = hex(await hmac('SHA-256', signingKey, toSign));
    return { url: 'https://' + host + '/', headers: { 'Content-Type': type, 'X-TC-Action': 'TextTranslate', 'X-TC-Version': '2018-03-21', 'X-TC-Timestamp': String(timestamp), 'X-TC-Region': credentials.region || 'ap-guangzhou', Authorization: 'TC3-HMAC-SHA256 Credential=' + credentials.secretId + '/' + scope + ', SignedHeaders=content-type;host;x-tc-action, Signature=' + signature }, encodedBody };
  }
  if (provider === 'Alibaba') {
    const common = { AccessKeyId: credentials.accessKeyId, Action: 'TranslateGeneral', Format: 'JSON', Version: '2018-10-12', SignatureMethod: 'HMAC-SHA1', SignatureVersion: '1.0', Timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), SignatureNonce: crypto.randomUUID(), RegionId: 'cn-hangzhou' };
    const form = { FormatType: 'text', SourceLanguage: chineseSource ? 'zh' : 'en', TargetLanguage: PROVIDER_LOCALES.Alibaba[locale], SourceText: content, Scene: 'general' };
    const signature = await hmac('SHA-1', credentials.accessKeySecret + '&', 'POST&%2F&' + rpcEncode(rpcForm({ ...common, ...form })));
    common.Signature = btoa(String.fromCharCode(...new Uint8Array(signature)));
    // As in Alibaba's official pop-core RPC client, every signed parameter is
    // sent once in the form body, keeping both credentials and text out of URLs.
    return { url: 'https://mt.cn-hangzhou.aliyuncs.com/', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, encodedBody: rpcForm({ ...common, ...form }) };
  }
  if (provider === 'MyMemory') return { url: 'https://api.mymemory.translated.net/get?' + new URLSearchParams({ q: content, langpair: (chineseSource ? 'zh-CN' : 'en') + '|' + PROVIDER_LOCALES.MyMemory[locale], mt: '1', key: credentials.apiKey, ...(credentials.email ? { de: credentials.email } : {}) }), method: 'GET', headers: { Accept: 'application/json' } };
  if (provider === 'ZTAITrans') return { url: UPSTREAM, headers: { ...headers, 'X-Api-Key': credentials.apiKey }, body: { model: 'fast', targetLanguage: TARGETS[locale], items: [{ id: 'segment-1', content }], ...(credentials.tenantId ? { tenantId: credentials.tenantId } : {}) } };
  if (provider === 'DeepL') return { url: `https://${credentials.plan === 'pro' ? 'api' : 'api-free'}.deepl.com/v2/translate`, headers: { ...headers, Authorization: 'DeepL-Auth-Key ' + credentials.apiKey }, body: { text: [content], source_lang: chineseSource ? 'ZH' : 'EN', target_lang: PROVIDER_LOCALES.DeepL[locale] } };
  if (provider === 'Azure') return { url: 'https://api.cognitive.microsofttranslator.com/translate?' + new URLSearchParams({ 'api-version': '3.0', from: chineseSource ? 'zh-Hans' : 'en', to: PROVIDER_LOCALES.Azure[locale] }), headers: { ...headers, 'Ocp-Apim-Subscription-Key': credentials.apiKey, ...(credentials.region ? { 'Ocp-Apim-Subscription-Region': credentials.region } : {}) }, body: [{ Text: content }] };
  return { url: 'https://translation.googleapis.com/language/translate/v2', headers: { ...headers, 'X-Goog-Api-Key': credentials.apiKey }, body: { q: [content], source: chineseSource ? 'zh-CN' : 'en', target: PROVIDER_LOCALES.Google[locale], format: 'text', model: 'nmt' } };
}
function genericUpstreamFailure(provider, response, payload) {
  const status = response.status;
  if (['Baidu', 'Tencent', 'Alibaba'].includes(provider)) {
    const code = provider === 'Baidu' ? String(payload?.error_code || '') : provider === 'Tencent' ? String(payload?.Response?.Error?.Code || '') : String(payload?.Code ?? '');
    const auth = provider === 'Baidu' ? ['52003', '54001', '58000', '58003', '90107'].includes(code) : provider === 'Tencent' ? /^(?:AuthFailure|UnauthorizedOperation)(?:\.|$)/.test(code) || ['IpInBlacklist', 'IpNotInWhitelist'].includes(code) : ['10009', '10011'].includes(code) || /^(?:InvalidAccessKeyId|SignatureDoesNotMatch|InvalidSecurityToken|Forbidden|NoPermission|AccessDenied)(?:\.|$)/.test(code);
    if ([401, 403].includes(status) || auth) return providerProblem(provider, 401, 'PROVIDER_AUTH', '该平台的凭据、访问权限或出口 IP 不可用，请检查配置。', { fatal: true });
    const config = provider === 'Baidu' ? code === '58002' : provider === 'Tencent' ? ['UnsupportedRegion', 'FailedOperation.ServiceIsolate', 'ActionOffline', 'FailedOperation.UserNotRegistered', 'FailedOperation.StopUsing', 'FailedOperation.ErrorUserArea'].includes(code) : ['10010', '10013'].includes(code);
    if (config) return providerProblem(provider, 400, 'PROVIDER_CONFIG', '该平台服务尚未开通、已停用或账户欠费，请检查平台控制台。', { fatal: true });
    const quota = provider === 'Baidu' ? code === '54004' : provider === 'Tencent' ? ['FailedOperation.NoFreeAmount', 'FailedOperation.NoBalance', 'LimitExceeded.FreeAmountLimit', 'LimitExceeded.NoFreeAmount'].includes(code) : false;
    if (quota) return providerProblem(provider, 402, 'PROVIDER_QUOTA', '该平台可用额度或余额已耗尽，已保存的译文会保留。', { quota: true });
    const unsupported = provider === 'Baidu' ? code === '58001' : provider === 'Tencent' ? ['InvalidParameter.UnsupportedLanguage', 'UnsupportedOperation.UnsupportedLanguage', 'UnsupportedOperation.UnSupportedTargetLanguage', 'UnsupportedOperation.UnsupportedSourceLanguage'].includes(code) : code === '10005';
    if (unsupported) return providerProblem(provider, 400, 'PROVIDER_UNSUPPORTED', '该平台或当前账户套餐不支持此语言方向。', { unsupported: true });
    const rate = provider === 'Baidu' ? ['54003', '54005'].includes(code) : provider === 'Tencent' ? /^(?:RequestLimitExceeded|LimitExceeded)(?:\.|$)/.test(code) : /^(?:Throttling|Throttling\.User|Throttling\.Api)$/.test(code);
    if (status === 429 || rate) return providerProblem(provider, 429, 'PROVIDER_RATE_LIMIT', '该平台请求过于频繁，请稍后重试。', { retryable: true, retryAfterMs: Math.max(cooldown(response), provider === 'Baidu' && code === '54005' ? 3000 : 0) });
    const service = provider === 'Baidu' ? ['52001', '52002'].includes(code) : provider === 'Tencent' ? /^(?:InternalError|FailedOperation|ServiceUnavailable)(?:\.|$)/.test(code) : ['10001', '10002', '10007', '10012', '19999'].includes(code) || /^ServiceUnavailable(?:\.|$)/.test(code);
    if (status >= 500 || service) return providerProblem(provider, 502, 'PROVIDER_SERVICE', '该平台暂时不可用，请稍后重试。', { retryable: true });
    const success = provider === 'Baidu' ? !code || code === '52000' : provider === 'Tencent' ? !code : code === '200';
    if (!response.ok || !success || status >= 300) return providerProblem(provider, 400, 'PROVIDER_REQUEST', '该平台拒绝了请求，请检查原文、套餐和目标语言。');
    return null;
  }
  if (provider === 'MyMemory') {
    const details = typeof payload?.responseDetails === 'string' ? payload.responseDetails : '';
    const candidate = typeof payload?.responseData?.translatedText === 'string' ? payload.responseData.translatedText : '';
    const serviceStatus = Number(payload?.responseStatus);
    if ([401, 403].includes(status) || serviceStatus === 401) return providerProblem(provider, 401, 'PROVIDER_AUTH', 'MyMemory 凭据无效或无权访问，请检查配置。', { fatal: true });
    const quotaMessage = value => /used all available free translations|next available in|quota\s*(?:has been\s*)?(?:exceed|finish|exhaust)|(?:daily|free)\s+(?:translation\s+)?(?:limit|quota)\s*(?:reached|exceed|exhaust)|out of quota/i.test(value);
    if ([true, 'true', 1].includes(payload?.quotaFinished) || quotaMessage(details) || /^\s*MYMEMORY WARNING:/i.test(candidate) && quotaMessage(candidate)) return providerProblem(provider, 402, 'PROVIDER_QUOTA', 'MyMemory 额度已耗尽，已保存译文会保留。', { quota: true, retryAfterMs: cooldown(response) });
    // MyMemory also represents actual daily exhaustion as HTTP 200/business 403.
    // Only business 403 without the trusted quota signals above is authorization.
    if (serviceStatus === 403) return providerProblem(provider, 401, 'PROVIDER_AUTH', 'MyMemory 凭据无效或无权访问，请检查配置。', { fatal: true });
    if (status === 429 || serviceStatus === 429) return providerProblem(provider, 429, 'PROVIDER_RATE_LIMIT', 'MyMemory 请求过于频繁，请稍后重试。', { retryable: true, retryAfterMs: cooldown(response) });
    if (status >= 500 || serviceStatus >= 500) return providerProblem(provider, 502, 'PROVIDER_SERVICE', 'MyMemory 暂时不可用，请稍后重试。', { retryable: true });
    if (!response.ok || serviceStatus !== 200 || /MYMEMORY WARNING:|NO QUERY SPECIFIED|INVALID LANGPAIR|IS AN INVALID (?:TARGET|SOURCE) LANGUAGE|PLEASE SELECT TWO DISTINCT LANGUAGES/i.test(candidate)) return providerProblem(provider, 400, 'PROVIDER_REQUEST', 'MyMemory 未返回有效译文，请检查请求与账户配置。');
    return null;
  }
  const azureCode = Number(payload?.error?.code);
  const googleReasons = Array.isArray(payload?.error?.errors) ? payload.error.errors.map(item => item?.reason) : [];
  const quota = provider === 'DeepL' && status === 456 || provider === 'Azure' && azureCode === 403001 || provider === 'Google' && googleReasons.some(reason => ['dailyLimitExceeded', 'dailyLimitExceededUnreg', 'quotaExceeded'].includes(reason));
  if (quota) return providerProblem(provider, 402, 'PROVIDER_QUOTA', '该平台额度已耗尽，已保存的译文会保留。', { quota: true });
  if (provider === 'Google' && googleReasons.some(reason => ['userRateLimitExceeded', 'rateLimitExceeded'].includes(reason))) return providerProblem(provider, 429, 'PROVIDER_RATE_LIMIT', '该平台请求过于频繁，请稍后重试。', { retryable: true, retryAfterMs: cooldown(response) });
  if ([401, 403].includes(status)) return providerProblem(provider, 401, 'PROVIDER_AUTH', '该平台的凭据无效或缺少权限，请检查配置。', { fatal: true });
  if (status === 429) return providerProblem(provider, 429, 'PROVIDER_RATE_LIMIT', '该平台请求过于频繁，请稍后重试。', { retryable: true, retryAfterMs: cooldown(response) });
  if (status >= 500) return providerProblem(provider, 502, 'PROVIDER_SERVICE', '该平台暂时不可用，请稍后重试。', { retryable: true });
  if (!response.ok || payload?.error || status >= 300) return providerProblem(provider, 400, 'PROVIDER_REQUEST', '该平台拒绝了请求，请检查原文、套餐和目标语言。');
  return null;
}
function decodeProviderText(value) {
  return value.replace(/&(?:#(x[0-9a-f]+|\d+)|amp|lt|gt|quot|apos);/gi, (entity, number) => {
    if (number) {
      const point = number[0].toLowerCase() === 'x' ? parseInt(number.slice(1), 16) : Number(number);
      return Number.isInteger(point) && point >= 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff) ? String.fromCodePoint(point) : entity;
    }
    return ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity.toLowerCase()] || entity;
  });
}
function genericOutput(provider, payload, locale, credentials, source, sourceLocale = 'zh-Hans') {
  let text;
  if (provider === 'MyMemory' && typeof payload?.responseData?.translatedText === 'string') text = decodeProviderText(payload.responseData.translatedText);
  if (provider === 'DeepL' && Array.isArray(payload?.translations) && payload.translations.length === 1) text = payload.translations[0]?.text;
  if (provider === 'Azure' && Array.isArray(payload) && payload.length === 1 && Array.isArray(payload[0]?.translations) && payload[0].translations.length === 1) {
    const translation = payload[0].translations[0];
    if (typeof translation?.to === 'string' && translation.to.toLowerCase() === PROVIDER_LOCALES.Azure[locale].toLowerCase()) text = translation.text;
  }
  if (provider === 'Google' && Array.isArray(payload?.data?.translations) && payload.data.translations.length === 1 && typeof payload.data.translations[0]?.translatedText === 'string') text = decodeProviderText(payload.data.translations[0].translatedText);
  if (provider === 'Baidu' && payload?.from === (sourceLocale === 'en' ? 'en' : 'zh') && payload?.to === PROVIDER_LOCALES.Baidu[locale] && Array.isArray(payload?.trans_result) && payload.trans_result.length > 0 && payload.trans_result.every(item => typeof item?.src === 'string' && typeof item?.dst === 'string' && item.dst.trim()) && payload.trans_result.map(item => item.src).join('\n') === source) text = payload.trans_result.map(item => item.dst).join('\n');
  if (provider === 'Tencent' && payload?.Response?.Source === (sourceLocale === 'en' ? 'en' : 'zh') && payload?.Response?.Target === PROVIDER_LOCALES.Tencent[locale]) text = payload.Response.TargetText;
  if (provider === 'Alibaba') text = payload?.Data?.Translated;
  const secrets = ['apiKey', 'appId', 'secretId', 'secretKey', 'accessKeyId', 'accessKeySecret'].map(field => credentials[field]).filter(value => typeof value === 'string' && value);
  if (typeof text !== 'string' || !text.trim() || secrets.some(secret => text.includes(secret)) || /^(?:\s*[.…]\s*)+$/u.test(text) || /^\s*(?:<!doctype html|<html(?:\s|>)|Internal Server Error\s*$)/i.test(text)) return null;
  return text;
}

const validationMethod = provider => ['DeepL', 'Google'].includes(provider) ? 'metadata' : 'translation';
function validationResult(provider, status, method, message) {
  // No translated text, raw diagnostics, tokens or usage/account identifiers are
  // returned. The character figure describes the fixed probe, not a bill receipt.
  return json({ provider, status, method, billableCharacters: method === 'translation' ? 1 : 0, message });
}
async function validateCredentials({ request, provider, credentials, fetchImpl, timeoutMs }) {
  const method = validationMethod(provider), controller = new AbortController();
  const onAbort = () => controller.abort();
  request.signal.addEventListener('abort', onAbort, { once: true });
  if (request.signal.aborted) controller.abort();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const unavailable = () => validationResult(provider, 'unavailable', method, '本次未能完成平台验证，请稍后手动重试；这不代表凭据无效。');
  try {
    let upstream;
    if (provider === 'DeepL') upstream = { url: `https://${credentials.plan === 'pro' ? 'api' : 'api-free'}.deepl.com/v2/usage`, method: 'GET', headers: { Authorization: 'DeepL-Auth-Key ' + credentials.apiKey, Accept: 'application/json' } };
    else if (provider === 'Google') upstream = { url: 'https://translation.googleapis.com/language/translate/v2/languages?model=nmt', method: 'GET', headers: { 'X-Goog-Api-Key': credentials.apiKey, Accept: 'application/json' } };
    else upstream = await providerUpstream(provider, credentials, '好', 'en');
    if (provider === 'MyMemory' && request.cf && request.headers.get('CF-Connecting-IP')) {
      const endpoint = new URL(upstream.url); endpoint.searchParams.set('ip', request.headers.get('CF-Connecting-IP')); upstream.url = endpoint.href;
    }
    if (controller.signal.aborted) return unavailable();
    const response = await abortRace(fetchImpl(upstream.url, { method: upstream.method || 'POST', headers: upstream.headers, ...(upstream.method !== 'GET' ? { body: upstream.encodedBody ?? JSON.stringify(upstream.body) } : {}), redirect: 'manual', signal: controller.signal }), controller.signal);
    let payload;
    try { payload = JSON.parse(await abortRace(readBounded(response, MAX_RESPONSE_BYTES, controller.signal), controller.signal)); }
    catch (error) { if (controller.signal.aborted) throw error; payload = null; }
    const failure = provider === 'ZTAITrans' ? upstreamFailure(response, payload) : genericUpstreamFailure(provider, response, payload);
    if (failure) {
      const diagnostic = await failure.json();
      if ([402, 429].includes(failure.status)) return validationResult(provider, 'limited', method, failure.status === 402 ? '平台返回额度或余额不足，暂时无法确认可翻译。' : '平台正在限流，本次无法判断凭据是否可用，请稍后手动重试。');
      if (failure.status === 401 || diagnostic.fatal || ['BACKUP_DISABLED', 'BACKUP_NOT_CONFIGURED'].includes(diagnostic.code)) return validationResult(provider, 'invalid', method, '平台授权或服务配置未通过验证，请检查凭据、区域、权限及服务是否开通。');
      if (failure.status >= 500) return unavailable();
      return validationResult(provider, 'invalid', method, '平台拒绝了这次验证，请检查凭据与账户服务配置。');
    }
    if (provider === 'DeepL') {
      const number = value => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
      if (!number(payload?.character_count) || !number(payload?.character_limit)) return unavailable();
      const hasKeyUsage = payload.api_key_character_count !== undefined || payload.api_key_character_limit !== undefined;
      if (hasKeyUsage && (!number(payload.api_key_character_count) || !number(payload.api_key_character_limit))) return unavailable();
      if (payload.character_count >= payload.character_limit || hasKeyUsage && payload.api_key_character_count >= payload.api_key_character_limit) return validationResult(provider, 'limited', method, '凭据通过用量接口授权，但账户或此密钥的字符限额已用完。');
      return validationResult(provider, 'valid', method, '用量接口授权检查通过，未试译；当前统计有剩余额度，具体翻译权限及计费以平台为准。');
    }
    if (provider === 'Google') {
      const languages = payload?.data?.languages;
      if (!Array.isArray(languages) || !languages.length || !languages.every(item => plainObject(item) && typeof item.language === 'string' && /^[a-z]{2,3}(?:-[A-Za-z]{2,8})?$/.test(item.language)) || !languages.some(item => item.language === 'en')) return unavailable();
      return validationResult(provider, 'valid', method, '语言目录授权检查通过，未试译；实际翻译仍受账户结算、配额与权限限制。');
    }
    const text = provider === 'ZTAITrans' ? validOutput(payload, '好', 'en', credentials.apiKey) : genericOutput(provider, payload, 'en', credentials, '好');
    if (text === null) return unavailable();
    return validationResult(provider, 'valid', method, provider === 'MyMemory' ? '单字试译通过；这不单独证明 MyMemory 私有词库的访问权限。' : '单字试译通过，当前凭据可以完成这次翻译请求；其他语言和后续额度仍以平台为准。');
  } catch (_) { return unavailable(); }
  finally { clearTimeout(timer); request.signal.removeEventListener('abort', onAbort); }
}

export function createHandler({ fetchImpl = (...args) => fetch(...args), timeoutMs = 600000 } = {}) {
  const limit = Math.max(1, Math.min(600000, Number(timeoutMs) || 600000));
  return async function handle(request, env = {}, _ctx) {
    const url = new URL(request.url);
    if (!['/api/translation/status', '/api/translation/backup', '/api/translation/provider', '/api/translation/validate'].includes(url.pathname)) return null;
    const serverKey = typeof env.TRANSLATION_API_KEY === 'string' ? env.TRANSLATION_API_KEY.trim() : '';
    const developerConfigured = !!serverKey && typeof env.LANGPACK_DEVELOPER_TOKEN === 'string' && env.LANGPACK_DEVELOPER_TOKEN.length >= 24;
    if (url.pathname === '/api/translation/status') {
      if (request.method !== 'GET') return problem(405, 'METHOD_NOT_ALLOWED', '此接口只接受 GET 请求。');
      const authorized = developerConfigured && await developerAuthorized(request.headers.get('X-LangPack-Developer-Token'), env);
      return json({ backupConfigured: !!authorized, backupProvider: 'ZTAITrans', developerConfigured, developerAccessRequired: true, userCredentialsRequired: true, providers: PROVIDER_NAMES });
    }
    const legacy = url.pathname === '/api/translation/backup';
    const validating = url.pathname === '/api/translation/validate';
    if (request.method !== 'POST') return problem(405, 'METHOD_NOT_ALLOWED', '此接口只接受 POST 请求。');
    const origin = request.headers.get('Origin'), site = request.headers.get('Sec-Fetch-Site');
    if (origin !== null && origin !== url.origin || site !== null && !['same-origin', 'none'].includes(site)) return problem(403, 'BACKUP_ORIGIN', '仅允许从当前工作台发起翻译请求。');
    if (request.signal.aborted) return problem(499, legacy ? 'BACKUP_ABORTED' : 'PROVIDER_ABORTED', '翻译请求已取消。');
    // Even old clients cannot consume the environment key without owner authentication.
    if (legacy && (!developerConfigured || !await developerAuthorized(request.headers.get('X-LangPack-Developer-Token'), env))) return problem(401, 'PROVIDER_AUTH', '开发者共享服务需要访问口令，请配置自己的平台密钥或更新客户端。', { fatal: true });
    if (request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return problem(415, 'BACKUP_CONTENT_TYPE', '请使用 JSON 格式提交翻译内容。');
    let body;
    try { body = JSON.parse(await readBounded(request, validating ? 16 * 1024 : MAX_REQUEST_BYTES, request.signal)); }
    catch (error) {
      if (request.signal.aborted || error.code === 'ABORTED') return problem(499, legacy ? 'BACKUP_ABORTED' : 'PROVIDER_ABORTED', '翻译请求已取消。');
      if (error.code === 'TOO_LARGE') return problem(413, 'BACKUP_TOO_LARGE', '这段内容超过请求大小限制，请拆分后重试。');
      return problem(400, 'BACKUP_JSON', '翻译请求不是有效的 JSON。');
    }
    const allowed = legacy ? ['content', 'locale', 'sourceLocale'] : validating ? ['provider', 'credentials'] : ['provider', 'content', 'locale', 'sourceLocale', 'credentials'];
    if (!plainObject(body) || Object.keys(body).some(key => !allowed.includes(key))) return problem(400, 'BACKUP_FIELDS', '请求中包含不支持的字段。');
    const provider = legacy ? 'ZTAITrans' : body.provider;
    if (!PROVIDER_NAMES.includes(provider)) return problem(400, 'PROVIDER_CONFIG', '请选择支持的翻译平台。', { fatal: true });
    // Probe content and language can never be supplied by callers. No retries,
    // account fallback, project writes or translation cache are involved.
    if (validating) body = { ...body, content: '好', locale: 'en' };
    if (typeof body.content !== 'string' || !body.content.trim()) return providerProblem(provider, 400, legacy ? 'BACKUP_EMPTY' : 'PROVIDER_REQUEST', '请先提供需要翻译的原文。');
    if (Array.from(body.content).length > MAX_CONTENT_CHARACTERS) return providerProblem(provider, 413, 'BACKUP_TOO_LARGE', '单段原文不能超过 50,000 个字符，请拆分后重试。');
    const sourceLocale = body.sourceLocale === undefined ? 'zh-Hans' : body.sourceLocale;
    if (!['zh-Hans', 'en'].includes(sourceLocale)) return providerProblem(provider, 400, legacy ? 'BACKUP_LANGUAGE' : 'PROVIDER_UNSUPPORTED', '当前源语言不受支持。', { unsupported: true });
    if (typeof body.locale !== 'string' || !Object.hasOwn(TARGETS, body.locale) || body.locale === sourceLocale) return providerProblem(provider, 400, legacy ? 'BACKUP_LANGUAGE' : 'PROVIDER_UNSUPPORTED', '当前目标语言不受支持。', { unsupported: true });
    if (provider !== 'ZTAITrans' && !Object.hasOwn(PROVIDER_LOCALES[provider], body.locale)) return providerProblem(provider, 400, 'PROVIDER_UNSUPPORTED', '此平台不支持该目标语言的精确代码，请选择其他已配置平台。', { unsupported: true });
    let credentials = legacy ? { apiKey: serverKey } : body.credentials;
    if (validating && provider === 'MyMemory' && plainObject(credentials) && (credentials.apiKey === undefined || credentials.apiKey === '') && credentialShape(provider, { ...credentials, apiKey: 'anonymous-validation-placeholder' })) return validationResult(provider, 'valid', 'anonymous', '匿名模式无需 API 密钥，本次未调用平台或验证私有词库。');
    if (!credentialShape(provider, credentials)) return providerProblem(provider, 400, 'PROVIDER_CONFIG', '请完整配置该平台自己的凭据。', { fatal: true });
    if (provider === 'ZTAITrans' && credentials.developerToken !== undefined) {
      if (!developerConfigured || !await developerAuthorized(credentials.developerToken, env)) return providerProblem(provider, 401, 'PROVIDER_AUTH', '开发者访问口令无效或尚未配置。', { fatal: true });
      credentials = { apiKey: serverKey };
    }
    if (validating) return validateCredentials({ request, provider, credentials, fetchImpl, timeoutMs: Math.min(limit, 20000) });
    const contentBytes = new TextEncoder().encode(body.content).byteLength;
    const characterLimit = { Baidu: 1000, Tencent: 2000, Alibaba: 5000 }[provider];
    if (characterLimit && Array.from(body.content).length > characterLimit || provider === 'Baidu' && contentBytes > 6000) return providerProblem(provider, 413, 'BACKUP_TOO_LARGE', '这段内容超过该平台单次请求限制，请拆分后重试。');
    let upstream;
    try { upstream = await providerUpstream(provider, credentials, body.content, body.locale, sourceLocale); }
    catch (_) { return providerProblem(provider, 502, 'PROVIDER_SERVICE', '无法准备该平台请求，请稍后重试。', { retryable: true }); }
    const upstreamBody = upstream.encodedBody ?? JSON.stringify(upstream.body);
    const maximum = provider === 'Google' ? 100 * 1024 : provider === 'DeepL' ? 128 * 1024 : MAX_REQUEST_BYTES;
    if (provider === 'MyMemory' ? new TextEncoder().encode(body.content).byteLength > 480 : new TextEncoder().encode(upstreamBody).byteLength > maximum) return providerProblem(provider, 413, 'BACKUP_TOO_LARGE', '这段内容超过该平台单次请求限制，请拆分后重试。');
    // On Workers this header is assigned by Cloudflare, preserving the actual caller's
    // MyMemory quota identity. Never trust a client-supplied equivalent in Node.
    if (provider === 'MyMemory' && request.cf && request.headers.get('CF-Connecting-IP')) {
      const endpoint = new URL(upstream.url); endpoint.searchParams.set('ip', request.headers.get('CF-Connecting-IP')); upstream.url = endpoint.href;
    }
    const controller = new AbortController(); let timedOut = false;
    const onAbort = () => controller.abort();
    request.signal.addEventListener('abort', onAbort, { once: true });
    if (request.signal.aborted) controller.abort();
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, limit);
    try {
      const response = await abortRace(fetchImpl(upstream.url, { method: upstream.method || 'POST', headers: upstream.headers, ...(upstream.method !== 'GET' ? { body: upstreamBody } : {}), redirect: 'manual', signal: controller.signal }), controller.signal);
      let payload;
      try { payload = JSON.parse(await abortRace(readBounded(response, MAX_RESPONSE_BYTES, controller.signal), controller.signal)); }
      catch (error) { if (controller.signal.aborted) throw error; payload = null; }
      const failure = provider === 'ZTAITrans' ? upstreamFailure(response, payload) : genericUpstreamFailure(provider, response, payload);
      if (failure) {
        if (legacy || provider !== 'ZTAITrans') return failure;
        const diagnostic = await failure.json();
        if (failure.status === 402) return providerProblem(provider, 402, 'PROVIDER_QUOTA', '该平台的租户预算已耗尽，已保存译文会保留。', { quota: true });
        if (failure.status === 401) return providerProblem(provider, 401, 'PROVIDER_AUTH', '该平台的凭据无效或无权使用，请检查配置。', { fatal: true });
        if (['BACKUP_DISABLED', 'BACKUP_NOT_CONFIGURED'].includes(diagnostic.code)) return providerProblem(provider, 400, 'PROVIDER_CONFIG', '该平台服务尚未启用或配置，请联系服务提供方。', { fatal: true });
        if (failure.status === 429) return providerProblem(provider, 429, 'PROVIDER_RATE_LIMIT', '该平台请求过于频繁，请稍后重试。', { retryable: true, retryAfterMs: diagnostic.retryAfterMs || 0 });
        if (failure.status >= 500) return providerProblem(provider, 502, 'PROVIDER_SERVICE', '该平台暂时不可用，请稍后重试。', { retryable: !!diagnostic.retryable });
        return providerProblem(provider, 400, 'PROVIDER_REQUEST', '该平台拒绝了请求，请检查原文和目标语言。');
      }
      const text = provider === 'ZTAITrans' ? validOutput(payload, body.content, body.locale, credentials.apiKey) : genericOutput(provider, payload, body.locale, credentials, body.content, sourceLocale);
      if (text === null || body.credentials?.developerToken && text.includes(body.credentials.developerToken)) return providerProblem(provider, 502, legacy ? 'BACKUP_RESPONSE' : 'PROVIDER_RESPONSE', '平台返回了不完整或不匹配的结果，未保存为译文。');
      return json({ text, provider, ...(provider === 'ZTAITrans' ? { model: 'fast' } : provider === 'Google' ? { model: 'nmt' } : {}) });
    } catch (_) {
      if (request.signal.aborted) return providerProblem(provider, 499, legacy ? 'BACKUP_ABORTED' : 'PROVIDER_ABORTED', '翻译请求已取消。');
      if (timedOut) return providerProblem(provider, 504, legacy ? 'BACKUP_TIMEOUT' : 'PROVIDER_TIMEOUT', '平台请求超时，已完成的译文会保留。', { retryable: true });
      return providerProblem(provider, 502, legacy ? 'BACKUP_SERVICE' : 'PROVIDER_SERVICE', '无法连接该平台，请稍后重试。', { retryable: true });
    } finally { clearTimeout(timer); request.signal.removeEventListener('abort', onAbort); }
  };
}
