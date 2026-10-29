const { test } = require('node:test');
const assert = require('node:assert/strict');
const Jobs = require('../web/translation-jobs.js');

function entry(id, source = '登录') { return { id, key: 'key_' + id, source, sourceVersion: 1, selected: true, translations: {}, reviewed: {}, edited: {} }; }
function jobFor(entries, locales = ['en', 'ja']) { return Jobs.createJob({ id: 'job', projectId: 'p', projectName: '项目', entries, locales }); }
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }

test('mixed success and failure retain old text; retry only failed cells', async () => {
  const rows = [entry('a'), entry('b', '注册')];
  rows[1].translations.ja = '旧版示例';
  const job = jobFor(rows);
  let shouldFail = true;
  const calls = [];
  const client = { async translate(source, locale) { calls.push([source, locale]); if (shouldFail && source === '注册' && locale === 'ja') throw Object.assign(new Error('临时失败'), { code: 'NETWORK', retryable: true }); return { text: locale + ':' + source, provider: 'MyMemory' }; } };
  await Jobs.run(job, { client });
  assert.deepEqual(Jobs.summary(job), { total: 4, processed: 4, success: 3, failed: 1, pending: 0, skipped: 0, ratio: 100 });
  assert.equal(rows[1].translations.ja, '旧版示例');
  assert.equal(rows[1].translationMeta.ja.status, 'failed');
  assert.equal(job.status, 'completed');
  shouldFail = false; Jobs.retryFailed(job);
  assert.equal(Jobs.summary(job).pending, 1);
  await Jobs.run(job, { client });
  assert.equal(calls.length, 5);
  assert.equal(Jobs.summary(job).success, 4);
  assert.equal(rows[1].translations.ja, 'ja:注册');
});

test('quota failure stops remaining requests and leaves pending cells', async () => {
  const rows = [entry('a'), entry('b')]; const job = jobFor(rows);
  let calls = 0;
  await Jobs.run(job, { client: { async translate() { calls++; throw Object.assign(new Error('今日额度用尽'), { code: 'QUOTA', quota: true }); } } });
  assert.equal(calls, 1); assert.equal(job.status, 'quota');
  assert.equal(Jobs.summary(job).failed, 1); assert.equal(Jobs.summary(job).pending, 3);
  Jobs.retryFailed(job); assert.equal(Jobs.summary(job).pending, 4);
});

test('aborted request returning late cannot write result', async () => {
  const rows = [entry('a')], job = jobFor(rows, ['en']), controller = new AbortController(), pending = deferred();
  const request = Jobs.run(job, { signal: controller.signal, client: { translate() { return pending.promise; } } });
  assert.equal(job.items[0].status, 'running');
  controller.abort(); pending.resolve({ text: 'late' });
  await request;
  assert.equal(rows[0].translations.en, undefined); assert.equal(job.status, 'paused'); assert.equal(job.items[0].status, 'pending');
});

test('AbortError is a pause rather than a failed translation', async () => {
  const job = jobFor([entry('a')], ['en']);
  await Jobs.run(job, { client: { async translate() { throw Object.assign(new Error('canceled'), { name: 'AbortError' }); } } });
  assert.equal(job.status, 'paused'); assert.equal(Jobs.summary(job).failed, 0); assert.equal(Jobs.summary(job).pending, 1);
});

test('manual and reviewed cells are protected; valid real result is reused', async () => {
  const rows = [entry('a'), entry('b'), entry('c')];
  rows[0].edited.en = true; rows[0].translations.en = '人工';
  rows[1].reviewed.en = true; rows[1].translations.en = '已确认';
  rows[2].translations.en = 'Log in'; rows[2].translationMeta = { en: { provider: 'MyMemory', status: 'success', sourceText: '登录' } };
  const job = jobFor(rows, ['en']);
  await Jobs.run(job, { client: { async translate() { assert.fail('No request should be made'); } } });
  assert.equal(Jobs.summary(job).skipped, 2); assert.equal(Jobs.summary(job).success, 1); assert.equal(job.items[2].reused, true);
  assert.equal(rows[0].translations.en, '人工'); assert.equal(rows[1].translations.en, '已确认');
});

test('legacy demo text is translated rather than reused', async () => {
  const row = entry('a'); row.translations.en = 'Demo'; row.translationMeta = { en: { provider: 'demo', status: 'success', sourceText: row.source } };
  let calls = 0; const job = jobFor([row], ['en']);
  await Jobs.run(job, { client: { async translate() { calls++; return { text: 'Actual' }; } } });
  assert.equal(calls, 1); assert.equal(row.translations.en, 'Actual'); assert.equal(row.translationMeta.en.provider, 'MyMemory');
});

