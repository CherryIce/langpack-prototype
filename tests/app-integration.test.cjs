const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');
const path = require('node:path');

const dist = path.join(__dirname, '../web');
const STORAGE = 'langpack-prototype-v1';
const code = name => fs.readFileSync(path.join(dist, name), 'utf8');
const clone = value => JSON.parse(JSON.stringify(value));
const date = '2026-10-29T08:00:00.000Z';
function makeEntry(id, source = '登录') {
  return { id, key: 'key_' + id, source, sourceVersion: 1, selected: true, translations: {}, reviewed: {}, edited: {} };
}
function fixture(locales = ['en', 'ja']) {
  const entries = [makeEntry('one')];
  return {
    version: 2, view: 'languages', currentProjectId: 'a',
    projects: [
      { id: 'a', name: '自定义项目 A', description: '不能丢失', locales: [...locales], icon: 'layers', color: '', entries, updatedAt: date },
      { id: 'b', name: '自定义项目 B', description: '', locales: ['en'], icon: 'layers', color: '', entries: [], updatedAt: date }
    ],
    session: { id: 'session-a', projectId: 'a', entries: clone(entries), locales: [...locales], mode: 'text', text: '登录', split: 'line', context: '', status: 'draft', includeSource: true, pretty: true, exportLocales: [...locales] },
    jobs: [], exports: [], settings: { includeSource: true, pretty: true, translationEmail: '', providerOrder: ['MyMemory', 'ZTAITrans'], providerFallback: true }, homeFilter: 'all', search: '', reviewLocale: 'en', reviewIndex: 0
  };
}
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }

function boot(saved, translate = async () => { throw new Error('Unexpected translation request'); }, options = {}) {
  const values = options.localValues || new Map(); values.set(STORAGE, JSON.stringify(saved));
  const sessionValues = options.sessionValues || new Map([['langpack-provider-session-v1', JSON.stringify({ ZTAITrans: { apiKey: 'fixture-user-owned-ztai-key' } })]]);
  const handlers = new Map(), errors = [], elements = new Map();
  let html = '';
  function element(id) {
    if (!elements.has(id)) elements.set(id, { id, dataset: {}, innerHTML: '', textContent: '', value: '', open: false, disabled: false,
      get validity() {
        // Model the email input's native type check; the app separately requires a dotted domain.
        const typeMismatch = this.id === 'translation-email' && this.value !== '' && !/^[^\s@]+@[^\s@]+$/.test(this.value);
        return { valid: !typeMismatch, typeMismatch, valueMissing: false };
      },
      classList: { add() {}, remove() {} }, addEventListener() {}, focus() {}, close() { this.open = false; }, showModal() { this.open = true; }, getBoundingClientRect() { return { left: 0, right: 400, top: 0, bottom: 400 }; } });
    return elements.get(id);
  }
  const app = element('app');
  Object.defineProperty(app, 'innerHTML', { get() { return html; }, set(value) { html = String(value); } });
  element('toast'); element('modal');
  const document = {
    querySelector(selector) {
      if (selector[0] !== '#') return null;
      const id = selector.slice(1);
      if (['app', 'toast', 'modal'].includes(id) || html.includes('id="' + id + '"') || [...elements.values()].some(value => value.innerHTML.includes('id="' + id + '"'))) return element(id);
      return null;
    },
    addEventListener(type, handler) { if (!handlers.has(type)) handlers.set(type, []); handlers.get(type).push(handler); }
  };
  const timers = new Set();
  const context = vm.createContext({
    document, localStorage: { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, String(value)), removeItem: key => values.delete(key) },
    sessionStorage: { getItem: key => sessionValues.get(key) ?? null, setItem: (key, value) => sessionValues.set(key, String(value)), removeItem: key => sessionValues.delete(key) },
    fetch: options.fetch || (async () => { throw new Error('Unexpected fetch in app fixture'); }),
    TextEncoder, TextDecoder, AbortController, Blob, URL, crypto: webcrypto,
    console: { log() {}, warn() {}, error(...args) { errors.push(args); } },
    setTimeout(callback, ms) { const duration = ms === 30000 ? options.validationTimeoutMs ?? 1000 : Math.min(ms, 10); const timer = setTimeout(() => { timers.delete(timer); callback(); }, duration); timers.add(timer); return timer; },
    clearTimeout(timer) { timers.delete(timer); clearTimeout(timer); }
  });
  context.window = context; context.addEventListener = () => {}; context.scrollTo = () => {};
  vm.runInContext(code('languages.js'), context);
  vm.runInContext(code('providers.js'), context);
  vm.runInContext(code('provider-settings.js'), context);
  vm.runInContext(code('engine.js'), context);
  vm.runInContext(code('translation-jobs.js'), context);
  context.MyMemoryTranslator = { createClient: config => { options.onPrimaryConfig?.(config); return { async translate(...args) { const result = await translate(...args); return { provider: 'MyMemory', ...result }; } }; }, utf8Length: value => new TextEncoder().encode(value).length };
  vm.runInContext(code('translation-service.js'), context);
  const service = context.TranslationService;
  context.TranslationService = { ...service, createProviderClient: args => { options.onProviderClient?.(args); return args.provider === 'ZTAITrans' && options.backupTranslate ? { translate: options.backupTranslate } : service.createProviderClient({ ...args, maxRetries: 0, fetchImpl: options.providerFetch || options.backupFetch || (async () => { throw Object.assign(new Error('No provider request expected'), { code: 'PROVIDER_CONFIG', fatal: true }); }) }); } };
  vm.runInContext(code('app.js'), context);
  return {
    state: () => JSON.parse(values.get(STORAGE)), html: () => html, errors, localValues: values, sessionValues,
    async click(action, extra = {}) {
      const button = { dataset: { action, ...extra }, disabled: false, closest() { return this; } };
      for (const handler of handlers.get('click') || []) await handler({ target: button });
    },
    field(id, value) { const target = document.querySelector('#' + id); assert.ok(target, 'Visible field ' + id); target.value = value; return target; },
    async input(id, value) { const target = this.field(id, value); for (const handler of handlers.get('input') || []) await handler({ target }); },
    async change(target) { for (const handler of handlers.get('change') || []) await handler({ target }); },
    content(id) { return element(id).innerHTML; },
    text(id) { return element(id).textContent; },
    value(id) { return element(id).value; },
    disabled(id) { return element(id).disabled; },
    async editDocumentSource(index, value) { const target = { value, dataset: { docSource: String(index) } }; for (const handler of handlers.get('input') || []) await handler({ target }); },
    close() { for (const timer of timers) clearTimeout(timer); },
    engine: context.LangPackEngine
  };
}
async function until(predicate) {
  for (let i = 0; i < 30; i++) { if (predicate()) return; await new Promise(resolve => setImmediate(resolve)); }
  assert.fail('App did not reach expected persisted state');
}

