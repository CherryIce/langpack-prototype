// Server-only translation proxy. The API key is supplied by the hosted runtime.
const UPSTREAM = 'https://aitrans-iqwek72342.futureinvest.id/api/translate/text';
const MAX_REQUEST_BYTES = 256 * 1024;
const MAX_RESPONSE_BYTES = 1024 * 1024;
const MAX_CONTENT_CHARACTERS = 50000;
const TARGETS = Object.freeze({ en: 'English', ja: 'Japanese', ko: 'Korean', fr: 'French', de: 'German', es: 'Spanish', 'zh-Hant': 'Traditional Chinese' });
const TARGET_ALIASES = Object.freeze({
  en: ['english', 'en', 'en-us', 'en_us', 'en-gb', 'en_gb', '英语'],
  ja: ['japanese', 'ja', 'ja-jp', 'ja_jp', '日语'],
  ko: ['korean', 'ko', 'ko-kr', 'ko_kr', '韩语'],
  fr: ['french', 'fr', 'fr-fr', 'fr_fr', '法语'],
  de: ['german', 'de', 'de-de', 'de_de', '德语'],
  es: ['spanish', 'es', 'es-es', 'es_es', '西班牙语'],
  'zh-Hant': ['traditional chinese', 'zh-hant', 'zh-tw', 'zh_tw', '繁体中文', '繁體中文']
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

export function createHandler({ fetchImpl = (...args) => fetch(...args), timeoutMs = 600000 } = {}) {
  const limit = Math.max(1, Math.min(600000, Number(timeoutMs) || 600000));
  return async function handle(request, env = {}, _ctx) {
    const url = new URL(request.url);
    if (!['/api/translation/status', '/api/translation/backup'].includes(url.pathname)) return null;
    const secret = typeof env.TRANSLATION_API_KEY === 'string' ? env.TRANSLATION_API_KEY.trim() : '';
    if (url.pathname === '/api/translation/status') {
      if (request.method !== 'GET') return problem(405, 'METHOD_NOT_ALLOWED', '此接口只接受 GET 请求。', { retryable: false });
      return json({ backupConfigured: !!secret, backupProvider: 'ZTAITrans' });
    }
    if (request.method !== 'POST') return problem(405, 'METHOD_NOT_ALLOWED', '此接口只接受 POST 请求。');
    const origin = request.headers.get('Origin');
    const site = request.headers.get('Sec-Fetch-Site');
    if (origin !== null && origin !== url.origin || site !== null && !['same-origin', 'none'].includes(site)) return problem(403, 'BACKUP_ORIGIN', '仅允许从当前工作台发起翻译请求。');
    if (request.signal.aborted) return problem(499, 'BACKUP_ABORTED', '翻译请求已取消。');
    if (!secret) return problem(503, 'BACKUP_NOT_CONFIGURED', '备用翻译服务尚未配置，已保留当前任务。');
    if (request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return problem(415, 'BACKUP_CONTENT_TYPE', '请使用 JSON 格式提交翻译内容。');
    let body;
    try { body = JSON.parse(await readBounded(request, MAX_REQUEST_BYTES, request.signal)); }
    catch (error) {
      if (request.signal.aborted || error.code === 'ABORTED') return problem(499, 'BACKUP_ABORTED', '翻译请求已取消。');
      if (error.code === 'TOO_LARGE') return problem(413, 'BACKUP_TOO_LARGE', '这段内容超过请求大小限制，请拆分后重试。');
      return problem(400, 'BACKUP_JSON', '翻译请求不是有效的 JSON。');
    }
    if (!body || Array.isArray(body) || typeof body !== 'object' || Object.keys(body).some(key => !['content', 'locale'].includes(key))) return problem(400, 'BACKUP_FIELDS', '请求只允许包含原文和目标语言。');
    if (typeof body.content !== 'string' || !body.content.trim()) return problem(400, 'BACKUP_EMPTY', '请先提供需要翻译的原文。');
    if (Array.from(body.content).length > MAX_CONTENT_CHARACTERS) return problem(413, 'BACKUP_TOO_LARGE', '单段原文不能超过 50,000 个字符，请拆分后重试。');
    if (typeof body.locale !== 'string' || !Object.hasOwn(TARGETS, body.locale)) return problem(400, 'BACKUP_LANGUAGE', '当前目标语言不受支持。');
    const controller = new AbortController(); let timedOut = false;
    const onAbort = () => controller.abort();
    request.signal.addEventListener('abort', onAbort, { once: true });
    if (request.signal.aborted) controller.abort();
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, limit);
    try {
      const response = await abortRace(fetchImpl(UPSTREAM, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Api-Key': secret },
        body: JSON.stringify({ model: 'fast', targetLanguage: TARGETS[body.locale], items: [{ id: 'segment-1', content: body.content }] }),
        // Workers supports manual/follow, not Fetch's "error" mode. Never follow
        // an upstream redirect: the API key must stay on the fixed endpoint.
        redirect: 'manual', signal: controller.signal
      }), controller.signal);
      let payload;
      try { payload = JSON.parse(await abortRace(readBounded(response, MAX_RESPONSE_BYTES, controller.signal), controller.signal)); }
      catch (error) { if (controller.signal.aborted) throw error; payload = null; }
      const failure = upstreamFailure(response, payload);
      if (failure) return failure;
      const text = validOutput(payload, body.content, body.locale, secret);
      if (text === null) return problem(502, 'BACKUP_RESPONSE', '备用翻译服务返回了不完整或不匹配的结果，未保存为译文。');
      return json({ text, provider: 'ZTAITrans', model: 'fast' });
    } catch (_) {
      if (request.signal.aborted) return problem(499, 'BACKUP_ABORTED', '翻译请求已取消。');
      if (timedOut) return problem(504, 'BACKUP_TIMEOUT', '备用翻译请求超时，现有结果已保留。', { retryable: true });
      return problem(502, 'BACKUP_SERVICE', '无法连接备用翻译服务，请稍后重试。', { retryable: true });
    } finally { clearTimeout(timer); request.signal.removeEventListener('abort', onAbort); }
  };
}

export default { fetch: createHandler() };