test('manual edit or revision change during request cannot be overwritten', async t => {
  for (const change of [row => { row.edited.en = true; }, row => { row.translationRevision = { en: 1 }; }, row => { row.reviewed.en = true; }]) {
    await t.test('race', async () => {
      const row = entry('a'), job = jobFor([row], ['en']), pending = deferred();
      const request = Jobs.run(job, { client: { translate: () => pending.promise } });
      row.translations.en = '用户刚保存'; change(row); pending.resolve({ text: 'late response' }); await request;
      assert.equal(row.translations.en, '用户刚保存'); assert.equal(job.items[0].status, 'skipped'); assert.equal(row.translationMeta?.en, undefined);
    });
  }
});

test('source text and source version changes are stale even if API succeeds', async t => {
  for (const change of [row => { row.source = '注册'; }, row => { row.sourceVersion = 2; }]) {
    await t.test('source update', async () => {
      const row = entry('a'), job = jobFor([row], ['en']), pending = deferred();
      const request = Jobs.run(job, { client: { translate: () => pending.promise } });
      change(row); row.translations.en = '新版本'; row.translationMeta = { en: { provider: 'manual', status: 'success' } }; pending.resolve({ text: '旧请求' }); await request;
      assert.equal(row.translations.en, '新版本'); assert.equal(row.translationMeta.en.provider, 'manual'); assert.equal(job.items[0].error.code, 'STALE');
    });
  }
});

test('refresh normalizes running work to pending and retains successful cells', async () => {
  const rows = [entry('a'), entry('b')]; const job = jobFor(rows, ['en']);
  job.items[0].status = 'success'; job.items[1].status = 'running'; job.status = 'running'; job.activeItem = {};
  Jobs.normalize(job);
  assert.equal(job.status, 'paused'); assert.equal(job.activeItem, null); assert.equal(job.items[0].status, 'success'); assert.equal(job.items[1].status, 'pending');
  let calls = 0; await Jobs.run(job, { client: { async translate() { calls++; return { text: 'Result' }; } } });
  assert.equal(calls, 1); assert.equal(Jobs.summary(job).success, 2);
});

test('entry replacements in explicit array are resolved after await', async () => {
  const rows = [entry('a')], job = jobFor(rows, ['en']), pending = deferred();
  const request = Jobs.run(job, { entries: rows, client: { translate: () => pending.promise } });
  const replacement = entry('a'); replacement.translationRevision = { en: 2 }; replacement.translations.en = '新对象人工内容'; rows[0] = replacement;
  pending.resolve({ text: 'late' }); await request;
  assert.equal(rows[0].translations.en, '新对象人工内容'); assert.equal(job.items[0].status, 'skipped');
});

test('chunk and retry progress are surfaced; late callbacks ignored', async () => {
  const row = entry('a'), job = jobFor([row], ['en']); let callbacks, notifications = 0, seen;
  await Jobs.run(job, { onChange(current) { notifications++; if (current.activeItem?.progress) seen = current.activeItem.progress; }, client: { async translate(source, locale, options) { callbacks = options; options.onProgress({ completed: 1, total: 2 }); options.onRetry({ attempt: 1, delayMs: 200 }); return { text: 'Log in', cached: true, requestCount: 2 }; } } });
  assert.deepEqual(seen, { completed: 1, total: 2 }); const before = notifications; callbacks.onProgress({ completed: 2, total: 2 }); assert.equal(notifications, before);
  assert.equal(job.items[0].cached, true); assert.equal(job.items[0].requestCount, 2);
});

test('empty response is a failure and never overwrites previous text', async () => {
  const row = entry('a'); row.translations.en = '旧译文'; const job = jobFor([row], ['en']);
  await Jobs.run(job, { client: { async translate() { return { text: ' ' }; } } });
  assert.equal(row.translations.en, '旧译文'); assert.equal(job.items[0].error.code, 'EMPTY_RESULT');
});

test('pause then immediate resume prevents old run from pausing or writing into new run', async () => {
  const row = entry('a'), job = jobFor([row], ['en']);
  const firstController = new AbortController(), first = deferred(), second = deferred();
  let calls = 0, firstChangeCount = 0;
  const client = { translate() { calls++; return calls === 1 ? first.promise : second.promise; } };
  const oldRun = Jobs.run(job, { client, signal: firstController.signal, onChange() { firstChangeCount++; } });
  firstController.abort(); Jobs.normalize(job);
  const newRun = Jobs.run(job, { client, signal: new AbortController().signal });
  const oldCount = firstChangeCount;
  first.resolve({ text: '旧结果' }); await oldRun;
  assert.equal(job.status, 'running'); assert.equal(job.items[0].status, 'running');
  assert.equal(row.translations.en, undefined); assert.equal(firstChangeCount, oldCount);
  second.resolve({ text: '新结果' }); await newRun;
  assert.equal(row.translations.en, '新结果'); assert.equal(job.status, 'completed');
});