test('v1 startup preserves projects, manual translations and export snapshots; seeded confirmations cannot bypass real translation', t => {
  const saved = fixture(['en']); saved.version = 1; saved.view = 'export';
  const legacy = saved.projects[0].entries[0]; legacy.translations.en = 'Legacy sample'; legacy.reviewed.en = true;
  const manual = makeEntry('manual', '注册'); manual.translations.en = 'My own carefully edited translation'; manual.edited.en = true; manual.reviewed.en = true;
  saved.projects[0].entries.push(manual); saved.session.entries = clone(saved.projects[0].entries);
  saved.exports = [{ id: 'export-before-upgrade', name: 'old.json', files: { 'en.json': '{"old":"keep exactly"}' }, kind: 'json', createdAt: date }];
  saved.jobs = [{ id: 'legacy-job', projectId: 'a', projectName: '自定义项目 A', entries: clone(saved.projects[0].entries), locales: ['en'], status: 'completed', createdAt: date }];
  const app = boot(saved); t.after(() => app.close());
  const migrated = app.state();
  assert.equal(migrated.version, 2); assert.equal(migrated.projects.length, 2);
  assert.equal(migrated.projects[0].name, '自定义项目 A'); assert.equal(migrated.projects[0].description, '不能丢失');
  assert.deepEqual(migrated.exports, saved.exports);
  assert.equal(migrated.projects[0].entries[0].translations.en, 'Legacy sample');
  assert.equal(migrated.projects[0].entries[0].reviewed.en, false);
  assert.equal(migrated.projects[0].entries[0].translationMeta.en.legacyReviewed, true);
  assert.equal(migrated.projects[0].entries[1].translations.en, manual.translations.en);
  assert.equal(migrated.projects[0].entries[1].reviewed.en, true);
  assert.equal(migrated.projects[0].entries[1].translationMeta.en.provider, 'manual');
  assert.equal(migrated.jobs[0].provider, 'LegacyDemo');
  assert.equal(app.engine.validate(migrated.session.entries, ['en']).some(issue => issue.type === 'legacy'), true);
  assert.match(app.html(), /历史演示译文需重新翻译/);
  assert.match(app.html(), /data-action="download-zip" disabled/);
  assert.deepEqual(app.errors, []);
});

test('event-driven batch persists successful results, failures and retry-only-failed lifecycle', async t => {
  const calls = []; let fail = true;
  const app = boot(fixture(), async (source, locale) => {
    calls.push(locale);
    if (locale === 'ja' && fail) throw Object.assign(new Error('Temporary network error'), { code: 'NETWORK', retryable: true });
    return { text: locale === 'en' ? 'Log in' : 'ログイン', provider: 'MyMemory', requestCount: 1 };
  });
  t.after(() => app.close());
  await app.click('start-translation');
  await until(() => app.state().session.status === 'completed');
  let state = app.state();
  assert.deepEqual(calls, ['en', 'ja']);
  assert.equal(state.projects[0].entries[0].translations.en, 'Log in');
  assert.equal(state.projects[0].entries[0].translationMeta.en.provider, 'MyMemory');
  assert.equal(state.projects[0].entries[0].translations.ja, undefined);
  assert.equal(state.jobs[0].success, 1); assert.equal(state.jobs[0].failed, 1);
  assert.match(app.html(), /部分译文需要重试/);
  assert.match(app.html(), /Temporary network error/);
  fail = false; await app.click('retry-failed');
  await until(() => app.state().session.status === 'completed' && app.state().jobs[0].failed === 0);
  state = app.state();
  assert.deepEqual(calls, ['en', 'ja', 'ja']);
  assert.equal(state.projects[0].entries[0].translations.ja, 'ログイン');
  assert.match(app.html(), /翻译已完成/); assert.deepEqual(app.errors, []);
});

test('quota errors from both providers stop batch, preserve pending cells and remain visible in actual UI', async t => {
  let primaryCount = 0, backupCount = 0;
  const app = boot(fixture(), async () => { primaryCount++; throw Object.assign(new Error('Daily quota exhausted'), { code: 'QUOTA', quota: true }); }, {
    backupFetch: async () => { backupCount++; return new Response(JSON.stringify({ code: 'PROVIDER_QUOTA', message: 'Budget exhausted' }), { status: 402 }); }
  });
  t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'quota');
  const state = app.state();
  assert.equal(primaryCount, 1); assert.equal(backupCount, 1); assert.equal(state.jobs[0].items[1].status, 'pending');
  assert.equal(state.projects[0].entries[0].translations.en, undefined);
  assert.equal(state.jobs[0].error.provider, 'ZTAITrans'); assert.equal(state.jobs[0].error.code, 'PROVIDER_QUOTA');
  assert.match(app.html(), /ZTAITrans 额度暂不可用/); assert.doesNotMatch(app.html(), /今日免费额度已用完/);
  assert.deepEqual(app.errors, []);
});

test('pause and new project session prevent late network result from changing either project', async t => {
  const late = deferred(); let started = false;
  const app = boot(fixture(['en']), () => { started = true; return late.promise; }); t.after(() => app.close());
  await app.click('start-translation'); assert.equal(started, true);
  await app.click('pause-translation');
  await app.click('project', { id: 'b' }); await app.click('add-content');
  const newSessionId = app.state().session.id; assert.equal(app.state().session.projectId, 'b');
  late.resolve({ text: 'Must not be saved', provider: 'MyMemory' });
  await new Promise(resolve => setImmediate(resolve)); await new Promise(resolve => setImmediate(resolve));
  const state = app.state();
  assert.equal(state.session.id, newSessionId); assert.equal(state.session.projectId, 'b');
  assert.equal(state.projects[0].entries[0].translations.en, undefined);
  assert.equal(state.projects[1].entries.length, 0);
  assert.equal(state.jobs[0].items[0].status, 'pending');
  assert.match(app.html(), /添加你的中文文案/); assert.deepEqual(app.errors, []);
});

test('immediate resume uses a new run; late aborted result cannot pause it or win', async t => {
  const first = deferred(), second = deferred(); let count = 0;
  const app = boot(fixture(['en']), () => ++count === 1 ? first.promise : second.promise); t.after(() => app.close());
  await app.click('start-translation'); await app.click('pause-translation'); await app.click('resume-translation');
  assert.equal(count, 2);
  first.resolve({ text: 'Old result' }); await new Promise(resolve => setImmediate(resolve));
  assert.equal(app.state().session.status, 'running');
  assert.equal(app.state().projects[0].entries[0].translations.en, undefined);
  second.resolve({ text: 'Current result', provider: 'MyMemory' });
  await until(() => app.state().session.status === 'completed');
  assert.equal(app.state().projects[0].entries[0].translations.en, 'Current result');
  assert.deepEqual(app.errors, []);
});

test('reload retains completed cells and normalizes in-flight work for resumption', async t => {
  const saved = fixture(['en']); const row = saved.session.entries[0];
  saved.jobs = [{ id: 'in-flight', projectId: 'a', projectName: 'A', provider: 'MyMemory', entries: [clone(row)], locales: ['en'], count: 1, total: 1, status: 'running', createdAt: date, activeItem: { entryId: row.id, locale: 'en' }, items: [{ entryId: row.id, locale: 'en', source: row.source, sourceVersion: 1, status: 'running' }] }];
  saved.session.jobId = 'in-flight'; saved.session.status = 'running'; saved.view = 'translate';
  const app = boot(saved); t.after(() => app.close());
  const state = app.state(); assert.equal(state.session.status, 'paused'); assert.equal(state.jobs[0].status, 'paused'); assert.equal(state.jobs[0].items[0].status, 'pending');
  assert.match(app.html(), /任务已暂停/); assert.match(app.html(), /继续翻译/); assert.deepEqual(app.errors, []);
});

test('viewing an untouched missing translation does not lock it as a manual edit before retry', async t => {
  let fail = true, calls = 0;
  const app = boot(fixture(['en']), async () => { calls++; if (fail) throw Object.assign(new Error('Temporary failure'), { code: 'NETWORK' }); return { text: 'Log in' }; });
  t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  await app.click('inspect-failed', { entryId: 'one', locale: 'en' });
  app.field('review-key', 'key_one'); app.field('review-text', '');
  await app.click('nav', { view: 'tasks' });
  assert.notEqual(app.state().projects[0].entries[0].edited.en, true);
  assert.equal(app.state().projects[0].entries[0].translationMeta.en.status, 'failed');
  fail = false;
  await app.click('open-job', { id: app.state().jobs[0].id }); await app.click('retry-failed');
  await until(() => app.state().session.status === 'completed' && app.state().jobs[0].failed === 0);
  assert.equal(calls, 2); assert.equal(app.state().projects[0].entries[0].translations.en, 'Log in');
});

