/* MyMemory REST adapter. No credentials, demo translations or public-memory writes. */
(function (root, factory) {
  'use strict';
  const api = factory();
  root.MyMemoryTranslator = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis, function () {
  'use strict';
  const ENDPOINT = 'https://api.mymemory.translated.net/get';
  const LANGUAGES = Object.freeze({ en: 'en', ja: 'ja', ko: 'ko', fr: 'fr', de: 'de', es: 'es', 'zh-Hant': 'zh-TW' });
  const encoder = new TextEncoder();
  const placeholderPattern = () => /\{\{\s*[\w.]+\s*\}\}|\{[\w.]+\}|%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdif@uoxXegGc]|%%/g;
  const utf8Length = text => encoder.encode(String(text)).length;

  function error(code, message, options) {
    const result = new Error(message);
    result.name = code === 'ABORTED' ? 'AbortError' : 'TranslationError';
    result.code = code;
    result.retryable = !!options?.retryable;
    result.quota = !!options?.quota;
    if (options?.retryAfterMs != null) result.retryAfterMs = options.retryAfterMs;
    if (options?.status != null) result.status = options.status;
    return result;
  }
  function aborted() { return error('ABORTED', '翻译已暂停，已完成的结果会保留。'); }
  function throwIfAborted(signal) { if (signal?.aborted) throw aborted(); }
  function withAbort(promise, signal) {
    if (!signal) return promise;
    if (signal.aborted) return Promise.reject(aborted());
    return new Promise((resolve, reject) => {
      const onAbort = () => { signal.removeEventListener('abort', onAbort); reject(aborted()); };
      signal.addEventListener('abort', onAbort, { once: true });
      Promise.resolve(promise).then(value => { signal.removeEventListener('abort', onAbort); resolve(value); }, reason => { signal.removeEventListener('abort', onAbort); reject(reason); });
    });
  }
  function defaultSleep(ms, signal) {
    return new Promise((resolve, reject) => {
      if (signal?.aborted) return reject(aborted());
      const onAbort = () => { clearTimeout(timer); signal.removeEventListener('abort', onAbort); reject(aborted()); };
      const timer = setTimeout(() => { signal?.removeEventListener('abort', onAbort); resolve(); }, Math.max(0, ms));
      signal?.addEventListener('abort', onAbort, { once: true });
    });
  }
  function notify(callback, value) { if (typeof callback === 'function') { try { callback(value); } catch (_) { /* UI callbacks cannot invalidate a successful request. */ } } }

  /** Lossless UTF-8 chunking; sentence ends are preferred over whitespace or a hard cut. */
  function splitText(value, maxBytes = 480) {
    const text = String(value ?? '');
    if (!Number.isInteger(maxBytes) || maxBytes < 4 || maxBytes > 500) throw new RangeError('分段字节上限需介于 4 和 500 之间。');
    if (!text) return [];
    const chunks = [];
    let start = 0;
    while (start < text.length) {
      let cursor = start, bytes = 0, sentenceEnd = -1, wordEnd = -1, softEnd = -1;
      while (cursor < text.length) {
        const marker = text.slice(cursor).match(/^ZXQPH\d+QXZ/);
        const unit = marker ? marker[0] : String.fromCodePoint(text.codePointAt(cursor));
        const size = utf8Length(unit);
        if (bytes + size > maxBytes) break;
        bytes += size; cursor += unit.length;
        if (/[。！？.!?；;\r\n]$/u.test(unit)) sentenceEnd = cursor;
        else if (/[，,：:]$/u.test(unit)) softEnd = cursor;
        if (/\s$/u.test(unit)) wordEnd = cursor;
      }
      if (cursor === start) throw error('CHUNK_SIZE', '内容中的受保护标记过长，无法拆分。');
      let end = cursor;
      if (cursor < text.length) end = sentenceEnd > start ? sentenceEnd : wordEnd > start ? wordEnd : softEnd > start ? softEnd : cursor;
      chunks.push(text.slice(start, end));
      start = end;
    }
    return chunks;
  }

  function decodeEntities(value) {
    return String(value).replace(/&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/gi, entity => {
      const named = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" };
      if (named[entity.toLowerCase()]) return named[entity.toLowerCase()];
      const hex = /^&#x/i.test(entity);
      const point = Number.parseInt(entity.slice(hex ? 3 : 2, -1), hex ? 16 : 10);
      return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff) ? String.fromCodePoint(point) : entity;
    });
  }
  function placeholderList(text) { return (String(text).match(placeholderPattern()) || []).map(token => token.replace(/\s+/g, '')).sort(); }
  function protect(source) {
    const originals = [];
    // Literal marker-like source must remain distinguishable from generated markers.
    let index = 0;
    while (source.includes('ZXQPH' + index + 'QXZ')) index++;
    const text = source.replace(placeholderPattern(), original => {
      while (source.includes('ZXQPH' + index + 'QXZ')) index++;
      const token = 'ZXQPH' + index++ + 'QXZ';
      originals.push({ token, original });
      return token;
    });
    return { text, originals };
  }
  function markerList(text) { return (text.match(/ZXQPH\d+QXZ/g) || []).sort(); }
  function normalizeMarkers(text) { return text.replace(/ZXQPH\s*(\d+)\s*QXZ/gi, (_, n) => 'ZXQPH' + n + 'QXZ'); }
  function assertMarkers(source, translated) {
    if (JSON.stringify(markerList(source)) !== JSON.stringify(markerList(translated))) throw error('PLACEHOLDER', '翻译服务改变了占位符，结果未保存。请重试或手动补译。');
  }
  function quotaMessage(text) { return /used all available free translations|next available in|quota\s*(?:has been\s*)?(?:exceed|finish|exhaust)|(?:daily|free)\s+(?:translation\s+)?(?:limit|quota)\s*(?:reached|exceed|exhaust)|out of quota/i.test(text); }
  function retryAfter(response) {
    const raw = response?.headers?.get?.('Retry-After');
    if (!raw) return 0;
    const seconds = Number(raw);
    if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
    const date = Date.parse(raw);
    return Number.isFinite(date) ? Math.max(0, date - Date.now()) : 0;
  }
  function friendlyStatus(status, delay) {
    if (status === 429) return error('RATE_LIMIT', 'MyMemory 请求过于频繁，请稍后重试。', { retryable: true, retryAfterMs: delay, status });
    if (status === 408 || status === 425 || status >= 500) return error('SERVICE', 'MyMemory 暂时无法处理请求，稍后可以重试。', { retryable: true, retryAfterMs: delay, status });
    return error('REQUEST', 'MyMemory 拒绝了这条请求，请检查原文和目标语言。', { status });
  }

  function createClient(options = {}) {
    const fetchImpl = options.fetchImpl || ((...args) => fetch(...args));
    const sleepImpl = options.sleep || defaultSleep;
    const minIntervalMs = Math.max(0, options.minIntervalMs ?? 1100);
    const timeoutMs = Math.max(1, options.timeoutMs ?? 15000);
    const maxRetries = Math.min(5, Math.max(0, options.maxRetries ?? 2));
    const retryBaseMs = Math.max(0, options.retryBaseMs ?? 1000);
    const maxCacheEntries = Math.min(2000, Math.max(1, options.maxCacheEntries ?? 500));
    const email = String(options.email || '').trim();
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw error('EMAIL', '请填写有效的联系邮箱，或留空使用匿名额度。');
    const cache = new Map();
    let queue = Promise.resolve(), lastStarted = 0;
    const usage = { requestCount: 0, characters: 0, bytes: 0 };
    function cacheGet(key) {
      if (!cache.has(key)) return undefined;
      const value = cache.get(key); cache.delete(key); cache.set(key, value); return value;
    }
    function cacheSet(key, value) {
      cache.delete(key); cache.set(key, value);
      while (cache.size > maxCacheEntries) cache.delete(cache.keys().next().value);
    }
    function sleep(ms, signal) { throwIfAborted(signal); return withAbort(Promise.resolve().then(() => sleepImpl(ms, signal)), signal); }
    function enqueue(run, signal) {
      const request = queue.then(async () => {
        throwIfAborted(signal);
        const delay = lastStarted ? Math.max(0, minIntervalMs - (Date.now() - lastStarted)) : 0;
        if (delay) await sleep(delay, signal);
        throwIfAborted(signal);
        lastStarted = Date.now();
        return run();
      });
      queue = request.catch(() => {});
      return withAbort(request, signal);
    }
    async function attempt(source, locale, context) {
      const controller = new AbortController();
      let timedOut = false;
      const onAbort = () => controller.abort();
      context.signal?.addEventListener('abort', onAbort, { once: true });
      if (context.signal?.aborted) controller.abort();
      const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeoutMs);
      const query = new URLSearchParams({ q: source, langpair: 'zh-CN|' + LANGUAGES[locale], mt: '1' });
      if (email) query.set('de', email);
      usage.requestCount++; usage.characters += Array.from(source).length; usage.bytes += utf8Length(source); context.requestCount++;
      try {
        const response = await withAbort(fetchImpl(ENDPOINT + '?' + query.toString(), { method: 'GET', signal: controller.signal, credentials: 'omit', referrerPolicy: 'no-referrer' }), controller.signal);
        let payload;
        try { payload = await withAbort(response.json(), controller.signal); }
        catch (cause) { if (controller.signal.aborted) throw cause; payload = null; }
        const details = typeof payload?.responseDetails === 'string' ? payload.responseDetails : '';
        const candidate = typeof payload?.responseData?.translatedText === 'string' ? payload.responseData.translatedText : '';
        const delay = retryAfter(response);
        if ([true, 'true', 1].includes(payload?.quotaFinished) || quotaMessage(details + '\n' + candidate)) throw error('QUOTA', 'MyMemory 今日免费额度已用尽。已完成的译文已保留，请等待额度恢复后重试。', { quota: true, retryAfterMs: delay, status: 429 });
        const httpStatus = Number(response.status || 200);
        if (response.ok === false || httpStatus >= 400) throw friendlyStatus(httpStatus, delay);
        const serviceStatus = Number(payload?.responseStatus);
        if (Number.isFinite(serviceStatus) && serviceStatus !== 200) throw friendlyStatus(serviceStatus, delay);
        if (!payload || !Number.isFinite(serviceStatus)) throw error('RESPONSE', '翻译服务返回了无法识别的结果，请稍后重试。', { retryable: true });
        if (/MYMEMORY WARNING:|NO QUERY SPECIFIED|INVALID LANGPAIR|IS AN INVALID (?:TARGET|SOURCE) LANGUAGE|PLEASE SELECT TWO DISTINCT LANGUAGES/i.test(candidate)) throw error('RESPONSE', '翻译服务返回了错误提示，未将其保存为译文。');
        if (!candidate.trim()) throw error('EMPTY', '翻译服务返回了空译文，请稍后重试。', { retryable: true });
        const translated = normalizeMarkers(decodeEntities(candidate)).replace(/\r\n|\r|\n/g, ' ').trim();
        if (!translated) throw error('EMPTY', '翻译服务返回了空译文，请稍后重试。', { retryable: true });
        assertMarkers(source, translated);
        if (JSON.stringify(placeholderList(source)) !== JSON.stringify(placeholderList(translated))) throw error('PLACEHOLDER', '翻译服务新增或改变了占位符，结果未保存。请人工检查。');
        return translated;
      } catch (cause) {
        if (context.signal?.aborted) throw aborted();
        if (timedOut) throw error('TIMEOUT', '翻译请求超时，正在保留已完成的结果。', { retryable: true });
        if (cause?.name === 'TranslationError' || cause?.code === 'ABORTED') throw cause;
        if (cause?.name === 'AbortError') throw aborted();
        throw error('NETWORK', '无法连接 MyMemory，请检查网络后重试。', { retryable: true });
      } finally { clearTimeout(timer); context.signal?.removeEventListener('abort', onAbort); }
    }
    async function chunk(source, locale, context) {
      const key = locale + '\0' + source;
      if (!context.bypassCache) {
        const cached = cacheGet(key);
        if (cached !== undefined) return cached;
      }
      for (let count = 0; ; count++) {
        throwIfAborted(context.signal);
        try {
          const result = await enqueue(() => attempt(source, locale, context), context.signal);
          cacheSet(key, result);
          return result;
        } catch (cause) {
          if (context.signal?.aborted || cause.code === 'ABORTED') throw aborted();
          // A long server-requested cooldown is returned to the UI, never shortened.
          if (!cause.retryable || cause.quota || count >= maxRetries || cause.retryAfterMs > 60000) throw cause;
          const delayMs = Math.max(cause.retryAfterMs || 0, retryBaseMs * Math.pow(2, count));
          notify(context.onRetry, { attempt: count + 1, maxRetries, delayMs, code: cause.code, message: cause.message, chunkIndex: context.chunkIndex, chunkCount: context.chunkCount });
          await sleep(delayMs, context.signal);
        }
      }
    }
    async function translate(value, locale, translationOptions = {}) {
      const source = String(value ?? '');
      throwIfAborted(translationOptions.signal);
      if (!LANGUAGES[locale]) throw error('LANGUAGE', '不支持这个目标语言。');
      if (!source.trim()) return { text: source, provider: 'MyMemory', cached: true, requestCount: 0 };
      const protectedSource = protect(source);
      const parts = [];
      // Newline boundaries and leading/trailing whitespace belong to the original document.
      for (const line of protectedSource.text.split(/(\r\n|\r|\n)/)) {
        if (!line) continue;
        if (/^\s+$/u.test(line)) { parts.push({ literal: line }); continue; }
        for (const piece of splitText(line)) {
          const match = piece.match(/^(\s*)([\s\S]*?)(\s*)$/u);
          const core = match[2];
          if (!core || !core.replace(/ZXQPH\d+QXZ/g, '').replace(/[\p{P}\p{S}\s\d]/gu, '')) parts.push({ literal: piece });
          else parts.push({ prefix: match[1], source: core, suffix: match[3] });
        }
      }
      const context = { ...translationOptions, requestCount: 0, chunkIndex: 0, chunkCount: parts.filter(part => part.source).length };
      notify(context.onProgress, { completed: 0, total: context.chunkCount, requestCount: 0 });
      const output = [];
      let previousWasTranslated = false;
      for (const part of parts) {
        throwIfAborted(context.signal);
        if (part.literal !== undefined) { output.push(part.literal); previousWasTranslated = false; }
        else {
          const translated = await chunk(part.source, locale, context);
          const piece = part.prefix + translated + part.suffix;
          const tail = output[output.length - 1] || '';
          // Adjacent Chinese chunks have no source space. Word-based target scripts need one.
          const separator = previousWasTranslated && ['en', 'fr', 'de', 'es', 'ko'].includes(locale) && /[\p{L}\p{N}.!?;:)"']$/u.test(tail) && /^[\p{L}\p{N}]/u.test(piece) ? ' ' : '';
          output.push(separator + piece);
          previousWasTranslated = true;
          context.chunkIndex++;
          notify(context.onProgress, { completed: context.chunkIndex, total: context.chunkCount, requestCount: context.requestCount });
        }
      }
      let text = output.join('');
      assertMarkers(protectedSource.text, text);
      for (const item of protectedSource.originals) text = text.replace(item.token, () => item.original);
      if (JSON.stringify(placeholderList(source)) !== JSON.stringify(placeholderList(text))) throw error('PLACEHOLDER', '译文中的占位符与原文不一致，请人工检查。');
      return { text, provider: 'MyMemory', cached: context.requestCount === 0, requestCount: context.requestCount };
    }
    return Object.freeze({ translate, getUsage: () => ({ ...usage, cacheEntries: cache.size }), clearCache: () => cache.clear() });
  }
  return Object.freeze({ createClient, splitText, utf8Length, languageMap: LANGUAGES, endpoint: ENDPOINT });
});
