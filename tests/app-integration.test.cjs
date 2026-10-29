const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');
const path = require('node:path');

const dist = path.join(__dirname, '../dist');
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
    jobs: [], exports: [], settings: { includeSource: true, pretty: true, translationEmail: '' }, homeFilter: 'all', search: '', reviewLocale: 'en', reviewIndex: 0
  };
}
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }

function boot(saved, translate = async () => { throw new Error('Unexpected translation request'); }) {
  const values = new Map([[STORAGE, JSON.stringify(saved)]]);
  const handlers = new Map(), errors = [], elements = new Map();
  let html = '';
  function element(id) {
    if (!elements.has(id)) elements.set(id, { id, dataset: {}, innerHTML: '', textContent: '', value: '', open: false, disabled: false, classList: { add() {}, remove() {} }, addEventListener() {}, focus() {}, close() { this.open = false; }, showModal() { this.open = true; }, getBoundingClientRect() { return { left: 0, right: 400, top: 0, bottom: 400 }; } });
    return elements.get(id);
  }
  const app = element('app');
  Object.defineProperty(app, 'innerHTML', { get() { return html; }, set(value) { html = String(value); } });
  element('toast'); element('modal');
  const document = {
    querySelector(selector) {
      if (selector[0] !== '#') return null;
      const id = selector.slice(1);
      if (['app', 'toast', 'modal'].includes(id) || html.includes('id="' + id + '"')) return element(id);
      return null;
    },
    addEventListener(type, handler) { if (!handlers.has(type)) handlers.set(type, []); handlers.get(type).push(handler); }
  };
  const timers = new Set();
  const context = vm.createContext({
    document, localStorage: { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, String(value)) },
    TextEncoder, TextDecoder, AbortController, Blob, URL, crypto: webcrypto,
    console: { log() {}, warn() {}, error(...args) { errors.push(args); } },
    setTimeout(callback, ms) { const timer = setTimeout(() => { timers.delete(timer); callback(); }, Math.min(ms, 10)); timers.add(timer); return timer; },
    clearTimeout(timer) { timers.delete(timer); clearTimeout(timer); }
  });
  context.window = context; context.addEventListener = () => {}; context.scrollTo = () => {};
  vm.runInContext(code('engine.js'), context);
  vm.runInContext(code('translation-jobs.js'), context);
  context.MyMemoryTranslator = { createClient: () => ({ translate }), utf8Length: value => new TextEncoder().encode(value).length };
  vm.runInContext(code('app.js'), context);
  return {
    state: () => JSON.parse(values.get(STORAGE)), html: () => html, errors,
    async click(action, extra = {}) {
      const button = { dataset: { action, ...extra }, disabled: false, closest() { return this; } };
      for (const handler of handlers.get('click') || []) await handler({ target: button });
    },
    field(id, value) { const target = document.querySelector('#' + id); assert.ok(target, 'Visible field ' + id); target.value = value; return target; },
    async input(id, value) { const target = this.field(id, value); for (const handler of handlers.get('input') || []) await handler({ target }); },
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

test('quota errors stop batch, preserve pending cells and remain visible in actual UI', async t => {
  let count = 0;
  const app = boot(fixture(), async () => { count++; throw Object.assign(new Error('Daily quota exhausted'), { code: 'QUOTA', quota: true }); });
  t.after(() => app.close());
  await app.click('start-translation'); await until(() => app.state().session.status === 'quota');
  const state = app.state();
  assert.equal(count, 1); assert.equal(state.jobs[0].items[1].status, 'pending');
  assert.equal(state.projects[0].entries[0].translations.en, undefined);
  assert.match(app.html(), /今日免费额度已用完/); assert.match(app.html(), /Daily quota exhausted/);
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