test('single retranslation cannot overwrite manual input saved while awaiting API', async t => {
  const saved = fixture(['en']); saved.view = 'review'; saved.session.status = 'completed';
  for (const row of [saved.projects[0].entries[0], saved.session.entries[0]]) {
    row.translations.en = 'Original translation'; row.translationMeta = { en: { provider: 'MyMemory', status: 'success', sourceText: row.source } };
  }
  const late = deferred(); let calls = 0;
  const app = boot(saved, () => { calls++; return late.promise; }); t.after(() => app.close());
  app.field('review-key', 'key_one'); app.field('review-text', 'Original translation');
  await app.click('retranslate'); assert.equal(calls, 1);
  assert.match(app.html(), /翻译中…/);
  await app.input('review-text', 'Manual text saved while waiting'); await app.click('save-review');
  late.resolve({ text: 'Late API result' }); await new Promise(resolve => setImmediate(resolve));
  const row = app.state().projects[0].entries[0];
  assert.equal(row.translations.en, 'Manual text saved while waiting');
  assert.equal(row.translationMeta.en.provider, 'manual'); assert.equal(row.edited.en, true);
  assert.deepEqual(app.errors, []);
});


test('primary quota automatically switches the actual app chain to backup and persists the actual provider for every result', async t => {
  let primaryCount = 0; const backupCalls = [];
  const saved = fixture();
  saved.projects[0].entries.push(makeEntry('two', '注册账号'));
  saved.session.entries = clone(saved.projects[0].entries);
  const app = boot(saved, async () => { primaryCount++; throw Object.assign(new Error('Primary quota exhausted'), { code: 'QUOTA', quota: true }); }, {
    backupTranslate: async (source, locale, options) => {
      backupCalls.push({ source, locale });
      options.onProgress?.({ completed: 1, total: 1, requestCount: 1 });
      return { text: locale === 'ja' ? '翻訳 ' + source : 'Translation ' + source, provider: 'ZTAITrans', requestCount: 1 };
    }
  });
  t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  const state = app.state();
  assert.equal(primaryCount, 1); assert.equal(backupCalls.length, 4);
  assert.equal(state.jobs[0].provider, 'TranslationChain'); assert.equal(state.jobs[0].success, 4); assert.equal(state.jobs[0].failed, 0);
  assert.equal(state.jobs[0].items.every(item => item.provider === 'ZTAITrans'), true);
  for (const entry of state.projects[0].entries) for (const locale of ['en', 'ja']) assert.equal(entry.translationMeta[locale].provider, 'ZTAITrans');
  assert.equal(state.settings.primaryCircuit.until > Date.now(), true);
  assert.equal(state.settings.lastFallback.to, 'ZTAITrans');
  assert.match(app.html(), /翻译已完成/); assert.doesNotMatch(app.html(), /今日免费额度已用完/);
  assert.deepEqual(app.errors, []);
});

test('fatal backup authorization failure stops the app job and does not show the primary quota title', async t => {
  let primaryCount = 0, backupCount = 0;
  const app = boot(fixture(), async () => { primaryCount++; throw Object.assign(new Error('Primary quota exhausted'), { code: 'QUOTA', quota: true }); }, {
    backupFetch: async () => { backupCount++; return new Response(JSON.stringify({ code: 'PROVIDER_AUTH', message: 'Unauthorized' }), { status: 401 }); }
  });
  t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'blocked');
  const state = app.state();
  assert.equal(primaryCount, 1); assert.equal(backupCount, 1);
  assert.equal(state.jobs[0].failed, 1); assert.equal(state.jobs[0].items[1].status, 'pending');
  assert.equal(state.jobs[0].error.provider, 'ZTAITrans'); assert.equal(state.jobs[0].error.code, 'PROVIDER_AUTH');
  assert.equal(state.projects[0].entries[0].translations.en, undefined);
  assert.match(app.html(), /翻译平台配置需要处理/); assert.doesNotMatch(app.html(), /今日免费额度已用完/);
  assert.deepEqual(app.errors, []);
});

test('the actual app plans reimports incrementally, persists reused results and makes no calls after reopening', async t => {
  const saved = fixture(['en', 'ja']);
  const old = saved.projects[0].entries[0];
  old.translations.en = 'Log in'; old.translationMeta = { en: { provider: 'ZTAITrans', status: 'success', sourceText: old.source, sourceVersion: 1 } };
  old.reviewed.en = true;
  saved.session.entries = [makeEntry('copy'), makeEntry('new', '新增文案'), makeEntry('duplicate', '新增文案')];
  const calls = [];
  const app = boot(saved, async (source, locale) => { calls.push([source, locale]); return { text: locale + ':' + source, provider: 'MyMemory', requestCount: 1 }; });
  t.after(() => app.close());
  assert.match(app.html(), /复用已有译文<\/span><strong>1 条/);
  assert.match(app.html(), /合并重复原文<\/span><strong>2 条/);
  assert.match(app.html(), /本次增量待译<\/span><strong>3</);
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.deepEqual(calls, [['新增文案', 'en'], ['登录', 'ja'], ['新增文案', 'ja']]);
  const state = app.state();
  assert.equal(state.session.entries[0].translations.en, 'Log in');
  assert.equal(state.session.entries[0].translationMeta.en.provider, 'ZTAITrans');
  assert.equal(state.session.entries[0].reviewed.en, false);
  assert.equal(state.jobs[0].items.filter(item => item.reused).length, 3);
  assert.match(app.html(), /复用 3/);
  state.session.entries = [makeEntry('another_copy')]; state.session.locales = ['en']; state.view = 'languages'; state.session.status = 'draft'; delete state.session.jobId;
  const reopened = boot(state); t.after(() => reopened.close());
  assert.match(reopened.html(), /复用译文并校对/);
  await reopened.click('start-translation'); await until(() => reopened.state().session.status === 'completed');
  assert.equal(reopened.state().session.entries[0].translations.en, 'Log in');
  assert.equal(reopened.state().jobs[0].items[0].reused, true);
  assert.deepEqual(app.errors, []); assert.deepEqual(reopened.errors, []);
});

test('saved translations from another project cannot satisfy the current project plan', async t => {
  const saved = fixture(['en']);
  const foreign = makeEntry('foreign'); foreign.translations.en = 'Foreign project translation'; foreign.translationMeta = { en: { provider: 'MyMemory', status: 'success', sourceText: foreign.source, sourceVersion: 1 } };
  saved.projects[1].entries = [foreign];
  let calls = 0;
  const app = boot(saved, async () => { calls++; return { text: 'Current project translation', provider: 'MyMemory' }; }); t.after(() => app.close());
  assert.match(app.html(), /复用已有译文<\/span><strong>0 条/);
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.equal(calls, 1);
  assert.equal(app.state().session.entries[0].translations.en, 'Current project translation');
  assert.equal(app.state().projects[1].entries[0].translations.en, 'Foreign project translation');
});

test('document source edits invalidate old translations and manual flags before incremental translation', async t => {
  const saved = fixture(['en']); saved.view = 'import'; saved.session.mode = 'document';
  const row = saved.session.entries[0]; row.translations.en = 'Original manual'; row.edited.en = true; row.reviewed.en = true;
  row.translationMeta = { en: { provider: 'manual', status: 'success', sourceText: row.source } };
  const calls = [];
  const app = boot(saved, async source => { calls.push(source); return { text: 'Changed translation', provider: 'MyMemory' }; }); t.after(() => app.close());
  await app.editDocumentSource(0, '更新后的原文'); await app.click('to-languages');
  const edited = app.state().session.entries[0];
  assert.equal(edited.sourceVersion, 2); assert.deepEqual(edited.edited, {}); assert.deepEqual(edited.translationMeta, {});
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.deepEqual(calls, ['更新后的原文']);
  assert.equal(app.state().session.entries[0].translationMeta.en.sourceVersion, 2);
  assert.equal(app.state().session.entries[0].translations.en, 'Changed translation');
});

