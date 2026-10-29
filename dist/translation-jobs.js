(function (root) {
  'use strict';

  const running = new WeakMap();
  const textOf = value => value && typeof value === 'object' ? String(value.text ?? '') : String(value ?? '');
  const versionOf = entry => entry.sourceVersion ?? 1;
  const revisionOf = (entry, locale) => entry.translationRevision?.[locale] ?? 0;
  const isManual = (entry, locale) => !!(entry.edited?.[locale] || entry.reviewed?.[locale]);
  const isCurrent = (entry, item) => !!entry && String(entry.source ?? '') === item.source && versionOf(entry) === item.sourceVersion;
  const reusable = (entry, item) => {
    const meta = entry.translationMeta?.[item.locale];
    return meta?.provider === 'MyMemory' && meta.status === 'success' && meta.sourceText === item.source && textOf(entry.translations?.[item.locale]).trim() !== '';
  };
  const now = () => new Date().toISOString();
  function errorInfo(error) {
    return { code: String(error?.code || 'TRANSLATION_FAILED'), message: String(error?.message || '翻译失败，请稍后重试。'), retryable: !!error?.retryable, quota: !!error?.quota || error?.code === 'QUOTA' || error?.code === 'QUOTA_EXCEEDED' };
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
  function createJob({ id, projectId, projectName, entries, locales, createdAt }) {
    const active = (entries || []).filter(entry => entry.selected !== false);
    const targets = [...new Set(locales || [])];
    const job = {
      id, projectId, projectName, entries: active, locales: targets,
      provider: 'MyMemory', count: active.length, status: 'pending',
      createdAt: createdAt || now(), activeItem: null,
      items: targets.flatMap(locale => active.map(entry => {
        const item = { entryId: entry.id, locale, source: String(entry.source ?? ''), sourceVersion: versionOf(entry), status: 'pending', attempts: 0 };
        if (isManual(entry, locale)) { item.status = 'skipped'; item.reason = 'manual'; }
        else if (reusable(entry, item)) { item.status = 'success'; item.reused = true; }
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
      if (item.status === 'failed' || item.status === 'running') { item.status = 'pending'; delete item.error; delete item.reason; }
    });
    if (job.items.some(item => item.status === 'pending')) job.status = 'paused';
    job.activeItem = null;
    sync(job);
    return job;
  }
  async function run(job, { entries = job.entries, client, signal, onChange } = {}) {
    if (!client || typeof client.translate !== 'function') throw new TypeError('需要提供翻译服务。');
    if (running.has(job) && !running.get(job).signal?.aborted) throw Object.assign(new Error('任务已经在执行。'), { code: 'BUSY' });
    const token = { signal };
    running.set(job, token);
    const owns = () => running.get(job) === token;
    const findEntry = item => entries.find(entry => entry.id === item.entryId);
    const notify = item => { if (!owns()) return; sync(job); if (onChange) onChange(job, item); };
    const fail = (item, entry, error, writeMeta = true) => {
      item.status = 'failed'; item.error = errorInfo(error); item.finishedAt = now();
      if (entry && writeMeta) {
        entry.translationMeta = entry.translationMeta || {};
        entry.translationMeta[item.locale] = { provider: 'MyMemory', status: 'failed', sourceText: item.source, sourceVersion: item.sourceVersion, error: { ...item.error } };
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
        if (reusable(entry, item)) { item.status = 'success'; item.reused = true; notify(item); continue; }
        const revision = revisionOf(entry, item.locale);
        item.status = 'running'; item.attempts = (item.attempts || 0) + 1;
        delete item.error;
        const activity = { entryId: item.entryId, locale: item.locale, key: entry.key, completed: 0, total: 0, progress: null, retry: null };
        job.activeItem = activity;
        notify(item);
        try {
          if (!owns()) return job;
          if (signal?.aborted) { abort(item); return job; }
          const result = await client.translate(item.source, item.locale, {
            signal,
            onProgress: progress => {
              if (!owns() || signal?.aborted || item.status !== 'running' || job.activeItem !== activity) return;
              activity.progress = progress; activity.completed = progress.completed ?? 0; activity.total = progress.total ?? 0; activity.requestCount = progress.requestCount ?? 0; notify(item);
            },
            onRetry: retry => {
              if (!owns() || signal?.aborted || item.status !== 'running' || job.activeItem !== activity) return;
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
            entry.translations = entry.translations || {};
            entry.translationMeta = entry.translationMeta || {};
            entry.reviewed = entry.reviewed || {};
            entry.translations[item.locale] = result.text;
            entry.reviewed[item.locale] = false;
            const translatedAt = now();
            entry.translationMeta[item.locale] = { provider: 'MyMemory', status: 'success', sourceText: item.source, sourceVersion: item.sourceVersion, translatedAt, cached: !!result.cached };
            Object.assign(item, { status: 'success', translatedAt, cached: !!result.cached, requestCount: result.requestCount || 0 });
            delete item.reused;
          }
        } catch (error) {
          if (!owns()) return job;
          if (signal?.aborted || error?.name === 'AbortError' || error?.code === 'ABORTED') { abort(item); return job; }
          entry = findEntry(item);
          if (!isCurrent(entry, item)) fail(item, entry, { code: 'STALE', message: '原文已更新，请重新创建翻译任务。' }, false);
          else if (isManual(entry, item.locale) || revisionOf(entry, item.locale) !== revision) skip(item, 'edited_during_request');
          else fail(item, entry, error);
          if (errorInfo(error).quota) {
            job.status = 'quota'; job.activeItem = null;
            job.error = errorInfo(error); notify(item); return job;
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
  const api = { createJob, run, summary, retryFailed, normalize };
  root.LangPackJobs = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