test('new jobs use the chain while explicitly restored MyMemory jobs remain compatible', async () => {
  assert.equal(jobFor([entry('a')], ['en']).provider, 'TranslationChain');
  const row = entry('legacy');
  const job = Jobs.createJob({ id: 'old-job', projectId: 'p', projectName: '旧任务', entries: [row], locales: ['en'], provider: 'MyMemory' });
  job.status = 'running'; job.items[0].status = 'running';
  Jobs.normalize(job);
  assert.equal(job.status, 'paused');
  await Jobs.run(job, { client: { async translate() { return { text: 'Log in', provider: 'MyMemory' }; } } });
  assert.equal(job.provider, 'MyMemory');
  assert.equal(job.items[0].provider, 'MyMemory');
  assert.equal(row.translationMeta.en.provider, 'MyMemory');
});

test('backup success records its actual provider and is reused by a subsequent job', async () => {
  const row = entry('backup'), job = jobFor([row], ['en']);
  await Jobs.run(job, { client: { async translate() { return { text: 'Log in', provider: 'ZTAITrans', requestCount: 1 }; } } });
  assert.equal(row.translationMeta.en.provider, 'ZTAITrans');
  assert.equal(row.translationMeta.en.status, 'success');
  assert.equal(job.items[0].provider, 'ZTAITrans');
  const again = jobFor([row], ['en']);
  await Jobs.run(again, { client: { async translate() { assert.fail('Backup success must not be requested again'); } } });
  assert.equal(again.items[0].status, 'success');
  assert.equal(again.items[0].reused, true);
  assert.equal(again.items[0].provider, 'ZTAITrans');
});

test('progress and retry callbacks update the active provider when fallback occurs', async () => {
  const row = entry('switch'), job = jobFor([row], ['en']);
  const seen = [];
  await Jobs.run(job, {
    onChange(current) { if (current.activeItem) seen.push({ provider: current.activeItem.provider, retry: !!current.activeItem.retry }); },
    client: { async translate(source, locale, options) {
      options.onProgress({ completed: 0, total: 2, provider: 'MyMemory' });
      options.onRetry({ attempt: 1, provider: 'ZTAITrans' });
      options.onProgress({ completed: 1, total: 1, provider: 'ZTAITrans' });
      return { text: 'Log in', provider: 'ZTAITrans' };
    } }
  });
  assert.ok(seen.some(item => item.provider === 'MyMemory'));
  assert.ok(seen.some(item => item.provider === 'ZTAITrans' && item.retry));
  assert.ok(seen.some(item => item.provider === 'ZTAITrans' && !item.retry));
  assert.equal(row.translationMeta.en.provider, 'ZTAITrans');
});

test('backup budget errors preserve provider and code without claiming the primary quota was exhausted', async () => {
  const rows = [entry('a'), entry('b')], job = jobFor(rows, ['en']);
  let calls = 0;
  await Jobs.run(job, { client: { async translate() {
    calls++;
    throw Object.assign(new Error('备用服务预算已用尽'), { code: 'BACKUP_BUDGET', provider: 'ZTAITrans', quota: true });
  } } });
  assert.equal(calls, 1);
  assert.equal(job.status, 'quota');
  assert.equal(job.error.code, 'BACKUP_BUDGET');
  assert.equal(job.error.provider, 'ZTAITrans');
  assert.equal(job.items[0].error.provider, 'ZTAITrans');
  assert.equal(rows[0].translationMeta.en.provider, 'ZTAITrans');
  assert.equal(rows[0].translations.en, undefined);
  assert.equal(job.items[1].status, 'pending');
});

test('failure provider uses current activity only when the error omits provider; unknown stays unknown', async () => {
  const backup = entry('backup'), unknown = entry('unknown');
  const job = jobFor([backup, unknown], ['en']);
  await Jobs.run(job, { client: { async translate(source, locale, options) {
    if (job.activeItem.entryId === 'backup') options.onProgress({ completed: 0, total: 1, provider: 'ZTAITrans' });
    throw Object.assign(new Error('临时失败'), { code: 'NETWORK' });
  } } });
  assert.equal(backup.translationMeta.en.provider, 'ZTAITrans');
  assert.equal(unknown.translationMeta.en.provider, 'Unknown');
  assert.equal(job.items[1].error.provider, 'Unknown');
});