test('explicit single retranslation continues to bypass caches when an incremental result already exists', async t => {
  const saved = fixture(['en']); saved.view = 'review'; saved.session.status = 'completed';
  for (const row of [saved.projects[0].entries[0], saved.session.entries[0]]) {
    row.translations.en = 'Log in'; row.translationMeta = { en: { provider: 'MyMemory', status: 'success', sourceText: row.source, sourceVersion: 1 } };
  }
  let calls = 0;
  const app = boot(saved, async (source, locale, options) => { calls++; assert.equal(options.bypassCache, true); return { text: 'Sign in', provider: 'MyMemory' }; }); t.after(() => app.close());
  app.field('review-key', 'key_one'); app.field('review-text', 'Log in');
  await app.click('retranslate'); await until(() => app.state().session.entries[0].translations.en === 'Sign in');
  assert.equal(calls, 1);
  assert.equal(app.state().session.entries[0].translationMeta.en.sourceVersion, 1);
});

test('language picker exposes 34 searchable targets, retains hidden selections and excludes the fixed source', async t => {
  const app = boot(fixture(['en'])); t.after(() => app.close());
  assert.equal((app.html().match(/data-locale="[^"]+"[^>]*aria-label="选择/g) || []).length, 34);
  assert.doesNotMatch(app.html(), /data-locale="zh-Hans"/);
  assert.match(app.html(), /35 种语言覆盖/); assert.match(app.html(), /34 种目标语言可选/);
  await app.input('language-search', 'pt-');
  assert.match(app.content('language-options'), /data-locale="pt-BR"/);
  assert.match(app.content('language-options'), /data-locale="pt-PT"/);
  assert.doesNotMatch(app.content('language-options'), /data-locale="en"/);
  assert.deepEqual(app.state().session.locales, ['en']);
  await app.change({ dataset: { locale: 'pt-BR' }, checked: true });
  assert.deepEqual(app.state().session.locales, ['en', 'pt-BR']);
  await app.input('language-search', 'සිංහල');
  assert.match(app.content('language-options'), /data-locale="si"/);
  await app.input('language-search', '不存在的语言');
  assert.match(app.content('language-options'), /没有找到匹配的语言/);
  assert.deepEqual(app.state().session.locales, ['en', 'pt-BR']);
  await app.click('toggle-all-languages');
  assert.equal(app.state().session.locales.length, 34);
  assert.equal(app.state().session.locales.includes('zh-Hans'), false);
  assert.deepEqual(app.state().settings.recentLocales, []);
});

test('selection changes alone do not change recent languages, and abandoned drafts retain the prior default', async t => {
  const saved = fixture(['en', 'ja']); saved.settings.recentLocales = ['pt-PT', 'ru'];
  const app = boot(saved); t.after(() => app.close());
  await app.change({ dataset: { locale: 'si' }, checked: true });
  await app.change({ dataset: { locale: 'ja' }, checked: false });
  assert.deepEqual(app.state().session.locales, ['en', 'si']);
  assert.deepEqual(app.state().settings.recentLocales, ['pt-PT', 'ru']);
  await app.click('project', { id: 'a' }); await app.click('add-content');
  assert.deepEqual(app.state().session.locales, ['pt-PT', 'ru']);
  await app.click('project', { id: 'a' }); await app.click('add-document');
  assert.deepEqual(app.state().session.locales, ['pt-PT', 'ru']);
  await app.click('project', { id: 'a' }); await app.click('translate-project');
  assert.deepEqual(app.state().session.locales, ['pt-PT', 'ru']);
  assert.deepEqual(app.state().projects[0].locales, ['en', 'ja']);
  await app.click('project', { id: 'a' }); await app.click('review-project');
  assert.deepEqual(app.state().session.locales, ['en', 'ja']);
  app.field('review-key', 'key_one'); app.field('review-text', '');
  await app.click('project', { id: 'a' }); await app.click('export-project');
  assert.deepEqual(app.state().session.locales, ['en', 'ja']);
  assert.deepEqual(app.state().session.exportLocales, ['en', 'ja']);
});

test('valid new batch records normalized recent targets, persists on reload and defaults a newly created project', async t => {
  const saved = fixture(['en', 'en', 'unknown', 'zh-Hans', 'pt-br', 'si']);
  const calls = [];
  const app = boot(saved, async (source, locale) => { calls.push(['primary', locale]); return { text: locale + ' result', provider: 'MyMemory' }; }, {
    backupTranslate: async (source, locale) => { calls.push(['backup', locale]); return { text: locale + ' result', provider: 'ZTAITrans' }; }
  }); t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.deepEqual(calls, [['primary', 'en'], ['backup', 'pt-BR'], ['primary', 'si']]);
  assert.deepEqual(app.state().settings.recentLocales, ['en', 'pt-BR', 'si']);
  assert.equal(app.state().session.entries[0].translationMeta['pt-BR'].provider, 'ZTAITrans');
  assert.equal(app.state().settings.primaryCircuit.until, 0);
  assert.equal(app.state().settings.lastFallback.reason, 'unsupported');
  const reopened = boot(app.state()); t.after(() => reopened.close());
  await reopened.click('project', { id: 'b' }); await reopened.click('add-content');
  assert.deepEqual(reopened.state().session.locales, ['en', 'pt-BR', 'si']);
  await reopened.click('new-project'); reopened.field('project-name', '新偏好项目'); reopened.field('project-description', ''); await reopened.click('create-project');
  assert.equal(reopened.state().projects.at(-1).name, '新偏好项目');
  assert.deepEqual(reopened.state().session.locales, ['en', 'pt-BR', 'si']);
});

test('a fully reused zero-request batch still records the languages the user actually started', async t => {
  const saved = fixture(['pt-PT', 'si']); saved.settings.recentLocales = ['en'];
  for (const row of [saved.projects[0].entries[0], saved.session.entries[0]]) for (const locale of ['pt-PT', 'si']) {
    row.translations[locale] = locale + ' existing'; row.translationMeta ||= {}; row.translationMeta[locale] = { provider: 'MyMemory', status: 'success', sourceText: row.source, sourceVersion: 1 };
  }
  const app = boot(saved); t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.deepEqual(app.state().settings.recentLocales, ['pt-PT', 'si']);
  assert.equal(app.state().jobs[0].items.every(item => item.reused), true);
});

test('invalid starts cannot erase the recent preference and no-preference drafts retain their old fallback', async t => {
  for (const locales of [[], ['xx', 'zh-Hans']]) {
    const saved = fixture(locales); saved.settings.recentLocales = ['ru', 'en'];
    const app = boot(saved); t.after(() => app.close()); await app.click('start-translation');
    assert.deepEqual(app.state().settings.recentLocales, ['ru', 'en']); assert.equal(app.state().jobs.length, 0);
  }
  const saved = fixture(['si']); saved.settings.recentLocales = ['xx', 'zh-Hans'];
  const fallback = boot(saved); t.after(() => fallback.close());
  await fallback.click('project', { id: 'a' }); await fallback.click('add-content');
  assert.deepEqual(fallback.state().session.locales, ['si']);
  await fallback.click('new-project'); fallback.field('project-name', '默认项目'); fallback.field('project-description', ''); await fallback.click('create-project');
  assert.deepEqual(fallback.state().session.locales, ['en', 'ja', 'ko']);
});

test('resume and failed retry retain their old language snapshots without narrowing recent preferences', async t => {
  const Jobs = require('../web/translation-jobs.js');
  for (const action of ['resume-translation', 'retry-failed']) await t.test(action, async () => {
    const saved = fixture(['en']); saved.settings.recentLocales = ['pt-PT', 'ru', 'si']; saved.view = 'translate';
    const job = Jobs.createJob({ id: 'old', projectId: 'a', projectName: '旧任务', entries: saved.session.entries, locales: ['en'] });
    job.status = 'paused'; if (action === 'retry-failed') job.items[0].status = 'failed';
    saved.jobs = [job]; saved.session.jobId = job.id; saved.session.status = 'paused';
    const app = boot(saved, async () => ({ text: 'Log in', provider: 'MyMemory' })); t.after(() => app.close());
    await app.click(action); await until(() => app.state().session.status === 'completed');
    assert.deepEqual(app.state().settings.recentLocales, ['pt-PT', 'ru', 'si']);
    assert.deepEqual(app.state().session.locales, ['en']); assert.deepEqual(app.state().jobs[0].locales, ['en']);
  });
});

