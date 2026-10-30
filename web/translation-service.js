/* Browser translation chain. The authenticated backup key is held by the server only. */
(function (root, factory) {
  'use strict';
  const api = factory(root.LangPackLanguages || (typeof module === 'object' && module.exports ? require('./languages.js') : null), root.LangPackProviders || (typeof module === 'object' && module.exports ? require('./providers.js') : null));
  root.TranslationService = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis, function (languages, providers) {
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
  function providerFailure(provider, code, message, extra = {}) { return Object.assign(failure(code, message, extra), { provider }); }
  function remoteProviderFailure(provider, status, payload, response) {
    const rawCode = typeof payload?.code === 'string' ? payload.code : '';
    const messages = {
      PROVIDER_QUOTA: '这个平台的额度已用尽，已完成的译文会保留。', PROVIDER_UNSUPPORTED: '这个平台不支持所选目标语言。',
      PROVIDER_AUTH: '这个平台的凭据无效或无权使用，请检查配置。', PROVIDER_CONFIG: '请先配置这个平台的有效凭据。',
      PROVIDER_RATE_LIMIT: '这个平台请求过于频繁，请稍后重试。', PROVIDER_REQUEST: '这个平台拒绝了请求，请检查配置和内容。',
      PROVIDER_RESPONSE: '这个平台返回的结果无效，未保存为译文。', PROVIDER_SERVICE: '这个平台暂时无法提供翻译，请稍后重试。',
      PROVIDER_TIMEOUT: '这个平台翻译超时，已完成的结果会保留。', PROVIDER_ABORTED: '翻译已暂停。'
    };
    const code = Object.hasOwn(messages, rawCode) ? rawCode : status === 401 || status === 403 ? 'PROVIDER_AUTH' : status === 429 ? 'PROVIDER_RATE_LIMIT' : status >= 500 ? 'PROVIDER_SERVICE' : status >= 400 ? 'PROVIDER_REQUEST' : 'PROVIDER_RESPONSE';
    const fatal = status === 401 || status === 403 || ['PROVIDER_AUTH', 'PROVIDER_CONFIG'].includes(code);
    const quota = !fatal && code === 'PROVIDER_QUOTA';
    const unsupported = !fatal && code === 'PROVIDER_UNSUPPORTED';
    const retryable = !fatal && !quota && !unsupported && payload?.retryable !== false && ['PROVIDER_RATE_LIMIT', 'PROVIDER_SERVICE', 'PROVIDER_TIMEOUT'].includes(code);
    return providerFailure(provider, code === 'PROVIDER_ABORTED' ? 'ABORTED' : code, messages[code] || '翻译请求失败，现有内容已保留。', { fatal, quota, unsupported, retryable, retryAfterMs: Math.max(retryAfter(response), Number.isFinite(payload?.retryAfterMs) ? Math.max(0, payload.retryAfterMs) : 0) });
  }
  function splitProviderText(value, maximum = 4000, utf8 = false) {
    const units = String(value).match(/ZXQ(?:PH|NL)\d+QXZ|[\s\S]/gu) || [];
    const encoder = utf8 ? new TextEncoder() : null;
    const size = unit => encoder ? encoder.encode(unit).length : Array.from(unit).length;
    const chunks = []; let start = 0;
    while (start < units.length) {
      let cursor = start, count = 0, boundary = -1;
      while (cursor < units.length && count + size(units[cursor]) <= maximum) {
        count += size(units[cursor]);
        if (/[。！？.!?；;，,\s]$/u.test(units[cursor])) boundary = cursor + 1;
        cursor++;
      }
      if (cursor === start) throw failure('PROVIDER_REQUEST', '受保护标记过长，无法安全拆分。');
      const end = cursor < units.length && boundary > start ? boundary : cursor;
      chunks.push(units.slice(start, end).join('')); start = end;
    }
    return chunks;
  }
  function createProviderClient({ provider, getCredentials = () => ({}), getRevision = () => 0, fetchImpl = (...args) => fetch(...args), sleep: sleepImpl = sleep, maxRetries = 1, timeoutMs = provider === 'ZTAITrans' ? 620000 : 65000, maxCacheEntries = 256 } = {}) {
    if (!providers.known(provider)) throw new TypeError('请选择已支持的翻译平台。');
    const cache = new Map();
    const remember = (key, text) => { cache.delete(key); cache.set(key, text); while (cache.size > Math.max(1, maxCacheEntries)) cache.delete(cache.keys().next().value); };
    async function translate(value, locale, options = {}) {
      const source = String(value ?? ''); checkAbort(options.signal);
      if (!languages.targets.some(language => language.code === locale)) throw providerFailure(provider, 'PROVIDER_UNSUPPORTED', '不支持这个目标语言。', { unsupported: true });
      const credentials = providers.cleanCredentials(provider, getCredentials());
      if (!providers.configured(provider, credentials) || provider === 'MyMemory' && !credentials.apiKey) throw providerFailure(provider, 'PROVIDER_CONFIG', '请先在设置中填写这个平台的凭据。', { fatal: true });
      const revision = getRevision(); let requestCount = 0;
      const ensureCurrent = () => { checkAbort(options.signal); if (getRevision() !== revision) throw providerFailure(provider, 'PROVIDER_CONFIG', '平台配置已改变，请重新开始或继续任务。', { fatal: true }); };
      async function request(content, cacheScope) {
        ensureCurrent();
        const key = JSON.stringify([provider, revision, locale, cacheScope, content]);
        if (!options.bypassCache && cache.has(key)) { const text = cache.get(key); remember(key, text); return text; }
        for (let attempt = 0; ; attempt++) {
          ensureCurrent(); const controller = new AbortController(); let timedOut = false;
          const onAbort = () => controller.abort(); options.signal?.addEventListener('abort', onAbort, { once: true });
          const timer = setTimeout(() => { timedOut = true; controller.abort(); }, Math.max(1, timeoutMs));
          try {
            const body = JSON.stringify({ provider, content, locale, credentials });
            if (new TextEncoder().encode(body).length > 256 * 1024) throw providerFailure(provider, 'PROVIDER_REQUEST', '翻译请求过大，请拆分原文。');
            requestCount++;
            const response = await withAbort(fetchImpl('/api/translation/provider', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, credentials: 'same-origin', cache: 'no-store', referrerPolicy: 'no-referrer', body, signal: controller.signal }), controller.signal);
            let payload; try { payload = await withAbort(response.json(), controller.signal); } catch (cause) { if (controller.signal.aborted) throw cause; payload = null; }
            const status = Number(response.status || 200);
            if (response.ok === false || status >= 400 || payload?.code) throw remoteProviderFailure(provider, status, payload, response);
            if (payload?.provider !== provider || typeof payload?.text !== 'string' || !payload.text.trim() || /^\s*(?:MYMEMORY WARNING:|<!doctype|<html|UNAUTHORIZED\s*$)/i.test(payload.text) || [credentials.apiKey, credentials.developerToken, credentials.secretKey, credentials.accessKeySecret].some(secret => secret && payload.text.includes(secret))) throw providerFailure(provider, 'PROVIDER_RESPONSE', '平台未返回有效译文，原有内容已保留。');
            const text = normalizeMarkers(payload.text).replace(/\r\n|\r|\n/g, ' ');
            if (JSON.stringify(markers(content)) !== JSON.stringify(markers(text))) throw providerFailure(provider, 'PLACEHOLDER', '翻译改变了占位符或换行标记，结果未保存。');
            ensureCurrent(); remember(key, text); return text;
          } catch (cause) {
            ensureCurrent();
            const error = timedOut ? providerFailure(provider, 'PROVIDER_TIMEOUT', '翻译请求超时，已完成结果会保留。', { retryable: true }) : cause?.name === 'TranslationError' || cause?.name === 'AbortError' ? cause : providerFailure(provider, 'PROVIDER_SERVICE', '无法连接翻译服务，请检查网络。', { retryable: true });
            if (isAbort(error) || !error.retryable || error.fatal || error.quota || attempt >= Math.min(2, Math.max(0, maxRetries)) || error.retryAfterMs > 60000) throw error;
            const delayMs = Math.max(error.retryAfterMs || 0, 1000 * 2 ** attempt);
            notify(options.onRetry, { provider, attempt: attempt + 1, delayMs, code: error.code });
            await withAbort(sleepImpl(delayMs, options.signal), options.signal);
          } finally { clearTimeout(timer); options.signal?.removeEventListener('abort', onAbort); }
        }
      }
      if (!source.trim()) return { text: source, provider, cached: true, requestCount: 0 };
      if (provider === 'ZTAITrans') {
        const [, prefix, core, suffix] = source.match(/^(\s*)([\s\S]*?)(\s*)$/u), protectedSource = protect(core);
        notify(options.onProgress, { provider, completed: 0, total: 1, requestCount });
        const text = prefix + restore(core, protectedSource, await request(protectedSource.text, source)) + suffix;
        ensureCurrent(); notify(options.onProgress, { provider, completed: 1, total: 1, requestCount });
        return { text, provider, requestCount, cached: requestCount === 0 };
      }
      const parts = [];
      for (const line of source.split(/(\r\n|\r|\n)/)) {
        if (!line.trim()) { parts.push({ literal: line }); continue; }
        const [, prefix, core, suffix] = line.match(/^(\s*)([\s\S]*?)(\s*)$/u), protectedSource = protect(core);
        const maximum = provider === 'MyMemory' ? 480 : ['Baidu', 'Tencent', 'Alibaba'].includes(provider) ? 1000 : 4000;
        parts.push({ prefix, suffix, core, protectedSource, chunks: splitProviderText(protectedSource.text, maximum, provider === 'MyMemory') });
      }
      const total = parts.reduce((sum, part) => sum + (part.chunks?.length || 0), 0); let completed = 0, output = '';
      notify(options.onProgress, { provider, completed, total, requestCount });
      for (const part of parts) {
        if (part.literal !== undefined) { output += part.literal; continue; }
        let line = '';
        for (let index = 0; index < part.chunks.length; index++) {
          const chunk = part.chunks[index], [, prefix, core, suffix] = chunk.match(/^(\s*)([\s\S]*?)(\s*)$/u);
          const literal = !core.replace(/ZXQ(?:PH|NL)\d+QXZ/g, '').replace(/[\p{P}\p{S}\s\d]/gu, '');
          const text = literal ? chunk : prefix + await request(core, '') + suffix;
          line += text; completed++;
          notify(options.onProgress, { provider, completed, total, requestCount });
        }
        output += part.prefix + restore(part.core, part.protectedSource, line) + part.suffix;
      }
      ensureCurrent();
      return { text: output, provider, requestCount, cached: requestCount === 0 };
    }
    return Object.freeze({ translate, clearCache: () => cache.clear() });
  }
  function createOrderedClient({ order = ['MyMemory'], fallback = true, clients = {}, circuits = {}, now = Date.now, onFallback } = {}) {
    const selected = providers.normalizeOrder(order);
    async function translate(source, locale, options = {}) {
      checkAbort(options.signal);
      if (!languages.targets.some(language => language.code === locale)) throw failure('PROVIDER_UNSUPPORTED', '不支持这个目标语言。', { unsupported: true });
      let lastError, previous;
      for (const provider of (fallback ? selected : selected.slice(0, 1))) {
        checkAbort(options.signal);
        if (!providers.supports(provider, locale)) { lastError = providerFailure(provider, 'PROVIDER_UNSUPPORTED', '这个平台不支持所选目标语言。', { unsupported: true }); previous = { from: provider, reason: 'unsupported' }; continue; }
        const circuit = circuits[provider] ||= { until: 0 };
        if (Number(circuit.until) > now()) { lastError = providerFailure(provider, 'PROVIDER_QUOTA', '这个平台的额度尚未恢复。', { quota: true, retryAfterMs: circuit.until - now() }); previous = { from: provider, reason: 'quota', until: circuit.until }; continue; }
        if (!clients[provider]?.translate) throw providerFailure(provider, 'PROVIDER_CONFIG', '请先配置所选平台。', { fatal: true });
        if (previous) notify(onFallback, { ...previous, to: provider });
        try {
          const result = await clients[provider].translate(source, locale, { ...options, onProgress: value => notify(options.onProgress, { ...value, provider }), onRetry: value => notify(options.onRetry, { ...value, provider }) });
          checkAbort(options.signal);
          if (result?.provider !== provider) throw providerFailure(provider, 'PROVIDER_RESPONSE', '翻译平台来源不匹配，结果未保存。');
          return result;
        } catch (error) {
          checkAbort(options.signal); if (isAbort(error) || error.fatal || !(error.quota || error.unsupported)) throw providerError(error, provider);
          lastError = providerError(error, provider);
          if (error.quota) { circuit.until = now() + Math.min(86400000, Math.max(1000, error.retryAfterMs > 0 ? error.retryAfterMs : 3600000)); previous = { from: provider, reason: 'quota', until: circuit.until }; }
          else previous = { from: provider, reason: 'unsupported' };
        }
      }
      throw lastError || providerFailure(selected[0] || 'MyMemory', 'PROVIDER_CONFIG', '请先选择翻译平台。', { fatal: true });
    }
    return Object.freeze({ translate });
  }
  return Object.freeze({ createBackupClient, createClient, createProviderClient, createOrderedClient, splitProviderText });
});