test('explicit error provider takes precedence over earlier primary progress', async () => {
  const row = entry('backup-error'), job = jobFor([row], ['en']);
  await Jobs.run(job, { client: { async translate(source, locale, options) {
    options.onProgress({ completed: 0, total: 1, provider: 'MyMemory' });
    throw Object.assign(new Error('备用鉴权失败'), { code: 'BACKUP_AUTH', provider: 'ZTAITrans' });
  } } });
  assert.equal(job.items[0].error.code, 'BACKUP_AUTH');
  assert.equal(job.items[0].error.provider, 'ZTAITrans');
  assert.equal(row.translationMeta.en.provider, 'ZTAITrans');
});

test('unrecognized explicit success provider cannot overwrite an existing translation', async () => {
  const row = entry('invalid'); row.translations.en = 'Old translation';
  const job = jobFor([row], ['en']);
  await Jobs.run(job, { client: { async translate() { return { text: 'New translation', provider: 'unverified-service' }; } } });
  assert.equal(row.translations.en, 'Old translation');
  assert.equal(job.items[0].status, 'failed');
  assert.equal(job.items[0].error.code, 'INVALID_PROVIDER');
  assert.equal(job.items[0].error.provider, 'Unknown');
});

test('fatal backup authentication, configuration and disabled errors block remaining requests', async t => {
  for (const code of ['BACKUP_AUTH', 'BACKUP_NOT_CONFIGURED', 'BACKUP_DISABLED']) {
    await t.test(code, async () => {
      const rows = [entry('a'), entry('b')], job = jobFor(rows, ['en', 'ja']);
      let calls = 0;
      await Jobs.run(job, { client: { async translate() {
        calls++;
        throw Object.assign(new Error('备用服务需要处理配置'), { code, provider: 'ZTAITrans', fatal: true });
      } } });
      assert.equal(calls, 1);
      assert.equal(job.status, 'blocked');
      assert.equal(job.activeItem, null);
      assert.equal(job.error.code, code);
      assert.equal(job.error.provider, 'ZTAITrans');
      assert.equal(job.error.fatal, true);
      assert.equal(job.error.quota, false);
      assert.equal(job.items[0].error.fatal, true);
      assert.equal(rows[0].translationMeta.en.error.fatal, true);
      assert.equal(rows[0].translations.en, undefined);
      assert.equal(Jobs.summary(job).failed, 1);
      assert.equal(Jobs.summary(job).pending, 3);
      Jobs.normalize(job);
      assert.equal(job.status, 'blocked');
    });
  }
});

test('an explicit retry after fixing a fatal backup problem resumes only unfinished cells', async () => {
  const rows = [entry('a'), entry('b'), entry('c')], job = jobFor(rows, ['en']);
  const calls = [];
  let fixed = false;
  const client = { async translate(source, locale) {
    const id = job.activeItem.entryId;
    calls.push(id);
    if (id === 'b' && !fixed) throw Object.assign(new Error('备用服务未配置'), { code: 'BACKUP_NOT_CONFIGURED', provider: 'ZTAITrans', fatal: true });
    return { text: id + ': translated', provider: 'ZTAITrans' };
  } };
  await Jobs.run(job, { client });
  assert.equal(job.status, 'blocked');
  assert.deepEqual(calls, ['a', 'b']);
  fixed = true;
  Jobs.retryFailed(job);
  assert.equal(job.status, 'paused');
  await Jobs.run(job, { client });
  assert.equal(job.status, 'completed');
  assert.deepEqual(calls, ['a', 'b', 'b', 'c']);
  assert.equal(Jobs.summary(job).success, 3);
  assert.equal(job.error, undefined);
});

test('quota classification remains quota even when a provider also marks the failure fatal', async () => {
  const job = jobFor([entry('a'), entry('b')], ['en']);
  await Jobs.run(job, { client: { async translate() {
    throw Object.assign(new Error('备用预算耗尽'), { code: 'BACKUP_BUDGET', provider: 'ZTAITrans', fatal: true, quota: true });
  } } });
  assert.equal(job.status, 'quota');
  assert.equal(job.error.code, 'BACKUP_BUDGET');
  assert.equal(job.error.provider, 'ZTAITrans');
  assert.equal(job.error.fatal, true);
  assert.equal(job.error.quota, true);
  assert.equal(Jobs.summary(job).pending, 1);
});