test('review, export, reopening old jobs and saving settings preserve preference and historic translations', async t => {
  const Jobs = require('../web/translation-jobs.js');
  const saved = fixture(['en', 'ja']); saved.settings.recentLocales = ['SI', 'pt-br', 'SI', 'xx', 'zh-Hans']; saved.view = 'project';
  const row = saved.projects[0].entries[0];
  row.translations = { en: 'Manual English', ja: '手動日本語' }; row.edited = { en: true, ja: true }; row.reviewed = { en: true, ja: true };
  saved.jobs = [Jobs.createJob({ id: 'historic', projectId: 'a', projectName: '旧任务', entries: [clone(row)], locales: ['ja'] })]; saved.jobs[0].status = 'completed';
  const app = boot(saved); t.after(() => app.close());
  const expected = ['si', 'pt-BR'];
  assert.deepEqual(app.state().settings.recentLocales, expected);
  await app.click('review-project'); assert.deepEqual(app.state().session.locales, ['en', 'ja']);
  app.field('review-key', 'key_one'); app.field('review-text', 'Manual English');
  await app.click('project', { id: 'a' }); await app.click('export-project');
  assert.deepEqual(app.state().session.locales, ['en', 'ja']); assert.deepEqual(app.state().session.exportLocales, ['en', 'ja']);
  await app.click('open-job', { id: 'historic' }); assert.deepEqual(app.state().session.locales, ['ja']);
  await app.click('nav', { view: 'settings' });
  assert.equal(app.field('translation-email', 'invalid-email').validity.valid, false);
  await app.click('save-translation-settings');
  assert.equal(app.state().settings.translationEmail, '');
  assert.equal(app.field('translation-email', 'owner@example.com').validity.valid, true);
  await app.click('save-translation-settings');
  assert.equal(app.state().settings.translationEmail, 'owner@example.com');
  assert.deepEqual(app.state().settings.recentLocales, expected);
  assert.deepEqual(app.state().projects[0].entries[0].translations, row.translations);
});

test('single retranslation leaves a broader recent target preference intact', async t => {
  const saved = fixture(['en']); saved.settings.recentLocales = ['ru', 'pt-PT', 'si']; saved.view = 'review'; saved.session.status = 'completed';
  const row = saved.session.entries[0]; row.translations.en = 'Existing'; row.translationMeta = { en: { provider: 'MyMemory', status: 'success', sourceText: row.source } };
  const app = boot(saved, async () => ({ text: 'Refreshed', provider: 'MyMemory' })); t.after(() => app.close());
  app.field('review-key', 'key_one'); app.field('review-text', 'Existing');
  await app.click('retranslate'); await until(() => app.state().session.entries[0].translations.en === 'Refreshed');
  assert.deepEqual(app.state().settings.recentLocales, ['ru', 'pt-PT', 'si']);
});

test('selecting all produces 34 genuine pipeline results and 35 canonical language files without source-to-source requests', async t => {
  const calls = [];
  const app = boot(fixture(['en']), async (source, locale) => { calls.push(['primary', locale]); return { text: locale + ' result', provider: 'MyMemory' }; }, {
    backupTranslate: async (source, locale) => { calls.push(['backup', locale]); return { text: locale + ' result', provider: 'ZTAITrans' }; }
  }); t.after(() => app.close());
  await app.click('toggle-all-languages'); await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  const state = app.state();
  assert.equal(calls.length, 34); assert.equal(calls.filter(([provider]) => provider === 'primary').length, 31);
  assert.deepEqual(calls.filter(([provider]) => provider === 'backup').map(([, locale]) => locale), ['pt-BR', 'fil', 'nb']);
  assert.equal(calls.some(([, locale]) => locale === 'zh-Hans'), false);
  assert.equal(state.jobs[0].success, 34); assert.equal(state.settings.recentLocales.length, 34);
  const files = app.engine.makePackages(state.session.entries, state.session.locales, true);
  assert.equal(Object.keys(files).length, 35);
  for (const locale of ['pt-BR', 'pt-PT', 'fil', 'nb', 'si']) assert.equal(JSON.parse(files[locale + '.json']).key_one, locale + ' result');
  assert.equal(state.settings.primaryCircuit.until, 0); assert.equal(state.settings.lastFallback.reason, 'unsupported');
});

test('migration defaults to MyMemory alone and never spends an implicit shared ZTAI account', async t => {
  const saved = fixture(['en']); delete saved.settings.providerOrder; delete saved.settings.providerFallback;
  let providerCalls = 0;
  const app = boot(saved, async () => { throw Object.assign(new Error('quota'), { quota: true }); }, { sessionValues: new Map(), providerFetch: async () => { providerCalls++; assert.fail('No implicit backup account'); } }); t.after(() => app.close());
  assert.deepEqual(app.state().settings.providerOrder, ['MyMemory']);
  await app.click('start-translation'); await until(() => app.state().session.status === 'quota');
  assert.equal(providerCalls, 0); assert.equal(app.state().jobs[0].error.provider, 'MyMemory');
});

test('settings select the primary platform and keep session credentials out of state, rendered values, tasks and language exports', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['MyMemory'];
  const secret = 'fixture-private-azure-key', requests = [];
  const app = boot(saved, undefined, { sessionValues: new Map(), providerFetch: async (url, options) => { requests.push(JSON.parse(options.body)); return new Response(JSON.stringify({ provider: 'Azure', text: 'Azure translation' })); } }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); await app.change({ id: 'primary-provider', value: 'Azure', dataset: {} });
  app.field('provider-Azure-key', secret); app.field('provider-Azure-region', 'eastasia');
  await app.click('save-provider-credentials', { provider: 'Azure' });
  assert.deepEqual(app.state().settings.providerOrder, ['Azure', 'MyMemory']);
  assert.doesNotMatch(JSON.stringify(app.state()), new RegExp(secret)); assert.doesNotMatch(app.html(), new RegExp(secret));
  assert.equal(app.localValues.get('langpack-provider-credentials-v1'), undefined);
  assert.match(app.sessionValues.get('langpack-provider-session-v1'), new RegExp(secret));
  await app.click('project', { id: 'a' }); await app.click('translate-project'); await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.deepEqual(requests[0].credentials, { apiKey: secret, region: 'eastasia' }); assert.equal(requests[0].provider, 'Azure');
  assert.equal(app.state().session.entries[0].translationMeta.en.provider, 'Azure');
  assert.doesNotMatch(JSON.stringify(app.state()), new RegExp(secret));
  assert.doesNotMatch(JSON.stringify(app.engine.makePackages(app.state().session.entries, ['en'], true)), new RegExp(secret));
});

test('configured MyMemory private key uses the protected proxy while deleting it restores anonymous direct translation', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['MyMemory']; saved.settings.translationEmail = 'owner@example.com';
  const secret = 'fixture-private-mymemory';
  const sessionValues = new Map([['langpack-provider-session-v1', JSON.stringify({ MyMemory: { apiKey: secret } })]]);
  const requests = []; let anonymousCalls = 0;
  const app = boot(saved, async () => { anonymousCalls++; return { text: 'Anonymous result', provider: 'MyMemory' }; }, { sessionValues, providerFetch: async (url, options) => { requests.push({ url, body: JSON.parse(options.body) }); return new Response(JSON.stringify({ provider: 'MyMemory', text: 'Private result' })); } }); t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.equal(anonymousCalls, 0); assert.equal(requests[0].url, '/api/translation/provider');
  assert.deepEqual(requests[0].body.credentials, { apiKey: secret, email: 'owner@example.com' });
  assert.doesNotMatch(JSON.stringify(app.state()), new RegExp(secret));
  await app.click('nav', { view: 'settings' }); await app.click('delete-provider-credentials', { provider: 'MyMemory' });
  await app.click('project', { id: 'a' }); await app.click('review-project'); app.field('review-key', 'key_one'); app.field('review-text', 'Private result');
  await app.click('retranslate'); await until(() => app.state().session.entries[0].translations.en === 'Anonymous result');
  assert.equal(anonymousCalls, 1); assert.equal(requests.length, 1);
});

