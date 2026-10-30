(function (root) {
  'use strict';

  const running = new WeakMap();
  const providers = root.LangPackProviders || (typeof module === 'object' && module.exports ? require('./providers.js') : null);
  const providerOf = value => providers.known(value) ? value : null;
  const textOf = value => value && typeof value === 'object' ? String(value.text ?? '') : String(value ?? '');
  const versionOf = entry => entry.sourceVersion ?? 1;
  const revisionOf = (entry, locale) => entry.translationRevision?.[locale] ?? 0;
  const isManual = (entry, locale) => !!(entry.edited?.[locale] || entry.reviewed?.[locale]);
  const isCurrent = (entry, item) => !!entry && String(entry.source ?? '') === item.source && versionOf(entry) === item.sourceVersion;
  const placeholders = value => (String(value).match(/\{\{\s*[\w.]+\s*\}\}|\{[\w.]+\}|%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdif@uoxXegGc]|%%/g) || []).map(token => token.replace(/\s+/g, '')).sort();
  const reusable = (entry, item) => {
    const meta = entry.translationMeta?.[item.locale];
    const text = textOf(entry.translations?.[item.locale]);
    return !entry.edited?.[item.locale] && providerOf(meta?.provider) && meta.status === 'success' && entry.source === item.source && meta.sourceText === item.source && (meta.sourceVersion == null || meta.sourceVersion === versionOf(entry)) && text.trim() !== '' && JSON.stringify(placeholders(item.source)) === JSON.stringify(placeholders(text));
  };
  function memoryFor(source, locale, entries) {
    let found;
    for (const entry of entries) {
      if (!reusable(entry, { source, locale })) continue;
      const candidate = { text: textOf(entry.translations[locale]), meta: entry.translationMeta[locale], entryId: entry.id };
      // Identical source text may have deliberately different contextual translations.
      if (found && found.text !== candidate.text) return null;
      found = candidate;
    }
    return found;
  }
  function copyMemory(entry, item, memory) {
    entry.translations ||= {}; entry.translationMeta ||= {}; entry.reviewed ||= {};
    entry.translations[item.locale] = memory.text;
    entry.reviewed[item.locale] = false;
    entry.translationMeta[item.locale] = { ...memory.meta, sourceText: item.source, sourceVersion: item.sourceVersion, cached: true, reusedFrom: memory.entryId };
    Object.assign(item, { status: 'success', reused: true, provider: memory.meta.provider, cached: true, requestCount: 0 });
  }
  function plan({ entries = [], locales = [], memoryEntries = [] } = {}) {
    const active = entries.filter(entry => entry.selected !== false);
    const memory = [...memoryEntries, ...active];
    const pending = new Map();
    const result = { total: 0, reused: 0, protected: 0, pending: 0, uniquePending: 0, duplicatePending: 0, characters: 0 };
    for (const locale of new Set(locales)) for (const entry of active) {
      result.total++;
      if (isManual(entry, locale)) result.protected++;
      else if (reusable(entry, { source: entry.source, locale })) result.reused++;
      else {
        const candidate = memoryFor(entry.source, locale, memory);
        if (candidate) result.reused++;
        else {
          result.pending++;
          pending.set(JSON.stringify([locale, entry.source]), entry.source);
        }
      }
    }
    result.uniquePending = pending.size;
    result.duplicatePending = result.pending - pending.size;
    result.characters = [...pending.values()].reduce((sum, source) => sum + source.length, 0);
    return result;
  }
  const now = () => new Date().toISOString();
  function errorInfo(error, fallbackProvider) {
    return { code: String(error?.code || 'TRANSLATION_FAILED'), message: String(error?.message || '翻译失败，请稍后重试。'), provider: providerOf(error?.provider) || providerOf(fallbackProvider) || 'Unknown', retryable: !!error?.retryable, fatal: !!error?.fatal, quota: !!error?.quota || error?.code === 'QUOTA' || error?.code === 'QUOTA_EXCEEDED' };
  }
  function summary(job) {
    const result = { total: job.items.length, processed: 0, success: 0, failed: 0, pending: 0, skipped: 0, ratio: 0 };
    job.items.forEach(item => {
      if (item.status === 'success' || item.status === 'failed' || item.status === 'skipped') { result[item.status]++; result.processed++; }
      else result.pending++;
    });
    result.ratio = result.total ? Math.round(result.processed / result.total * 100) : 0;
    return result;
  }
  function sync(job) {
    const counts = summary(job);
    Object.assign(job, { total: counts.total, processed: counts.processed, success: counts.success, failed: counts.failed, skipped: counts.skipped });
  }
  function createJob({ id, projectId, projectName, entries, locales, sourceLocale = 'zh-Hans', memoryEntries = [], createdAt, provider = 'TranslationChain' }) {
    const active = (entries || []).filter(entry => entry.selected !== false);
    const targets = [...new Set(locales || [])];
    const job = {
      id, projectId, projectName, entries: active, locales: targets, sourceLocale,
      provider: provider === 'TranslationChain' || providers.known(provider) ? provider : 'TranslationChain', count: active.length, status: 'pending',
      createdAt: createdAt || now(), activeItem: null,
      plan: plan({ entries: active, locales: targets, memoryEntries }),
      items: targets.flatMap(locale => active.map(entry => {
        const item = { entryId: entry.id, locale, source: String(entry.source ?? ''), sourceVersion: versionOf(entry), status: 'pending', attempts: 0 };
        if (isManual(entry, locale)) { item.status = 'skipped'; item.reason = 'manual'; }
        else if (reusable(entry, item)) { item.status = 'success'; item.reused = true; item.provider = entry.translationMeta[locale].provider; }
        else {
          const memory = memoryFor(item.source, locale, [...memoryEntries, ...active]);
          if (memory) copyMemory(entry, item, memory);
        }
        return item;
      }))
    };
    sync(job);
    return job;
  }
  function normalize(job) {
    job.items.forEach(item => { if (item.status === 'running') item.status = 'pending'; });
    if (job.status === 'running') job.status = 'paused';
    job.activeItem = null;
    sync(job);
    return job;
  }
  function retryFailed(job) {
    if (running.has(job) && !running.get(job).signal?.aborted) throw Object.assign(new Error('任务仍在执行，请先暂停。'), { code: 'BUSY' });
    job.items.forEach(item => {
      if (item.status === 'failed' || item.status === 'running') { item.status = 'pending'; delete item.error; delete item.reason; delete item.provider; }
    });
    if (job.items.some(item => item.status === 'pending')) job.status = 'paused';
    job.activeItem = null;
    sync(job);
    return job;
  }
  async function run(job, { entries = job.entries, memoryEntries = [], client, signal, onChange } = {}) {
    if (!client || typeof client.translate !== 'function') throw new TypeError('需要提供翻译服务。');
    if (running.has(job) && !running.get(job).signal?.aborted) throw Object.assign(new Error('任务已经在执行。'), { code: 'BUSY' });
    const token = { signal };
    running.set(job, token);
    const owns = () => running.get(job) === token;
    const findEntry = item => entries.find(entry => entry.id === item.entryId);
    const freshResults = new Map();
    const memoryKey = item => JSON.stringify([item.locale, item.source]);
    const freshMemory = item => {
      const saved = freshResults.get(memoryKey(item));
      const donor = saved && entries.find(entry => entry.id === saved.entryId);
      if (!donor || versionOf(donor) !== saved.sourceVersion || revisionOf(donor, item.locale) !== saved.revision || !reusable(donor, item) || textOf(donor.translations[item.locale]) !== saved.text) return null;
      return { text: saved.text, meta: donor.translationMeta[item.locale], entryId: donor.id };
    };
    const notify = item => { if (!owns()) return; sync(job); if (onChange) onChange(job, item); };
    const fail = (item, entry, error, writeMeta = true) => {
      item.status = 'failed'; item.error = errorInfo(error, job.activeItem?.provider); item.provider = item.error.provider; item.finishedAt = now();
      if (entry && writeMeta) {
        entry.translationMeta = entry.translationMeta || {};
        entry.translationMeta[item.locale] = { provider: item.error.provider, status: 'failed', sourceText: item.source, sourceVersion: item.sourceVersion, error: { ...item.error } };
      }
    };
    const skip = (item, reason) => { item.status = 'skipped'; item.reason = reason; delete item.error; };
    const abort = item => {
      if (!owns()) return;
      if (item?.status === 'running') item.status = 'pending';
      job.status = 'paused'; job.activeItem = null; notify(item);
    };
    try {
      job.status = 'running';
      job.activeItem = null;
      notify();
      for (const item of job.items) {
        if (!owns()) return job;
        if (signal?.aborted) { abort(item); return job; }
        if (item.status !== 'pending') continue;
        let entry = findEntry(item);
        if (!isCurrent(entry, item)) { fail(item, entry, { code: 'STALE', message: '原文已更新，请重新创建翻译任务。' }, false); notify(item); continue; }
        if (isManual(entry, item.locale)) { skip(item, 'manual'); notify(item); continue; }
        if (reusable(entry, item)) { item.status = 'success'; item.reused = true; item.provider = entry.translationMeta[item.locale].provider; notify(item); continue; }
        const memory = freshMemory(item) || memoryFor(item.source, item.locale, [...memoryEntries, ...entries]);
        if (memory) { copyMemory(entry, item, memory); notify(item); continue; }
        const revision = revisionOf(entry, item.locale);
        item.status = 'running'; item.attempts = (item.attempts || 0) + 1;
        delete item.error;
        delete item.provider;
        const activity = { entryId: item.entryId, locale: item.locale, key: entry.key, provider: null, completed: 0, total: 0, progress: null, retry: null };
        job.activeItem = activity;
        notify(item);
        try {
          if (!owns()) return job;
          if (signal?.aborted) { abort(item); return job; }
          const result = await client.translate(item.source, item.locale, {
            sourceLocale: job.sourceLocale === 'en' ? 'en' : 'zh-Hans',
            signal,
            onProgress: progress => {
              if (!owns() || signal?.aborted || item.status !== 'running' || job.activeItem !== activity) return;
              if (providerOf(progress.provider)) activity.provider = progress.provider;
              activity.progress = progress; activity.completed = progress.completed ?? 0; activity.total = progress.total ?? 0; activity.requestCount = progress.requestCount ?? 0; activity.retry = null; notify(item);
            },
            onRetry: retry => {
              if (!owns() || signal?.aborted || item.status !== 'running' || job.activeItem !== activity) return;
              if (providerOf(retry.provider)) activity.provider = retry.provider;
              activity.retry = retry; notify(item);
            }
          });
          // A service implementation may ignore AbortSignal and return late.
          if (!owns()) return job;
          if (signal?.aborted) { abort(item); return job; }
          entry = findEntry(item);
          if (!isCurrent(entry, item)) { fail(item, entry, { code: 'STALE', message: '原文已更新，旧翻译结果未覆盖新内容。' }, false); }
          else if (isManual(entry, item.locale) || revisionOf(entry, item.locale) !== revision) { skip(item, 'edited_during_request'); }
          else {
            if (typeof result?.text !== 'string' || !result.text.trim()) throw Object.assign(new Error('翻译服务返回空结果。'), { code: 'EMPTY_RESULT' });
            const provider = result.provider == null ? 'MyMemory' : providerOf(result.provider);
            if (!provider) throw Object.assign(new Error('翻译服务返回了无法识别的来源，结果未保存。'), { code: 'INVALID_PROVIDER' });
            entry.translations = entry.translations || {};
            entry.translationMeta = entry.translationMeta || {};
            entry.reviewed = entry.reviewed || {};
            entry.translations[item.locale] = result.text;
            entry.reviewed[item.locale] = false;
            const translatedAt = now();
            entry.translationMeta[item.locale] = { provider, status: 'success', sourceText: item.source, sourceVersion: item.sourceVersion, translatedAt, cached: !!result.cached };
            Object.assign(item, { status: 'success', provider, translatedAt, cached: !!result.cached, requestCount: result.requestCount || 0 });
            delete item.reused;
            freshResults.set(memoryKey(item), { entryId: entry.id, sourceVersion: versionOf(entry), revision: revisionOf(entry, item.locale), text: result.text });
          }
        } catch (error) {
          if (!owns()) return job;
          if (signal?.aborted || error?.name === 'AbortError' || error?.code === 'ABORTED') { abort(item); return job; }
          entry = findEntry(item);
          if (!isCurrent(entry, item)) fail(item, entry, { code: 'STALE', message: '原文已更新，请重新创建翻译任务。' }, false);
          else if (isManual(entry, item.locale) || revisionOf(entry, item.locale) !== revision) skip(item, 'edited_during_request');
          else fail(item, entry, error);
          const failure = errorInfo(error, job.activeItem?.provider);
          if (failure.quota) {
            job.status = 'quota'; job.activeItem = null;
            job.error = failure; notify(item); return job;
          }
          if (failure.fatal) {
            job.status = 'blocked'; job.activeItem = null;
            job.error = failure; notify(item); return job;
          }
        }
        job.activeItem = null;
        notify(item);
      }
      job.status = 'completed'; job.completedAt = now(); job.activeItem = null; delete job.error;
      notify();
      return job;
    } finally {
      if (owns()) running.delete(job);
    }
  }
  const api = { createJob, run, summary, retryFailed, normalize, plan };
  root.LangPackJobs = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
