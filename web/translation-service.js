/* Browser translation chain. The authenticated backup key is held by the server only. */
(function (root, factory) {
  'use strict';
  const api = factory(root.LangPackLanguages || (typeof module === 'object' && module.exports ? require('./languages.js') : null));
  root.TranslationService = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis, function (languages) {
  'use strict';
  const PROVIDER = 'ZTAITrans';
  const placeholderPattern = () => /\{\{\s*[\w.]+\s*\}\}|\{[\w.]+\}|%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdif@uoxXegGc]|%%/g;
  const protectedPattern = () => /\{\{\s*[\w.]+\s*\}\}|\{[\w.]+\}|%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdif@uoxXegGc]|%%|\r\n|\r|\n|ZXQ(?:PH|NL)\s*\d+\s*QXZ/gi;

  function failure(code, message, extra = {}) {
    const error = new Error(message);
    Object.assign(error, { name: code === 'ABORTED' || code === 'BACKUP_ABORTED' ? 'AbortError' : 'TranslationError', code, provider: PROVIDER, retryable: false, quota: false }, extra);
    return error;
  }
  function aborted() { return failure('ABORTED', '翻译已暂停，已完成的结果会保留。'); }
  function checkAbort(signal) { if (signal?.aborted) throw aborted(); }
  function isAbort(error) { return error?.name === 'AbortError' || error?.code === 'ABORTED'; }
  function withAbort(promise, signal) {
    if (!signal) return promise;
    if (signal.aborted) return Promise.reject(aborted());
    return new Promise((resolve, reject) => {
      const onAbort = () => { signal.removeEventListener('abort', onAbort); reject(aborted()); };
      signal.addEventListener('abort', onAbort, { once: true });
      Promise.resolve(promise).then(value => { signal.removeEventListener('abort', onAbort); resolve(value); }, error => { signal.removeEventListener('abort', onAbort); reject(error); });
    });
  }
  function sleep(ms, signal) {
    return new Promise((resolve, reject) => {
      if (signal?.aborted) return reject(aborted());
      const onAbort = () => { clearTimeout(timer); signal.removeEventListener('abort', onAbort); reject(aborted()); };
      const timer = setTimeout(() => { signal?.removeEventListener('abort', onAbort); resolve(); }, Math.max(0, ms));
      signal?.addEventListener('abort', onAbort, { once: true });
    });
  }
  function notify(callback, value) { if (typeof callback === 'function') { try { callback(value); } catch (_) { /* Observers must not turn successful translations into errors. */ } } }
  function providerError(error, provider) {
    if (error && typeof error === 'object') { try { if (!error.provider) error.provider = provider; } catch (_) { /* Preserve frozen errors. */ } }
    return error;
  }
  const placeholders = text => (String(text).match(placeholderPattern()) || []).map(token => token.replace(/\s+/g, '')).sort();
  const markers = text => (String(text).match(/ZXQ(?:PH|NL)\d+QXZ/g) || []).sort();
  const normalizeMarkers = text => text.replace(/ZXQ\s*(PH|NL)\s*(\d+)\s*QXZ/gi, (_, type, index) => 'ZXQ' + type.toUpperCase() + index + 'QXZ');
  function protect(source) {
    const tokens = [];
    const occupied = source.toUpperCase();
    let index = 0;
    const text = source.replace(protectedPattern(), original => {
      let token;
      do { token = 'ZXQ' + (/^(?:\r\n|\r|\n)$/.test(original) ? 'NL' : 'PH') + index++ + 'QXZ'; } while (occupied.includes(token));
      tokens.push({ token, original });
      return token;
    });
    return { text, tokens };
  }
  function restore(source, protectedSource, result) {
    let text = normalizeMarkers(result).replace(/\r\n|\r|\n/g, ' ').trim();
    if (JSON.stringify(markers(protectedSource.text)) !== JSON.stringify(markers(text))) throw failure('PLACEHOLDER', '备用翻译改变了占位符或换行标记，结果未保存。请重试或人工校对。');
    for (const { token, original } of protectedSource.tokens) text = text.replace(token, () => original);
    if (JSON.stringify(placeholders(source)) !== JSON.stringify(placeholders(text))) throw failure('PLACEHOLDER', '备用译文中的占位符与原文不一致，结果未保存。');
    return text;
  }
  function retryAfter(response) {
    const raw = response?.headers?.get?.('Retry-After');
    if (!raw) return 0;
    const number = Number(raw);
    if (Number.isFinite(number)) return Math.max(0, number * 1000);
    const date = Date.parse(raw);
    return Number.isFinite(date) ? Math.max(0, date - Date.now()) : 0;
  }
  function remoteFailure(status, payload, response) {
    const code = typeof payload?.code === 'string' && payload.code ? payload.code : status === 401 ? 'UNAUTHORIZED' : status === 402 ? 'TRANSLATE_BUDGET_EXCEEDED' : status === 429 ? 'RATE_LIMIT' : 'BACKUP_SERVICE';
    const messages = {
      UNAUTHORIZED: '备用翻译服务鉴权失败，请检查服务端配置。',
      BACKUP_AUTH: '备用翻译服务鉴权失败，请检查服务端配置。',
      TRANSLATE_BUDGET_EXCEEDED: '备用翻译服务的授权预算已用尽，请稍后或联系服务提供方处理。',
      BACKUP_BUDGET: '备用翻译服务的授权预算已用尽，请稍后或联系服务提供方处理。',
      TRANSLATE_DISABLED: '备用翻译服务已停用，现有译文会保留。',
      BACKUP_DISABLED: '备用翻译服务已停用，现有译文会保留。',
      TRANSLATE_NOT_CONFIGURED: '备用翻译服务尚未配置，现有译文会保留。',
      BACKUP_NOT_CONFIGURED: '备用翻译服务尚未配置，现有译文会保留。',
      BACKUP_SERVICE: '备用翻译服务暂时无法处理请求，请稍后重试。',
      BACKUP_TIMEOUT: '备用翻译请求超时，已完成的结果会保留。',
      BACKUP_ABORTED: '备用翻译已暂停，已完成的结果会保留。',
      BACKUP_RATE_LIMIT: '备用翻译请求过于频繁，请稍后重试。',
      TRANSLATE_EMPTY: '备用服务未收到可翻译文本。',
      TRANSLATE_LANG_REQUIRED: '备用服务未收到目标语言。',
      RATE_LIMIT: '备用翻译请求过于频繁，请稍后重试。'
    };
    const fatal = status === 401 || payload?.fatal === true || ['UNAUTHORIZED', 'BACKUP_AUTH', 'TRANSLATE_DISABLED', 'BACKUP_DISABLED', 'TRANSLATE_NOT_CONFIGURED', 'BACKUP_NOT_CONFIGURED'].includes(code);
    const quota = status === 402 || ['TRANSLATE_BUDGET_EXCEEDED', 'BACKUP_BUDGET'].includes(code);
    const neverRetry = fatal || quota || code === 'BACKUP_ABORTED';
    const retryable = !neverRetry && payload?.retryable !== false && (status >= 500 || status === 408 || status === 425 || status === 429 || ['BACKUP_TIMEOUT', 'BACKUP_SERVICE', 'BACKUP_RATE_LIMIT'].includes(code));
    const bodyDelay = Number.isFinite(payload?.retryAfterMs) && payload.retryAfterMs >= 0 ? payload.retryAfterMs : 0;
    return failure(code, messages[code] || (status >= 500 ? '备用翻译服务暂时无法处理请求，请稍后重试。' : '备用翻译请求失败，请检查原文与目标语言。'), { status, retryable, fatal, quota, retryAfterMs: Math.max(retryAfter(response), bodyDelay) });
  }
  function createBackupClient(options = {}) {
    const endpoint = options.endpoint ?? '/api/translation/backup';
    if (typeof endpoint !== 'string' || !/^\/(?!\/)/.test(endpoint) || /[\\\r\n#]/.test(endpoint)) throw new TypeError('备用翻译必须使用同源服务端接口。');
    const fetchImpl = options.fetchImpl || ((...args) => fetch(...args));
    const sleepImpl = options.sleep || sleep;
    const timeoutMs = Math.max(1, options.timeoutMs ?? 620000);
    const maxRetries = Math.min(1, Math.max(0, options.maxRetries ?? 1));
    const maxCacheEntries = Math.max(1, Math.min(2000, options.maxCacheEntries ?? 256));
    const cache = new Map();
    function remember(key, text) {
      cache.delete(key); cache.set(key, text);
      while (cache.size > maxCacheEntries) cache.delete(cache.keys().next().value);
    }
    async function request(content, locale, signal, counts) {
      checkAbort(signal);
      const controller = new AbortController();
      let timedOut = false;
      const onAbort = () => controller.abort();
      signal?.addEventListener('abort', onAbort, { once: true });
      if (signal?.aborted) controller.abort();
      const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeoutMs);
      counts.requestCount++;
      try {
        const response = await withAbort(fetchImpl(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' }, credentials: 'same-origin', cache: 'no-store', referrerPolicy: 'same-origin', body: JSON.stringify({ content, locale }), signal: controller.signal }), controller.signal);
        let payload;
        try { payload = await withAbort(response.json(), controller.signal); }
        catch (error) { if (controller.signal.aborted) throw error; payload = null; }
        const status = Number(response?.status ?? 200);
        if (response?.ok === false || status >= 400 || payload?.code) throw remoteFailure(status, payload, response);
        if (typeof payload?.text !== 'string' || payload.provider && payload.provider !== PROVIDER) throw failure('RESPONSE', '备用服务返回了无法识别的结果，未保存为译文。');
        const text = payload.text;
        if (!text.trim() || /^(?:\.{3}|…|<译文>)$/u.test(text.trim()) || /^\s*(?:MYMEMORY WARNING:|<!doctype html|<html(?:\s|>)|Internal Server Error\s*$|UNAUTHORIZED\s*$|TRANSLATE_[A-Z_]+\s*$)/i.test(text)) throw failure('EMPTY_RESULT', '备用服务没有返回有效译文，原有内容已保留。');
        checkAbort(signal);
        return text;
      } catch (error) {
        if (signal?.aborted) throw aborted();
        if (timedOut) throw failure('TIMEOUT', '备用翻译请求超时，已完成的结果会保留。', { retryable: true });
        if (error?.name === 'TranslationError' || error?.code === 'BACKUP_ABORTED') throw error;
        if (isAbort(error)) throw aborted();
        throw failure('NETWORK', '无法连接备用翻译服务，请检查网络后重试。', { retryable: true });
      } finally { clearTimeout(timer); signal?.removeEventListener('abort', onAbort); }
    }
    async function translate(value, locale, options = {}) {
      const source = String(value ?? '');
      checkAbort(options.signal);
      if (!languages.targets.some(language => language.code === locale)) throw failure('LANGUAGE', '不支持这个目标语言。');
      if (!source.trim()) return { text: source, provider: PROVIDER, cached: true, requestCount: 0 };
      const key = locale + '\0' + source;
      if (!options.bypassCache && cache.has(key)) {
        const text = cache.get(key); remember(key, text);
        notify(options.onProgress, { completed: 1, total: 1, requestCount: 0, provider: PROVIDER });
        return { text, provider: PROVIDER, cached: true, requestCount: 0 };
      }
      const [, prefix, core, suffix] = source.match(/^(\s*)([\s\S]*?)(\s*)$/u);
      const protectedSource = protect(core);
      const counts = { requestCount: 0 };
      notify(options.onProgress, { completed: 0, total: 1, requestCount: 0, provider: PROVIDER });
      for (let attempt = 0; ; attempt++) {
        checkAbort(options.signal);
        try {
          const raw = await request(protectedSource.text, locale, options.signal, counts);
          checkAbort(options.signal);
          const text = prefix + restore(core, protectedSource, raw) + suffix;
          checkAbort(options.signal);
          remember(key, text);
          notify(options.onProgress, { completed: 1, total: 1, requestCount: counts.requestCount, provider: PROVIDER });
          return { text, provider: PROVIDER, cached: false, requestCount: counts.requestCount };
        } catch (error) {
          if (options.signal?.aborted) throw aborted();
          if (isAbort(error)) throw error;
          if (!error.retryable || error.quota || attempt >= maxRetries || error.retryAfterMs > 60000) throw error;
          const delayMs = Math.max(error.retryAfterMs || 0, 1000 * 2 ** attempt);
          notify(options.onRetry, { attempt: attempt + 1, maxRetries, delayMs, code: error.code, message: error.message, provider: PROVIDER });
          await withAbort(Promise.resolve().then(() => sleepImpl(delayMs, options.signal)), options.signal);
        }
      }
    }
    return Object.freeze({ translate, clearCache: () => cache.clear() });
  }

  function createClient({ primary, backup, circuit = { until: 0 }, onFallback, now = Date.now } = {}) {
    if (!primary || typeof primary.translate !== 'function' || !backup || typeof backup.translate !== 'function') throw new TypeError('需要提供主翻译和备用翻译服务。');
    function callbacks(options, provider) {
      return { ...options,
        onProgress: value => { if (!options.signal?.aborted) notify(options.onProgress, { ...value, provider }); },
        onRetry: value => { if (!options.signal?.aborted) notify(options.onRetry, { ...value, provider }); }
      };
    }
    async function fromBackup(source, locale, options) {
      checkAbort(options.signal);
      try {
        const result = await withAbort(backup.translate(source, locale, callbacks(options, PROVIDER)), options.signal);
        checkAbort(options.signal);
        return result;
      } catch (error) { if (options.signal?.aborted) throw aborted(); if (isAbort(error)) throw error; throw providerError(error, PROVIDER); }
    }
    async function translate(source, locale, options = {}) {
      checkAbort(options.signal);
      if (!languages.targets.some(language => language.code === locale)) throw failure('LANGUAGE', '不支持这个目标语言。');
      if (languages.backupOnly.includes(locale)) return fromBackup(source, locale, options);
      if (Number(circuit.until) > now()) return fromBackup(source, locale, options);
      try {
        const result = await withAbort(primary.translate(source, locale, callbacks(options, 'MyMemory')), options.signal);
        checkAbort(options.signal);
        return result;
      } catch (error) {
        if (options.signal?.aborted || isAbort(error)) throw aborted();
        if (!(error?.quota || error?.code === 'QUOTA')) throw providerError(error, 'MyMemory');
        const time = now();
        if (!(Number(circuit.until) > time)) {
          const cooldown = Number.isFinite(error.retryAfterMs) && error.retryAfterMs > 0 ? error.retryAfterMs : 60 * 60 * 1000;
          circuit.until = time + Math.min(24 * 60 * 60 * 1000, Math.max(1000, cooldown));
          notify(onFallback, { from: 'MyMemory', to: PROVIDER, reason: error.code || 'QUOTA', until: circuit.until });
        }
        checkAbort(options.signal);
        // Translate the original whole paragraph, never join it to partial primary output.
        return fromBackup(source, locale, options);
      }
    }
    return Object.freeze({ translate });
  }
  return Object.freeze({ createBackupClient, createClient });
});