test('explicit remember, session-only replacement and delete clear old credential copies without serializing them into project settings', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['DeepL'];
  const app = boot(saved, undefined, { sessionValues: new Map() }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); app.field('provider-DeepL-key', 'fixture-remembered'); app.field('provider-DeepL-plan', 'free'); app.field('provider-DeepL-remember', '').checked = true;
  await app.click('save-provider-credentials', { provider: 'DeepL' });
  assert.match(app.localValues.get('langpack-provider-credentials-v1'), /fixture-remembered/);
  app.field('provider-DeepL-key', 'fixture-session-replacement'); app.field('provider-DeepL-plan', 'pro'); app.field('provider-DeepL-remember', '').checked = false;
  await app.click('save-provider-credentials', { provider: 'DeepL' });
  assert.equal(app.localValues.get('langpack-provider-credentials-v1'), undefined);
  assert.doesNotMatch(app.sessionValues.get('langpack-provider-session-v1'), /fixture-remembered/);
  const reloaded = boot(app.state(), undefined, { localValues: app.localValues, sessionValues: app.sessionValues }); t.after(() => reloaded.close());
  assert.doesNotMatch(reloaded.html(), /fixture-session-replacement/);
  await reloaded.click('delete-provider-credentials', { provider: 'DeepL' });
  assert.equal(reloaded.sessionValues.get('langpack-provider-session-v1'), undefined);
  assert.doesNotMatch(JSON.stringify(reloaded.state()), /fixture-session-replacement/);
});

test('provider authentication failure blocks the batch instead of calling an enabled second platform', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['DeepL', 'Azure'];
  saved.session.entries.push(makeEntry('two', '注册')); saved.projects[0].entries = clone(saved.session.entries);
  const sessionValues = new Map([['langpack-provider-session-v1', JSON.stringify({ DeepL: { apiKey: 'fixture-bad-key', plan: 'free' }, Azure: { apiKey: 'fixture-next-key' } })]]);
  const calls = [];
  const app = boot(saved, undefined, { sessionValues, providerFetch: async (_, options) => { calls.push(JSON.parse(options.body).provider); return new Response(JSON.stringify({ provider: 'DeepL', code: 'PROVIDER_AUTH', message: 'fixture-bad-key', fatal: true }), { status: 401 }); } }); t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'blocked');
  assert.deepEqual(calls, ['DeepL']); assert.equal(app.state().jobs[0].items[1].status, 'pending');
  assert.doesNotMatch(JSON.stringify(app.state()), /fixture-bad-key|fixture-next-key/);
});

test('developer verification is a zero-budget status request and saved ZTAI developer authorization never includes a tenant or API key', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['ZTAITrans'];
  const statuses = [], translations = [];
  const app = boot(saved, undefined, { sessionValues: new Map(), fetch: async (url, options) => { statuses.push({ url, options }); return new Response(JSON.stringify({ developerConfigured: true, backupConfigured: true })); }, providerFetch: async (_, options) => { translations.push(JSON.parse(options.body)); return new Response(JSON.stringify({ provider: 'ZTAITrans', text: 'Developer result' })); } }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); app.field('provider-ZTAITrans-developer', 'fixture-developer-token'); app.field('provider-ZTAITrans-mode', 'developer'); app.field('provider-ZTAITrans-tenant', 'must-not-forward');
  await app.click('verify-developer'); assert.equal(statuses.length, 1); assert.equal(statuses[0].url, '/api/translation/status'); assert.equal(statuses[0].options.headers['X-LangPack-Developer-Token'], 'fixture-developer-token'); assert.equal(statuses[0].options.body, undefined); assert.equal(translations.length, 0);
  await app.click('save-provider-credentials', { provider: 'ZTAITrans' });
  assert.doesNotMatch(app.html(), /fixture-developer-token/); assert.doesNotMatch(JSON.stringify(app.state()), /fixture-developer-token/);
  await app.click('project', { id: 'a' }); await app.click('translate-project'); await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.deepEqual(translations[0].credentials, { developerToken: 'fixture-developer-token' });
});

test('saving a new provider account pauses an active request; its late result cannot overwrite the resumed account result', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['DeepL'];
  const sessionValues = new Map([['langpack-provider-session-v1', JSON.stringify({ DeepL: { apiKey: 'fixture-old-account', plan: 'free' } })]]);
  const first = deferred(); let calls = 0, oldSignal;
  const app = boot(saved, undefined, { sessionValues, providerFetch: async (_, options) => { calls++; if (calls === 1) { oldSignal = options.signal; return first.promise; } assert.equal(JSON.parse(options.body).credentials.apiKey, 'fixture-new-account'); return new Response(JSON.stringify({ provider: 'DeepL', text: 'New account result' })); } }); t.after(() => app.close());
  await app.click('start-translation'); await app.click('nav', { view: 'settings' }); app.field('provider-DeepL-key', 'fixture-new-account'); app.field('provider-DeepL-plan', 'free');
  await app.click('save-provider-credentials', { provider: 'DeepL' });
  assert.equal(oldSignal.aborted, true); assert.equal(app.state().session.status, 'paused');
  first.resolve(new Response(JSON.stringify({ provider: 'DeepL', text: 'Old account result' }))); await new Promise(resolve => setImmediate(resolve));
  await app.click('open-job', { id: app.state().jobs[0].id }); await app.click('resume-translation'); await until(() => app.state().session.status === 'completed');
  assert.equal(calls, 2); assert.equal(app.state().session.entries[0].translations.en, 'New account result');
});

test('changing the MyMemory contact identity pauses active work and resumes with the newly configured email', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['MyMemory'];
  const first = deferred(), configs = []; let calls = 0;
  const app = boot(saved, async () => ++calls === 1 ? first.promise : ({ provider: 'MyMemory', text: 'New identity result' }), { sessionValues: new Map(), onPrimaryConfig: value => configs.push(value) }); t.after(() => app.close());
  await app.click('start-translation'); await app.click('nav', { view: 'settings' }); app.field('translation-email', 'new-owner@example.com'); await app.click('save-translation-settings');
  assert.equal(app.state().session.status, 'paused');
  first.resolve({ provider: 'MyMemory', text: 'Old anonymous result' }); await new Promise(resolve => setImmediate(resolve));
  await app.click('open-job', { id: app.state().jobs[0].id }); await app.click('resume-translation'); await until(() => app.state().session.status === 'completed');
  assert.deepEqual(configs.map(value => value.email), ['', 'new-owner@example.com']);
  assert.equal(app.state().session.entries[0].translations.en, 'New identity result');
});

test('domestic platform forms save exact BYOK pairs, retain secrets outside projects and reuse successful translations after credential deletion', async t => {
  const forms = {
    Baidu: { appId: 'fixture-baidu-app', secretKey: 'fixture-baidu-private' },
    Tencent: { secretId: 'fixture-tencent-id', secretKey: 'fixture-tencent-private' },
    Alibaba: { accessKeyId: 'fixture-alibaba-id', accessKeySecret: 'fixture-alibaba-private' }
  };
  for (const [provider, credentials] of Object.entries(forms)) await t.test(provider, async () => {
    const saved = fixture(['en']); saved.settings.providerOrder = ['MyMemory'];
    const requests = [];
    const app = boot(saved, undefined, { sessionValues: new Map(), providerFetch: async (url, options) => { requests.push({ url, body: JSON.parse(options.body) }); return new Response(JSON.stringify({ provider, text: provider + ' result' })); } }); t.after(() => app.close());
    await app.click('nav', { view: 'settings' }); await app.change({ id: 'primary-provider', value: provider, dataset: {} });
    assert.match(app.html(), /8 个平台/);
    const [identity, secret] = Object.keys(credentials);
    app.field(`provider-${provider}-${identity}`, credentials[identity]);
    await app.click('save-provider-credentials', { provider });
    assert.equal(app.sessionValues.get('langpack-provider-session-v1'), undefined);
    app.field(`provider-${provider}-${secret}`, credentials[secret]);
    await app.click('save-provider-credentials', { provider });
    for (const value of Object.values(credentials)) { assert.doesNotMatch(JSON.stringify(app.state()), new RegExp(value)); assert.doesNotMatch(app.html(), new RegExp(value)); }
    assert.equal(app.localValues.get('langpack-provider-credentials-v1'), undefined);
    await app.click('project', { id: 'a' }); await app.click('translate-project'); await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
    const expected = provider === 'Tencent' ? { ...credentials, region: 'ap-guangzhou' } : credentials;
    assert.equal(requests.length, 1); assert.equal(requests[0].url, '/api/translation/provider'); assert.equal(requests[0].body.provider, provider); assert.deepEqual(requests[0].body.credentials, expected);
    assert.equal(app.state().session.entries[0].translationMeta.en.provider, provider);
    for (const value of Object.values(credentials)) assert.doesNotMatch(JSON.stringify(app.engine.makePackages(app.state().session.entries, ['en'], true)), new RegExp(value));
    await app.click('nav', { view: 'settings' }); await app.click('delete-provider-credentials', { provider });
    assert.equal(app.sessionValues.get('langpack-provider-session-v1'), undefined);
    await app.click('project', { id: 'a' }); await app.click('translate-project'); await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
    assert.equal(requests.length, 1); assert.equal(app.state().jobs[0].items[0].reused, true);
  });
});

test('saving each of the eight platform cards validates the saved snapshot once and keeps the result separate from storage and translation tasks', async t => {
  const forms = {
    MyMemory: { key: 'fixture-memory-private' }, ZTAITrans: { key: 'fixture-ztai-private', mode: 'apiKey', tenant: 'fixture-tenant' },
    DeepL: { key: 'fixture-deepl-private', plan: 'free' }, Azure: { key: 'fixture-azure-private', region: 'eastasia' }, Google: { key: 'fixture-google-private' },
    Baidu: { appId: 'fixture-baidu-app', secretKey: 'fixture-baidu-private' }, Tencent: { secretId: 'fixture-tencent-id', secretKey: 'fixture-tencent-private', region: 'ap-guangzhou' }, Alibaba: { accessKeyId: 'fixture-alibaba-id', accessKeySecret: 'fixture-alibaba-private' }
  };
  for (const [provider, fields] of Object.entries(forms)) await t.test(provider, async () => {
    const saved = fixture(['en']); saved.settings.providerOrder = [provider];
    const calls = [];
    const app = boot(saved, undefined, { sessionValues: new Map(), fetch: async (url, options) => {
      const body = JSON.parse(options.body); calls.push({ url, options, body });
      const method = ['DeepL', 'Google'].includes(provider) ? 'metadata' : 'translation';
      return new Response(JSON.stringify({ provider, status: 'valid', message: Object.values(fields).join(' '), method, billableCharacters: method === 'translation' ? 1 : 0 }));
    }, providerFetch: async () => assert.fail('Validation must not invoke the translation client') }); t.after(() => app.close());
    await app.click('nav', { view: 'settings' });
    for (const [field, value] of Object.entries(fields)) app.field(`provider-${provider}-${field}`, value);
    await app.click('save-provider-credentials', { provider });
    assert.equal(calls.length, 1); assert.equal(calls[0].url, '/api/translation/validate'); assert.equal(calls[0].options.method, 'POST');
    assert.deepEqual(Object.keys(calls[0].body).sort(), ['credentials', 'provider']); assert.equal(calls[0].body.provider, provider);
    const vault = JSON.parse(app.sessionValues.get('langpack-provider-session-v1')); assert.deepEqual(calls[0].body.credentials, vault[provider]);
    const feedback = app.content(`provider-${provider}-feedback`);
    assert.match(feedback, /仅保留在当前标签页会话/); assert.match(feedback, /上次校验尝试/);
    assert.match(feedback, ['DeepL', 'Google'].includes(provider) ? /授权检查通过，本次未试译/ : /上次单字试译通过/);
    for (const value of Object.values(fields).filter(value => value.startsWith('fixture-'))) { assert.doesNotMatch(feedback, new RegExp(value)); assert.doesNotMatch(JSON.stringify(app.state()), new RegExp(value)); }
    assert.equal(app.state().jobs.length, 0); assert.equal(app.state().exports.length, 0); assert.equal(app.disabled(`provider-${provider}-save`), false);
  });
});

test('anonymous MyMemory validation records no trial and does not claim that the service was checked', async t => {
  const app = boot(fixture(['en']), undefined, { sessionValues: new Map(), fetch: async () => new Response(JSON.stringify({ provider: 'MyMemory', status: 'valid', method: 'anonymous', billableCharacters: 0, message: 'must not be rendered' })) }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); await app.click('save-provider-credentials', { provider: 'MyMemory' });
  assert.match(app.content('provider-MyMemory-feedback'), /无需私有凭据.*未检查服务、未试译/);
  assert.doesNotMatch(app.content('provider-MyMemory-feedback'), /1 字符|must not be rendered/);
});

test('validation failures keep credentials saved and classify transport errors without rendering private response strings', async t => {
  const secret = 'fixture-private-validation-key';
  for (const [name, responseFactory, expected] of [
    ['invalid', () => new Response(JSON.stringify({ provider: 'Azure', status: 'invalid', method: 'translation', billableCharacters: 1, message: secret })), 'invalid'],
    ['limited', () => new Response(JSON.stringify({ provider: 'Azure', status: 'limited', method: 'translation', billableCharacters: 1, message: secret })), 'limited'],
    ['network', () => { throw new Error(secret); }, 'unavailable'],
    ['unauthorized', () => new Response(secret, { status: 401 }), 'invalid'],
    ['bad request', () => new Response(secret, { status: 400 }), 'invalid'],
    ['forbidden', () => new Response(secret, { status: 403 }), 'invalid'],
    ['invalid shape', () => new Response(secret, { status: 422 }), 'invalid'],
    ['quota', () => new Response(secret, { status: 402 }), 'limited'],
    ['rate limited', () => new Response(secret, { status: 429 }), 'limited'],
    ['server unavailable', () => new Response(secret, { status: 503 }), 'unavailable'],
    ['wrong provider', () => new Response(JSON.stringify({ provider: 'Google', status: 'valid', method: 'metadata', billableCharacters: 0, message: secret })), 'unavailable'],
    ['wrong method', () => new Response(JSON.stringify({ provider: 'Azure', status: 'valid', method: 'metadata', billableCharacters: 0, message: secret })), 'unavailable'],
    ['wrong character count', () => new Response(JSON.stringify({ provider: 'Azure', status: 'valid', method: 'translation', billableCharacters: 0, message: secret })), 'unavailable']
  ]) await t.test(name, async () => {
    let calls = 0;
    const app = boot(fixture(['en']), undefined, { sessionValues: new Map(), fetch: async () => { calls++; return responseFactory(); } }); t.after(() => app.close());
    await app.click('nav', { view: 'settings' }); app.field('provider-Azure-key', secret); app.field('provider-Azure-region', 'eastasia'); await app.click('save-provider-credentials', { provider: 'Azure' });
    assert.equal(calls, 1); assert.match(app.sessionValues.get('langpack-provider-session-v1'), new RegExp(secret));
    const feedback = app.content('provider-Azure-feedback'); assert.match(feedback, new RegExp(`data-validation-status="${expected}"`));
    assert.match(feedback, /仅保留在当前标签页会话/); assert.doesNotMatch(feedback, new RegExp(secret)); assert.doesNotMatch(JSON.stringify(app.state()), new RegExp(secret)); assert.deepEqual(app.errors, []);
  });
});

test('validation disables repeat submissions and patches feedback without clearing another card input', async t => {
  const pending = deferred(); let calls = 0;
  const app = boot(fixture(['en']), undefined, { sessionValues: new Map(), fetch: async () => { calls++; return pending.promise; } }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); app.field('provider-Azure-key', 'fixture-azure-key'); app.field('provider-Azure-region', 'eastasia');
  const saving = app.click('save-provider-credentials', { provider: 'Azure' });
  assert.equal(app.disabled('provider-Azure-save'), true); assert.match(app.content('provider-Azure-feedback'), /正在验证当前已保存的配置/);
  await app.click('save-provider-credentials', { provider: 'Azure' }); await app.click('validate-provider', { provider: 'Azure' }); assert.equal(calls, 1);
  app.field('provider-Google-key', 'fixture-unsaved-google-key');
  pending.resolve(new Response(JSON.stringify({ provider: 'Azure', status: 'valid', method: 'translation', billableCharacters: 1 })));
  await saving;
  assert.equal(app.disabled('provider-Azure-save'), false); assert.equal(app.value('provider-Google-key'), 'fixture-unsaved-google-key');
  assert.match(app.content('provider-Azure-feedback'), /上次单字试译通过/);
});

test('same credentials with only a storage preference change reuse the session result; explicit revalidation does not reset translation clients', async t => {
  const saved = fixture(['en']); saved.settings.providerOrder = ['Azure']; let validations = 0, translations = 0, clients = 0;
  const app = boot(saved, undefined, { sessionValues: new Map(), onProviderClient() { clients++; }, fetch: async () => { validations++; return new Response(JSON.stringify({ provider: 'Azure', status: 'valid', method: 'translation', billableCharacters: 1 })); }, providerFetch: async () => { translations++; return new Response(JSON.stringify({ provider: 'Azure', text: 'Saved translation' })); } }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); app.field('provider-Azure-key', 'fixture-azure-key'); app.field('provider-Azure-region', 'eastasia'); await app.click('save-provider-credentials', { provider: 'Azure' });
  app.field('provider-Azure-remember', '').checked = true; await app.click('save-provider-credentials', { provider: 'Azure' });
  assert.equal(validations, 1); assert.match(app.content('provider-Azure-feedback'), /已保存到本机浏览器/);
  await app.click('project', { id: 'a' }); await app.click('translate-project'); await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.equal(clients, 1); assert.equal(translations, 1);
  await app.click('nav', { view: 'settings' }); const before = JSON.stringify(app.state()); const vaultBefore = app.localValues.get('langpack-provider-credentials-v1');
  await app.click('validate-provider', { provider: 'Azure' }); assert.equal(validations, 2); assert.equal(JSON.stringify(app.state()), before); assert.equal(app.localValues.get('langpack-provider-credentials-v1'), vaultBefore);
  await app.click('project', { id: 'a' }); await app.click('translate-project'); await app.click('start-translation'); await until(() => app.state().session.status === 'completed');
  assert.equal(clients, 1); assert.equal(translations, 1);
});

test('validation snapshots and per-platform operation tokens reject late results after replacement, deletion and reset', async t => {
  for (const action of ['replace', 'delete', 'reset']) await t.test(action, async () => {
    const old = deferred(), snapshots = []; let signal;
    const app = boot(fixture(['en']), undefined, { sessionValues: new Map(), fetch: async (_, options) => { snapshots.push(JSON.parse(options.body)); if (snapshots.length === 1) { signal = options.signal; return old.promise; } return new Response(JSON.stringify({ provider: 'Azure', status: 'invalid', method: 'translation', billableCharacters: 1 })); } }); t.after(() => app.close());
    await app.click('nav', { view: 'settings' }); app.field('provider-Azure-key', 'fixture-old-key'); app.field('provider-Azure-region', 'eastasia');
    const first = app.click('save-provider-credentials', { provider: 'Azure' });
    if (action === 'replace') { app.field('provider-Azure-key', 'fixture-new-key'); await app.click('save-provider-credentials', { provider: 'Azure' }); }
    else await app.click(action === 'delete' ? 'delete-provider-credentials' : 'reset', { provider: 'Azure' });
    assert.equal(signal.aborted, true);
    old.resolve(new Response(JSON.stringify({ provider: 'Azure', status: 'valid', method: 'translation', billableCharacters: 1, message: 'fixture-old-key' }))); await first;
    assert.equal(snapshots[0].credentials.apiKey, 'fixture-old-key');
    if (action === 'replace') { assert.equal(snapshots[1].credentials.apiKey, 'fixture-new-key'); assert.match(app.content('provider-Azure-feedback'), /data-validation-status="invalid"/); }
    else { assert.doesNotMatch(app.html(), /上次单字试译通过/); assert.equal(app.sessionValues.get('langpack-provider-session-v1'), undefined); }
    assert.doesNotMatch(JSON.stringify(app.state()), /fixture-old-key|fixture-new-key/);
  });
});

test('independent platform validations can finish in reverse order and feedback survives navigation for the current page session', async t => {
  const azure = deferred(), google = deferred();
  const app = boot(fixture(['en']), undefined, { sessionValues: new Map(), fetch: async (_, options) => JSON.parse(options.body).provider === 'Azure' ? azure.promise : google.promise }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); app.field('provider-Azure-key', 'fixture-azure-key'); app.field('provider-Azure-region', 'eastasia'); const savingAzure = app.click('save-provider-credentials', { provider: 'Azure' });
  app.field('provider-Google-key', 'fixture-google-key'); const savingGoogle = app.click('save-provider-credentials', { provider: 'Google' });
  google.resolve(new Response(JSON.stringify({ provider: 'Google', status: 'valid', method: 'metadata', billableCharacters: 0 }))); await savingGoogle;
  azure.resolve(new Response(JSON.stringify({ provider: 'Azure', status: 'valid', method: 'translation', billableCharacters: 1 }))); await savingAzure;
  assert.equal(app.disabled('provider-Azure-save'), false); assert.equal(app.disabled('provider-Google-save'), false);
  assert.match(app.content('provider-Azure-feedback'), /上次单字试译通过/); assert.match(app.content('provider-Google-feedback'), /授权检查通过，本次未试译/);
  await app.click('project', { id: 'a' }); await app.click('nav', { view: 'settings' });
  assert.match(app.html(), /上次单字试译通过/); assert.match(app.html(), /授权检查通过，本次未试译/); assert.match(app.html(), /仅本次会话/);
});

test('validation timeout keeps the saved credentials and ends the checking state without retrying', async t => {
  let calls = 0;
  const app = boot(fixture(['en']), undefined, { validationTimeoutMs: 1, sessionValues: new Map(), fetch: async () => { calls++; return new Promise(() => {}); } }); t.after(() => app.close());
  await app.click('nav', { view: 'settings' }); app.field('provider-Azure-key', 'fixture-timeout-key'); app.field('provider-Azure-region', 'eastasia'); await app.click('save-provider-credentials', { provider: 'Azure' });
  assert.equal(calls, 1); assert.equal(app.disabled('provider-Azure-save'), false); assert.match(app.content('provider-Azure-feedback'), /data-validation-status="unavailable"/); assert.match(app.sessionValues.get('langpack-provider-session-v1'), /fixture-timeout-key/);
});
