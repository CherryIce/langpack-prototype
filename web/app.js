(function () {
  'use strict';
  const E = window.LangPackEngine;
  const M = window.MyMemoryTranslator;
  const T = window.TranslationService;
  const J = window.LangPackJobs;
  const P = window.LangPackProviders;
  const storageFor = name => { try { return window[name]; } catch (_) { return undefined; } };
  const credentialVault = P.createVault({ sessionStorage: storageFor('sessionStorage'), localStorage: storageFor('localStorage') });
  let providerRevision = 0;
  const providerCircuits = {};
  const providerValidation = new Map();
  const providerValidationVersions = new Map();
  const $ = (selector, root = document) => root.querySelector(selector);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const uid = () => crypto.randomUUID ? crypto.randomUUID() : 'id_' + Date.now().toString(36) + Math.random().toString(36).slice(2);
  const ICONS = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    layers: '<path d="m12 3 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5M3 16l9 5 9-5"/>',
    tasks: '<rect x="4" y="4" width="16" height="17" rx="2"/><path d="M9 3h6v4H9zM8 12l1.5 1.5L12 11M14 12h3M8 17h9"/>',
    download: '<path d="M12 3v12m-4-4 4 4 4-4M4 16v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/>',
    settings: '<path d="m9 3-1 3-3 1-2 4 2 2v3l3 3 3-1 3 2 4-2v-3l3-2-1-4-3-1-1-3-4-1Z"/><circle cx="12" cy="12" r="3"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    right: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
    left: '<path d="M19 12H5m5-5-5 5 5 5"/>',
    chevron: '<path d="m9 5 7 7-7 7"/>',
    down: '<path d="m6 9 6 6 6-6"/>',
    globe: '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
    file: '<path d="M13 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V10Z"/><path d="M13 3v7h7M8 14h8M8 17h6"/>',
    text: '<path d="M4 5h16M12 5v15M8 20h8M4 5v4M20 5v4"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
    help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.6 2.2c-.9.4-1.1 1-1.1 1.8M12 17h.01"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    circlecheck: '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
    shield: '<path d="m12 3 8 3v5c0 5-4 8-8 10-4-2-8-5-8-10V6Z"/><path d="m8 12 3 3 5-6"/>',
    upload: '<path d="M12 16V3m-4 4 4-4 4 4M4 15v5h16v-5"/>',
    code: '<path d="m8 6-6 6 6 6m8-12 6 6-6 6m-3-14-2 16"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    sparkles: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3ZM20 2v4m-2-2h4"/>',
    key: '<circle cx="8" cy="8" r="4"/><path d="m11 11 9 9m-3-3 3-3m-6 0 3-3"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    copy: '<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V3H3v13h5"/>',
    refresh: '<path d="M20 7v5h-5M4 17v-5h5M6.1 6.1A8 8 0 0 1 20 12M4 12a8 8 0 0 0 13.9 5.9"/>',
    alert: '<path d="m12 3 10 18H2Z"/><path d="M12 9v5m0 3h.01"/>',
    book: '<path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15"/>',
    folder: '<path d="M3 6a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/>',
    edit: '<path d="m16 3 5 5L9 20l-6 1 1-6ZM13 6l5 5"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    switch: '<path d="M3 7h16m-4-4 4 4-4 4M21 17H5m4-4-4 4 4 4"/>',
    bolt: '<path d="m13 2-9 12h7l-1 8 10-12h-8Z"/>'
  };
  const icon = name => '<svg viewBox="0 0 24 24" aria-hidden="true">' + (ICONS[name] || ICONS.file) + '</svg>';
  const LANGS = window.LangPackLanguages.targets;
  const normalizeLocales = window.LangPackLanguages.normalizeTargets;
  function defaultLocales(fallback = []) {
    const recent = normalizeLocales(state.settings.recentLocales);
    const previous = normalizeLocales(fallback);
    return recent.length ? recent : previous.length ? previous : ['en', 'ja', 'ko'];
  }
  const lang = code => LANGS.find(x => x.code === code) || { code, name: code === 'zh-Hans' ? '简体中文' : code, native: '', label: code };
  const textOf = value => value && typeof value === 'object' ? String(value.text ?? '') : String(value ?? '');
  const STORAGE = 'langpack-prototype-v1';
  const SAMPLE = '登录\n注册账号\n忘记密码\n欢迎回来，{name}\n保存更改\n开启通知';
  const DOC_SAMPLE = '欢迎使用译包。\n\n一次输入，即可生成多种语言的翻译结果。\n\n为每一段中文生成稳定的语义 key。\n\n按语言导出 JSON，让本地化更简单。';
  let toastTimer, saveTimer, importRequest = 0, batchGeneration = 0, languageSearch = '';
  let batchController = null, singleController = null, singleRequest = null;
  const translationClients = new Map();
  const isRealJob = job => !!job && (job.provider === 'TranslationChain' || P.known(job.provider)) && Array.isArray(job.items);
  function translationClient() {
    const email = state.settings.translationEmail || '';
    const cacheKey = providerRevision + ':' + credentialVault.revision;
    if (!translationClients.has(cacheKey)) {
      const clients = {};
      for (const provider of state.settings.providerOrder) clients[provider] = provider === 'MyMemory' && !credentialVault.has(provider) ? M.createClient({ email }) : T.createProviderClient({ provider, getCredentials: () => ({ ...credentialVault.get(provider), ...(provider === 'MyMemory' && email ? { email } : {}) }), getRevision: () => credentialVault.revision });
      providerCircuits.MyMemory ||= state.settings.primaryCircuit;
      translationClients.set(cacheKey, T.createOrderedClient({ order: state.settings.providerOrder, fallback: state.settings.providerFallback, clients, circuits: providerCircuits,
        onFallback(info) { state.settings.lastFallback = { ...info, at: new Date().toISOString() }; persist(); toast(`${info.from} ${info.reason === 'quota' ? '额度暂不可用' : '不支持该语言'}，已切换 ${info.to}。`); }
      }));
    }
    return translationClients.get(cacheKey);
  }
  let storageFailed = false;
  let backupConfiguration = 'unknown';
  function seedEntries(text, locales, complete = true) {
    return E.splitText(text, 'line').map(entry => {
      locales.forEach(locale => { entry.translations[locale] = ''; entry.reviewed[locale] = false; });
      return entry;
    });
  }
  function initialState() {
    const now = new Date().toISOString();
    return { version: 2, view: 'home', currentProjectId: 'mono-app', projects: [
      { id: 'mono-app', name: 'Mono App', description: '让产品的每一句话，都被世界读懂。', locales: ['en', 'ja', 'ko'], icon: 'layers', color: '', entries: seedEntries(SAMPLE + '\n退出登录\n取消', ['en', 'ja', 'ko']), updatedAt: now, sample: true },
      { id: 'product-guide', name: '产品介绍', description: '产品简介与新手引导的多语言文案。', locales: ['en', 'fr', 'ja'], icon: 'book', color: 'blue', entries: seedEntries(DOC_SAMPLE.replace(/\n\n/g, '\n'), ['en', 'fr', 'ja'], false), updatedAt: now, sample: true }
    ], session: null, jobs: [], exports: [], settings: { includeSource: true, pretty: true, translationEmail: '', providerOrder: ['MyMemory'], providerFallback: true, primaryCircuit: { until: 0 } }, homeFilter: 'all', search: '', reviewLocale: 'en', reviewIndex: 0 };
  }
  function migrate(saved) {
    if (!saved || !Array.isArray(saved.projects) || ![1, 2].includes(saved.version)) return initialState();
    saved.settings = { includeSource: true, pretty: true, translationEmail: '', primaryCircuit: { until: 0 }, ...saved.settings };
    saved.settings.recentLocales = normalizeLocales(saved.settings.recentLocales);
    const order = P.normalizeOrder(saved.settings.providerOrder);
    saved.settings.providerOrder = order.length ? order : ['MyMemory'];
    saved.settings.providerFallback = saved.settings.providerFallback !== false;
    if (!saved.settings.primaryCircuit || !Number.isFinite(saved.settings.primaryCircuit.until)) saved.settings.primaryCircuit = { until: 0 };
    saved.jobs ||= []; saved.exports ||= [];
    if (saved.version === 1) {
      const entries = [...saved.projects.flatMap(p => p.entries), ...(saved.session?.entries || []), ...saved.jobs.flatMap(j => j.entries || [])];
      entries.forEach(entry => {
        entry.translationMeta ||= {}; entry.translationRevision ||= {};
        Object.entries(entry.translations || {}).forEach(([locale, value]) => {
          if (textOf(value).trim() && !entry.translationMeta[locale]) {
            entry.translationMeta[locale] = { provider: entry.edited?.[locale] ? 'manual' : 'LegacyDemo', status: 'success', sourceText: entry.source };
            if (!entry.edited?.[locale]) {
              entry.translationMeta[locale].legacyReviewed = !!entry.reviewed?.[locale];
              entry.reviewed ||= {}; entry.reviewed[locale] = false;
            }
          }
        });
      });
      saved.jobs.forEach(job => { job.provider ||= 'LegacyDemo'; });
      saved.version = 2;
    }
    saved.jobs.filter(isRealJob).forEach(job => J.normalize(job));
    return saved;
  }
  let state;
  try { state = migrate(JSON.parse(localStorage.getItem(STORAGE))); }
  catch { state = initialState(); }
  if (state.session) state.session.importing = false;
  if (state.session?.status === 'running') { state.session.status = 'paused'; const job = state.jobs.find(j => j.id === state.session.jobId); if (job) job.status = 'paused'; }
  if (state.view === 'translate' && !state.session) state.view = 'home';
  if (['review', 'export', 'languages', 'input', 'import'].includes(state.view) && !state.session) state.view = 'home';
  function persist() {
    try { localStorage.setItem(STORAGE, JSON.stringify(state)); }
    catch { if (!storageFailed) { storageFailed = true; toast('浏览器存储空间不足，当前内容请及时导出。'); } }
  }
  function saveSoon() { clearTimeout(saveTimer); saveTimer = setTimeout(persist, 180); }
  const currentProject = () => state.projects.find(p => p.id === state.currentProjectId) || state.projects[0];
  const sessionProject = () => state.projects.find(p => p.id === state.session?.projectId) || currentProject();
  const sessionEntries = () => state.session?.entries || [];
  const selectedEntries = () => sessionEntries().filter(e => e.selected !== false);
  const sessionJob = () => state.jobs.find(job => job.id === state.session?.jobId);
  function translationLabel(entry, locale) {
    const meta = entry.translationMeta?.[locale];
    if (entry.reviewed?.[locale]) return '已人工确认';
    if (entry.edited?.[locale]) return '人工译文 · 待确认';
    if (meta?.provider === 'LegacyDemo') return '历史演示译文';
    if (meta?.status === 'failed') return '翻译失败';
    return textOf(entry.translations[locale]).trim() ? `${P.known(meta?.provider) ? meta.provider : '来源待核对'} · 待校对` : '待翻译';
  }
  function markManual(entry, locale) {
    entry.edited ||= {}; entry.edited[locale] = true;
    entry.translationRevision ||= {}; entry.translationRevision[locale] = (entry.translationRevision[locale] || 0) + 1;
    entry.translationMeta ||= {}; entry.translationMeta[locale] = { provider: 'manual', status: 'success', sourceText: entry.source };
  }
  function cancelSingle() { singleController?.abort(); singleController = null; singleRequest = null; }
  const titleFor = { home: '我的项目', project: '项目文案', input: '文本输入', import: '文档导入', languages: '目标语言', translate: '翻译任务', review: '翻译校对', export: 'JSON 导出', tasks: '翻译任务', exports: '导出记录', settings: '偏好设置' };
  function nav(view) { if (['input', 'import', 'languages', 'translate', 'review', 'export'].includes(view) && state.session) state.currentProjectId = state.session.projectId; state.view = view; state.search = ''; persist(); render(); window.scrollTo({ top: 0 }); }
  function toast(message) { const el = $('#toast'); el.textContent = message; el.classList.add('show'); clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove('show'), 3200); }
  function stats(project) {
    const total = project.entries.length * project.locales.length;
    const complete = project.entries.reduce((sum, e) => sum + project.locales.filter(l => textOf(e.translations[l]).trim()).length, 0);
    return { total, complete, ratio: total ? Math.round(complete / total * 100) : 0 };
  }
  function navLink(view, name, glyph, mobile = false) {
    let active = view === state.view || view === 'home' && ['project', 'input', 'import', 'languages', 'review', 'export'].includes(state.view) || view === 'tasks' && state.view === 'translate';
    return `<button class="${mobile ? 'mobile-nav-link' : 'nav-link'} ${active ? 'active' : ''}" data-action="nav" data-view="${view}" ${active ? 'aria-current="page"' : ''}>${icon(glyph)}<span>${name}</span>${!mobile && view === 'home' ? `<span class="nav-count">${state.projects.length}</span>` : ''}</button>`;
  }
  function shell(content) {
    const project = currentProject();
    const inFlow = ['project', 'input', 'import', 'languages', 'translate', 'review', 'export'].includes(state.view);
    return `<aside class="sidebar"><button class="brand" data-action="nav" data-view="home" aria-label="译包，返回项目首页"><div class="brand-logo"><span>译</span><sup>A</sup></div><div><div class="brand-title">译包<span style="font-size:13px;font-weight:400;margin-left:6px;color:#839d8b">LangPack</span></div><div class="brand-sub">让语言，轻松相通</div></div></button><div class="workspace-label">WORKSPACE</div><nav class="main-nav" aria-label="主导航">${navLink('home', '我的项目', 'grid')}${navLink('tasks', '翻译任务', 'tasks')}${navLink('exports', '导出记录', 'download')}${navLink('settings', '偏好设置', 'settings')}</nav><div class="sidebar-bottom"><div class="tip-box">${icon('sparkles')}<h3>从一句中文开始</h3><p>语义 key、多语言翻译、JSON 导出，一次完成。</p><button class="text-button" data-action="help">了解工作流程 ${icon('right')}</button></div><button class="user-button" data-action="nav" data-view="settings"><div class="avatar">L</div><div class="user-info"><strong>我的工作空间</strong><span>保存在当前浏览器</span></div>${icon('down')}</button></div></aside><div class="app-shell"><header class="topbar"><div class="breadcrumb">${icon('folder')}<button data-action="nav" data-view="home">工作空间</button>${icon('chevron')}${inFlow ? `<button data-action="project" data-id="${esc(project?.id || '')}">${esc(project?.name || '项目')}</button>${icon('chevron')}` : ''}<span>${titleFor[state.view]}</span></div><div class="top-actions"><span class="demo-indicator"><i></i>多平台真实翻译</span><button class="icon-button" data-action="help" aria-label="使用帮助">${icon('help')}</button><button class="top-avatar" data-action="nav" data-view="settings" aria-label="工作空间设置">L</button></div></header><main class="main" id="main-content">${content}</main></div><nav class="mobile-bottom" aria-label="底部导航">${navLink('home', '项目', 'grid', true)}${navLink('tasks', '任务', 'tasks', true)}${navLink('exports', '导出', 'download', true)}${navLink('settings', '设置', 'settings', true)}</nav>`;
  }
  function pageHead(title, subtitle, action = '', eyebrow = '') { return `<div class="page-head between"><div>${eyebrow ? `<div class="eyebrow">${eyebrow}</div>` : ''}<h1>${title}</h1><p>${subtitle}</p></div>${action}</div>`; }
  function renderHome() {
    const allEntries = state.projects.reduce((s, p) => s + p.entries.length, 0);
    const locales = new Set(state.projects.flatMap(p => p.locales));
    return pageHead('我的项目', '把中文的灵感，带到更广阔的世界。', `<button class="btn primary" data-action="new-project">${icon('plus')}新建项目</button>`, 'YOUR LOCALIZATION WORKSPACE') +
    `<section class="home-hero"><div class="hero-copy"><div class="eyebrow">WRITE ONCE. REACH EVERYWHERE.</div><h2>从一句中文，<br>到每一种语言。</h2><p>自动生成语义 key，批量翻译多种语言。<br>让繁琐的本地化，变得简单有序。</p><div class="hero-buttons"><button class="btn primary" data-action="quick-start">开始一段翻译 ${icon('right')}</button><button class="btn" data-action="quick-import">${icon('upload')}导入文档</button></div></div><div class="hero-visual" aria-hidden="true"><div class="hero-arrow">${icon('switch')}</div><div class="language-orbit">文 → A</div><div class="language-orbit second">あ</div><div class="code-card"><div class="file-title">${icon('file')}zh-Hans.json</div><pre>{\n  <em>"login"</em>: "登录",\n  <em>"save"</em>: "保存"\n}</pre></div><div class="code-card front"><div class="file-title">${icon('file')}en.json <span style="margin-left:auto;color:#9fc4aa">✓</span></div><pre>{\n  <em>"login"</em>: "Log in",\n  <em>"save"</em>: "Save"\n}</pre></div></div></section><div class="home-stats"><div class="home-stat"><span class="stat-icon">${icon('layers')}</span><div><strong>${state.projects.length.toString().padStart(2, '0')}</strong><p>进行中的项目</p></div></div><div class="home-stat"><span class="stat-icon">${icon('text')}</span><div><strong>${allEntries}</strong><p>已管理的文案</p></div></div><div class="home-stat"><span class="stat-icon">${icon('globe')}</span><div><strong>${locales.size.toString().padStart(2, '0')}</strong><p>覆盖的目标语言</p></div></div></div><div class="toolbar"><div class="tabs"><button class="tab ${state.homeFilter === 'all' ? 'active' : ''}" data-action="filter-projects" data-filter="all">全部项目<span>${state.projects.length}</span></button><button class="tab ${state.homeFilter === 'pending' ? 'active' : ''}" data-action="filter-projects" data-filter="pending">待完善</button></div><label class="search">${icon('search')}<input type="search" id="project-search" placeholder="搜索项目名称…" aria-label="搜索项目名称" value="${esc(state.search)}"></label></div><div class="project-grid" id="project-grid">${projectCards()}</div><div class="section-title"><h2>让本地化，井井有条</h2><span class="muted">四步完成你的语言包</span></div><div class="guide-row">${[['01', '输入或导入', '从中文文本、文档开始'], ['02', '选择语言', '一次选择，多种语言'], ['03', '翻译与校对', '稳定的 key，可编辑的译文'], ['04', '导出语言包', '独立 JSON，随时集成']].map(([n, t, s]) => `<div class="guide-step"><span class="guide-number">${n}</span><div><h3>${t}</h3><p>${s}</p></div></div>`).join('')}</div><footer class="home-footer"><span class="flex">${icon('shield')}文档本地解析 · 翻译时发送所选原文</span><span>LangPack · Made for every language</span></footer>`;
  }
  function projectCards() {
    const projects = state.projects.filter(p => (!state.search || (p.name + p.description).toLowerCase().includes(state.search.toLowerCase())) && (state.homeFilter !== 'pending' || stats(p).ratio < 100 || p.entries.some(e => p.locales.some(l => !e.reviewed[l]))));
    return projects.map(p => { const st = stats(p); return `<article class="project-card" tabindex="0" role="button" data-action="project" data-id="${esc(p.id)}" aria-label="打开项目 ${esc(p.name)}"><div class="project-top"><div class="tag-icon ${p.color}">${icon(p.icon)}</div><span class="badge ${st.ratio === 100 && st.total ? 'ok' : 'neutral'}"><i class="dot"></i>${st.ratio === 100 && st.total ? '翻译已齐全' : st.total ? '待补充译文' : '准备开始'}</span></div><h3 class="project-name">${esc(p.name)}</h3><p class="project-desc">${esc(p.description || '你的下一个多语言项目，从这里开始。')}</p><div class="project-tags">${p.locales.map(l => `<span class="language-mini">${lang(l).label}</span>`).join('')}${p.sample ? '<span class="language-mini">示例</span>' : ''}</div><div class="project-meta"><span class="flex">${icon('text')}${p.entries.length} 条文案</span><span>${st.ratio}% 已翻译 ${icon('chevron')}</span></div></article>`; }).join('') + `<button class="project-card project-add" data-action="new-project"><span class="add-circle">${icon('plus')}</span><strong>创建新项目</strong><p>让新的想法，跨越语言</p></button>`;
  }
  function workflowHeader(step, title, subtitle) {
    const labels = ['添加内容', '选择语言', '自动翻译', '校对译文', '导出 JSON'];
    return `<div class="workflow-head"><div class="workflow-title"><button class="back-btn" data-action="flow-back" aria-label="返回上一步">${icon('left')}</button><div><h1>${title}</h1><p>${subtitle}</p></div></div><span class="header-save">${icon('circlecheck')}已自动保存</span></div><div class="steps" aria-label="翻译流程">${labels.map((label, i) => `<div class="step ${i === step ? 'active' : i < step ? 'done' : ''}" ${i === step ? 'aria-current="step"' : ''}><span class="step-circle">${i < step ? icon('check') : i + 1}</span><span>${label}</span></div>`).join('')}</div>`;
  }
  function flowFooter(action, label, hint, back = true, disabled = false) { return `<div class="workflow-footer">${back ? '<button class="btn ghost" data-action="flow-back">' + icon('left') + '上一步</button>' : `<span class="muted">${hint || '内容与 key 可随时调整'}</span>`}<button class="btn primary" data-action="${action}" ${disabled ? 'disabled' : ''}>${label}${icon('right')}</button></div>`; }
  function newSession(mode, empty = false) {
    importRequest++;
    if (state.session?.status === 'running') { toast('当前翻译正在进行，请先完成或取消该任务。'); return nav('translate'); }
    cancelSingle();
    const p = currentProject();
    languageSearch = '';
    state.session = { id: uid(), projectId: p.id, mode, text: '', split: 'line', context: '', entries: [], locales: defaultLocales(p.locales), status: 'draft', fileName: '', includeSource: state.settings.includeSource, exportLocales: [], pretty: state.settings.pretty, committed: false };
    state.reviewIndex = 0;
    nav(mode === 'document' ? 'import' : 'input');
  }
  function rekeyAgainstProject(entries) {
    const used = new Set(sessionProject().entries.map(e => e.key));
    entries.forEach(entry => { if (used.has(entry.key)) entry.key = E.uniqueKey(entry.source, used); used.add(entry.key); });
    return entries;
  }
  function updateInputEntries() {
    const session = state.session;
    const previous = session.entries;
    const entries = rekeyAgainstProject(E.splitText(session.text, session.split));
    const consumed = new Set();
    entries.forEach((entry, index) => {
      const oldIndex = previous.findIndex((old, n) => !consumed.has(n) && old.source === entry.source);
      if (oldIndex >= 0) { consumed.add(oldIndex); Object.assign(entry, previous[oldIndex]); }
    });
    session.entries = entries;
    saveSoon();
  }
  function previewRows() {
    const entries = sessionEntries();
    if (!entries.length) return `<div class="empty-preview">${icon('key')}<p>输入中文后，语义 key 会出现在这里</p></div>`;
    return entries.map((entry, i) => `<div class="preview-key-row"><span class="row-index">${String(i + 1).padStart(2, '0')}</span><div><p class="source-preview">${esc(entry.source)}</p><div class="key-line">${icon('key')}<input class="key-field" data-key-index="${i}" value="${esc(entry.key)}" aria-label="第 ${i + 1} 条文案的 key"></div>${entry.keyGenerated === 'fallback' ? '<div class="source-hint">自定义文案：可手动填写语义 key</div>' : ''}</div></div>`).join('');
  }
  function renderInput() {
    const s = state.session;
    return workflowHeader(0, '添加你的中文文案', '每一句表达，都值得被更多人读懂。') + `<div class="two-columns"><section class="panel input-panel"><div class="panel-head"><div class="input-tabs grow"><button class="input-tab active" data-action="switch-mode" data-mode="text">${icon('text')}文本输入</button><button class="input-tab" data-action="switch-mode" data-mode="document">${icon('upload')}文档导入</button></div></div><div class="panel-body"><div class="between" style="margin-bottom:10px"><label class="field-label" for="source-text" style="margin:0">中文原文</label><button class="text-button" data-action="fill-example">${icon('sparkles')}使用示例</button></div><textarea class="field source-area" id="source-text" placeholder="输入中文文案，每行一条，例如：&#10;登录&#10;注册账号&#10;欢迎回来，{name}" spellcheck="false">${esc(s.text)}</textarea><div class="textarea-meta"><span id="source-count">${s.text.length} 字符 · ${s.entries.length} 条文案</span><span>支持 {name} 等占位符</span></div><div class="split-options"><span>拆分方式</span><label class="radio-label"><input type="radio" name="split" value="line" ${s.split === 'line' ? 'checked' : ''}>一行一条</label><label class="radio-label"><input type="radio" name="split" value="paragraph" ${s.split === 'paragraph' ? 'checked' : ''}>按空行分段</label></div><label class="field-label context-label" for="context">使用场景 <span class="muted">（选填）</span></label><textarea class="field context-field" id="context" placeholder="例如：一款效率工具的登录与设置页面">${esc(s.context)}</textarea></div><div class="panel-footer"><div class="notice">${icon('shield')}<span>key 生成后保持稳定，修改译文不会影响代码引用。key 按常用文案规则生成，自定义内容可手动命名。</span></div></div></section><section class="panel preview-panel"><div class="panel-head"><h2>语义 key 预览</h2><span class="badge ok" id="preview-count">${s.entries.length} 条</span></div><div class="panel-body" id="key-preview">${previewRows()}</div><div class="panel-footer"><div class="flex small muted">${icon('key')}<span>英文小写 + 下划线 · 点击 key 可编辑</span></div></div></section></div>${flowFooter('to-languages', '下一步：选择语言', '支持多条输入，自动拆分生成 key', false, !s.entries.length)}`;
  }
  function documentRows() {
    return sessionEntries().map((entry, i) => `<div class="doc-row"><input type="checkbox" data-doc-select="${i}" ${entry.selected ? 'checked' : ''} aria-label="选择第 ${i + 1} 段"><div><label class="field-label" style="margin-bottom:5px">${String(i + 1).padStart(2, '0')} · ${entry.sourceType === 'heading' ? '标题' : entry.sourceType === 'table-cell' || entry.sourceType === 'table' ? '表格' : '正文段落'}</label><textarea class="field" data-doc-source="${i}" rows="2" aria-label="第 ${i + 1} 段原文">${esc(entry.source)}</textarea><input class="key-field" data-key-index="${i}" value="${esc(entry.key)}" aria-label="第 ${i + 1} 段 key"><div class="doc-actions">${i < sessionEntries().length - 1 ? `<button data-action="merge-paragraph" data-index="${i}">与下段合并</button>` : ''}<button data-action="split-paragraph" data-index="${i}">按句拆分</button>${entry.keyGenerated === 'fallback' ? '<span class="muted">key 可手动命名</span>' : ''}</div></div></div>`).join('');
  }
  function renderImport() {
    const s = state.session;
    return workflowHeader(0, '从一份文档开始', '按段落整理，完整保留你的表达。') + `<div class="two-columns"><section class="panel input-panel"><div class="panel-head"><div class="input-tabs grow"><button class="input-tab" data-action="switch-mode" data-mode="text">${icon('text')}文本输入</button><button class="input-tab active" data-action="switch-mode" data-mode="document">${icon('upload')}文档导入</button></div></div><div class="panel-body"><input id="file-input" class="hidden" type="file" accept=".txt,.md,.markdown,.docx">${s.fileName ? `<div class="file-loaded"><div class="tag-icon">${icon('file')}</div><div class="grow"><h3>${esc(s.fileName)}</h3><p>${s.entries.length} 个内容块 · ${selectedEntries().length} 个已选择</p></div><button class="icon-button" data-action="pick-file" aria-label="重新选择文件">${icon('refresh')}</button></div><div style="height:16px"></div>` : ''}<div class="drop-zone" id="drop-zone"><span class="drop-icon">${icon('upload')}</span><h3>拖入文档，开始你的多语言旅程</h3><p>支持 TXT、Markdown、DOCX · 最大 10 MB</p><button class="btn" data-action="pick-file">${icon('folder')}选择文档</button></div><div class="doc-sample"><span>${icon('file')}</span><div class="grow"><h3>先用示例文档体验</h3><p>产品介绍.md · 4 个中文段落</p></div><button class="btn small-btn soft" data-action="load-doc-example">载入示例</button></div><label class="field-label context-label" for="context">文档使用场景 <span class="muted">（选填）</span></label><textarea class="field context-field" id="context" placeholder="例如：产品官网的功能介绍">${esc(s.context)}</textarea><div id="import-error" class="error-text" role="alert"></div></div><div class="panel-footer"><div class="notice">${icon('shield')}<span>文档文件在本地解析；开始翻译后，选中的段落会发送给你配置并启用的翻译平台。请先调整需要翻译的内容。</span></div></div></section><section class="panel preview-panel"><div class="panel-head"><h2>段落预览</h2><span class="badge ok">${selectedEntries().length} / ${s.entries.length} 已选</span></div><div class="panel-body document-list" style="display:block">${s.entries.length ? `<div class="bulk-actions"><button class="text-button" data-action="select-paragraphs">全选 / 取消全选</button><span>勾选需要翻译的内容</span></div>${documentRows()}` : `<div class="empty-preview">${icon('file')}<p>导入后，在这里预览与调整段落</p></div>`}</div></section></div>${flowFooter('to-languages', '下一步：选择语言', '先预览，再翻译；每段对应一个 key', false, !selectedEntries().length)}`;
  }
  function filteredLanguages() {
    const query = languageSearch.trim().toLowerCase();
    return LANGS.filter(language => !query || `${language.name} ${language.native} ${language.code}`.toLowerCase().includes(query));
  }
  function languageOptions() {
    const locales = normalizeLocales(state.session.locales);
    const visible = filteredLanguages();
    return visible.length ? visible.map(language => `<label class="language-option ${locales.includes(language.code) ? 'selected' : ''}"><span class="language-code ${language.code}">${language.label}</span><span class="language-label"><strong>${language.name}</strong><span><bdi>${language.native}</bdi> · ${language.code}${!P.supports(state.settings.providerOrder[0], language.code) ? ' · ' + state.settings.providerOrder[0] + ' 不支持' : ''}</span></span><input type="checkbox" data-locale="${language.code}" ${locales.includes(language.code) ? 'checked' : ''} aria-label="选择${language.name}"></label>`).join('') : '<p class="language-no-results">没有找到匹配的语言。已选语言继续保留，可清空搜索后调整。</p>';
  }
  function renderLanguages() {
    const s = state.session, locales = normalizeLocales(s.locales);
    const chars = selectedEntries().reduce((sum, e) => sum + e.source.length, 0);
    const plan = J.plan({ entries: selectedEntries(), locales, memoryEntries: sessionProject().entries });
    return workflowHeader(1, '想让哪些语言读懂你？', '一次多选，为每种语言生成独立的翻译结果。') + `<div class="language-layout"><section class="panel"><div class="panel-head"><h2>选择目标语言</h2><button class="text-button" data-action="toggle-all-languages">${locales.length === LANGS.length ? '取消全选' : '选择全部 34 种'}</button></div><div class="panel-body"><p class="subheading">35 种语言覆盖 · 简体中文 zh-Hans 为固定源语言；34 种目标语言可选</p><label class="language-search" for="language-search">${icon('search')}<input id="language-search" type="search" placeholder="搜索语言、原名或代码" value="${esc(languageSearch)}" autocomplete="off"></label><p class="caption" id="language-search-count">${filteredLanguages().length} / ${LANGS.length} 种可选目标语言</p><div class="language-grid" id="language-options">${languageOptions()}</div></div></section><aside class="panel selected-summary"><div><h3>这次的翻译计划</h3><div class="selected-languages">${locales.length ? locales.map(l => `<span class="selected-chip">${lang(l).name}<button data-action="remove-locale" data-locale="${l}" aria-label="移除${lang(l).name}">×</button></span>`).join('') : '<span class="small muted">至少选择一种目标语言</span>'}</div></div><div class="divider"></div><div><div class="summary-row"><span>中文文案</span><strong>${selectedEntries().length} 条</strong></div><div class="summary-row"><span>目标语言</span><strong>${locales.length} 种</strong></div><div class="summary-row"><span>原文字符</span><strong>${chars}</strong></div><div class="summary-row"><span>复用已有译文</span><strong>${plan.reused} 条</strong></div><div class="summary-row"><span>保留人工修改 / 确认</span><strong>${plan.protected} 条</strong></div><div class="summary-row"><span>合并重复原文</span><strong>${plan.duplicatePending} 条</strong></div><div class="summary-row summary-total"><span>本次增量待译</span><strong>${plan.uniquePending}<span style="font-size:11px;letter-spacing:0;margin-left:5px">条译文</span></strong></div></div><div class="service-box"><div class="flex"><span class="flex">${icon('sparkles')}按你的平台顺序翻译</span><span class="badge ok">真实 API</span></div><p>当前首选 ${state.settings.providerOrder[0]}。${state.settings.providerFallback && state.settings.providerOrder.length > 1 ? `已启用顺序：${state.settings.providerOrder.join(' → ')}。` : '本次仅使用首选平台。'}可在设置中调整平台与自备凭据。仅额度耗尽或不支持目标语言时切换；凭据错误会停止。</p></div><div class="notice" style="margin-top:16px">${icon('shield')}<span>仅新增、原文变更或缺失目标语言的内容会发送给翻译服务；同项目中可复用的译文与人工修改会保留。重复原文按目标语言合并处理。各平台语言支持和免费额度不同，请先在设置中配置所需平台。</span></div></aside></div>${flowFooter('start-translation', plan.uniquePending ? '开始增量翻译' : '复用译文并校对', '', true, !locales.length).replace('class="workflow-footer"', 'class="workflow-footer language-flow-footer"')}`;
  }
  function progressData() {
    const job = sessionJob();
    if (isRealJob(job)) return J.summary(job);
    const total = selectedEntries().length * state.session.locales.length;
    return { total, processed: 0, success: 0, failed: 0, pending: total, skipped: 0, ratio: 0 };
  }
  function renderTranslate() {
    const s = state.session, job = sessionJob();
    const progress = progressData();
    const real = isRealJob(job);
    const finished = ['completed', 'partial'].includes(s.status);
    const running = s.status === 'running';
    const quota = s.status === 'quota';
    const blocked = s.status === 'blocked';
    const activeProvider = job?.activeItem?.provider || state.settings.providerOrder[0];
    const failed = (job?.items || []).filter(item => item.status === 'failed');
    const reused = (job?.items || []).filter(item => item.reused).length;
    const active = job?.activeItem;
    const heading = !real ? '历史演示任务' : quota ? `${job?.error?.provider || '翻译平台'} 额度暂不可用` : blocked ? '翻译平台配置需要处理' : finished ? progress.failed ? '部分译文需要重试' : '翻译已完成' : running ? `正在通过 ${activeProvider} 翻译` : '任务已暂停';
    const subtitle = !real ? '旧译文已保留，可以重新提交未确认文案进行真实翻译。' : quota ? '已完成的译文会保留，剩余内容不会继续发送。' : finished ? `成功 ${progress.success}（复用 ${reused}）· 失败 ${progress.failed} · 保留人工 ${progress.skipped}` : running ? `${selectedEntries().length} 条文案 · ${s.locales.length} 种目标语言 · 当前服务 ${activeProvider}` : '继续任务会处理剩余内容，已成功的译文无需重复请求。';
    return workflowHeader(2, '正在连接更多语言', '真实翻译，逐条保存；长段落仍对应同一个 key。') + `<section class="panel translation-center"><div class="translation-emblem ${running ? 'running' : ''}">${icon(finished && !progress.failed ? 'circlecheck' : quota ? 'alert' : 'globe')}</div><h2>${heading}</h2><p>${subtitle}</p><div class="translation-progress" role="progressbar" aria-label="翻译进度" aria-valuenow="${progress.ratio}" aria-valuemin="0" aria-valuemax="100"><div style="width:${progress.ratio}%"></div></div><div class="progress-meta"><span>${progress.processed} / ${progress.total} 已处理</span><span>${progress.ratio}%</span></div><div class="locale-progress">${s.locales.map(l => {
      const items = (job?.items || []).filter(item => item.locale === l);
      const count = items.filter(item => ['success', 'failed', 'skipped'].includes(item.status)).length;
      const errors = items.filter(item => item.status === 'failed').length;
      return `<div class="locale-progress-row"><span class="language-code ${l}">${lang(l).label}</span><span>${lang(l).name}</span><div class="mini-progress"><i style="width:${items.length ? count / items.length * 100 : 0}%"></i></div><span>${count} / ${items.length || selectedEntries().length}${errors ? ` · ${errors} 失败` : ''}</span></div>`;
    }).join('')}</div>${active && running ? `<div class="active-translation" aria-live="polite"><span class="spinner"></span><span>${active.provider || activeProvider} · ${lang(active.locale).name} · ${esc(active.key || '')}${active.total ? ` · 分段 ${active.completed || 0} / ${active.total}` : ''}${active.retry ? ` · 第 ${active.retry.attempt} 次重试` : ''}</span></div>` : ''}${failed.length ? `<div class="translation-errors">${failed.slice(0, 8).map(item => `<div class="translation-error"><div class="grow"><strong>${esc(sessionEntries().find(e => e.id === item.entryId)?.key || item.entryId)} · ${lang(item.locale).name}</strong><p>${esc(item.error?.message || '翻译失败，请稍后重试。')}</p></div><button class="text-button" data-action="inspect-failed" data-entry-id="${esc(item.entryId)}" data-locale="${item.locale}">校对</button></div>`).join('')}${failed.length > 8 ? `<p class="caption">还有 ${failed.length - 8} 项，可在校对页查看。</p>` : ''}</div>` : ''}<div class="notice ${quota || blocked ? 'warning' : ''}">${icon('shield')}<span>${quota || blocked ? (job?.error?.message || '当前翻译服务不可用，请稍后重试；已完成结果会保留。') : '仅使用你启用的平台与自备凭据；开启自动备用时，仅额度或语言不支持才按顺序切换。成功结果逐条保留，可暂停后继续。'}</span></div><div class="translation-buttons">${running ? '<button class="btn ghost" data-action="pause-translation">暂停任务</button>' : real ? `${progress.failed || quota || blocked ? `<button class="btn primary" data-action="retry-failed">${icon('refresh')}重试失败与未完成项</button>` : ''}${progress.pending && !quota && !blocked ? `<button class="btn primary" data-action="resume-translation">${icon('refresh')}继续翻译</button>` : ''}<button class="btn ${finished && !progress.failed ? 'primary' : ''}" data-action="to-review">${finished ? '开始校对译文' : '校对已保存结果'}${icon('right')}</button>` : `<button class="btn primary" data-action="start-translation">增量翻译未完成项${icon('right')}</button>`}</div></section>`;
  }
  function commitSession(s = state.session) {
    if (!s) return;
    const p = state.projects.find(p => p.id === s.projectId);
    if (!p) return;
    (s.entries || []).filter(e => e.selected !== false).forEach(entry => { const index = p.entries.findIndex(e => e.id === entry.id); if (index >= 0) p.entries[index] = entry; else p.entries.push(entry); });
    p.locales = [...new Set([...p.locales, ...s.locales])];
    p.updatedAt = new Date().toISOString();
    s.committed = true;
  }
  function pauseTranslation(announce = true) {
    const s = state.session, job = sessionJob();
    batchGeneration++;
    batchController?.abort(); batchController = null;
    if (isRealJob(job)) { J.normalize(job); job.status = 'paused'; job.activeItem = null; }
    if (s) s.status = 'paused';
    commitSession(s); persist(); render();
    if (announce) toast('任务已暂停，已保存结果不会丢失。');
  }
  async function startTranslation(resume = false, retry = false) {
    const s = state.session;
    if (!s || s.status === 'running' || batchController) return;
    if (!s.locales.length || !selectedEntries().length) return toast('请先添加文案并选择目标语言。');
    cancelSingle();
    let job = sessionJob();
    if (!resume || !isRealJob(job)) {
      const locales = normalizeLocales(s.locales);
      if (!locales.length) return toast('请选择有效的目标语言。');
      const issues = E.validate(selectedEntries(), []).filter(issue => ['key', 'duplicate', 'source', 'empty'].includes(issue.type));
      if (issues.length || selectedEntries().length > 1000) return toast(issues[0]?.message || '单次最多翻译 1000 条文案，请分批处理。');
      s.locales = locales;
      s.entries = selectedEntries();
      job = J.createJob({ id: uid(), projectId: s.projectId, projectName: sessionProject().name, entries: s.entries, locales: [...s.locales], memoryEntries: sessionProject().entries });
      commitSession(s);
      state.settings.recentLocales = [...s.locales];
      s.jobId = job.id;
      state.jobs.unshift(job);
    } else if (retry) J.retryFailed(job);
    const generation = ++batchGeneration;
    const controller = new AbortController();
    batchController = controller;
    s.status = 'running'; job.status = 'running';
    nav('translate');
    const current = () => generation === batchGeneration && state.session?.id === s.id && !controller.signal.aborted;
    try {
      await J.run(job, { entries: s.entries, memoryEntries: sessionProject().entries, client: translationClient(), signal: controller.signal, onChange() {
        if (!current()) return;
        s.status = job.status;
        s.processed = J.summary(job).processed;
        commitSession(s); persist();
        if (['translate', 'tasks'].includes(state.view)) render();
      } });
      if (!current()) return;
      s.status = job.status; s.processed = J.summary(job).processed;
      commitSession(s); persist();
      if (['translate', 'tasks'].includes(state.view)) render();
      else toast(job.status === 'quota' ? '翻译额度或预算已用完，任务已暂停。' : '翻译任务已更新，可进入任务页查看。');
    } catch (error) {
      if (!current()) return;
      J.normalize(job); job.status = 'paused'; s.status = 'paused';
      persist(); render(); toast(error.message || '任务已暂停，请稍后重试。');
    } finally { if (generation === batchGeneration) batchController = null; }
  }
  function currentReviewEntry() { const entries = selectedEntries(); state.reviewIndex = Math.max(0, Math.min(state.reviewIndex, entries.length - 1)); return entries[state.reviewIndex]; }
  function reviewIssues() { return E.validate(selectedEntries(), state.session.locales); }
  function renderReview() {
    const s = state.session;
    if (!s.locales.includes(state.reviewLocale)) state.reviewLocale = s.locales[0];
    const l = state.reviewLocale;
    const entries = selectedEntries();
    const entry = currentReviewEntry();
    if (!entry) return workflowHeader(3, '翻译校对', '还没有需要校对的内容。') + emptyState('没有文案', '返回项目添加中文文案。');
    const issues = reviewIssues();
    const completed = entries.filter(e => textOf(e.translations[l]).trim()).length;
    const value = textOf(entry.translations[l]);
    const entryIssues = issues.filter(i => i.entryId === entry.id && (!i.locale || i.locale === l));
    return workflowHeader(3, '让每一句，都恰如其分', '逐条检查与调整，译文和 key 都由你掌控。') + `<div class="review-toolbar"><div class="review-tabs">${s.locales.map(code => `<button class="review-tab ${code === l ? 'active' : ''}" data-action="review-locale" data-locale="${code}">${lang(code).name}<span class="mono" style="font-size:9px;opacity:.6">${lang(code).label}</span></button>`).join('')}</div><span class="badge ${completed === entries.length ? 'ok' : 'warn'}">${completed} / ${entries.length} 已有译文</span></div><div class="review-layout"><aside class="panel entry-list">${entries.map((e, i) => `<button class="entry-button ${i === state.reviewIndex ? 'active' : ''}" data-action="review-entry" data-index="${i}" aria-label="校对 ${esc(e.source)}"><span class="status-circle ${!textOf(e.translations[l]).trim() ? 'missing' : e.reviewed[l] ? 'complete' : ''}">${!textOf(e.translations[l]).trim() ? '!' : e.reviewed[l] ? '✓' : ''}</span><span class="grow"><span class="source-text">${esc(e.source)}</span><span class="mono">${esc(e.key)}</span></span></button>`).join('')}</aside><section class="panel review-card"><div class="panel-head"><h3>文案 ${String(state.reviewIndex + 1).padStart(2, '0')}</h3><span class="badge ${entry.reviewed[l] ? 'ok' : !value ? 'warn' : 'neutral'}">${translationLabel(entry, l)}</span></div><div class="panel-body"><div class="review-source-label"><span>ZH</span>简体中文 · 原文</div><div class="review-source">${esc(entry.source)}</div><div class="review-key"><label for="review-key">语义 key</label><input class="field" id="review-key" value="${esc(entry.key)}" spellcheck="false">${icon('key')}</div><div class="between"><label class="field-label" for="review-text" style="margin:0">${lang(l).name}译文 <span class="muted">${lang(l).native}</span></label><button class="text-button" data-action="retranslate" ${singleRequest?.entryId === entry.id && singleRequest?.locale === l ? 'disabled' : ''}>${icon('refresh')}${singleRequest?.entryId === entry.id && singleRequest?.locale === l ? '翻译中…' : '重译'}</button></div><textarea id="review-text" class="field review-field" dir="auto" placeholder="${value ? '' : '译文尚未生成，可在这里手动补充，或点击重译' }" spellcheck="false">${esc(value)}</textarea><div id="entry-errors" class="error-text" role="alert">${entryIssues.map(i => esc(i.message)).join('<br>')}</div><div class="review-actions"><label><input type="checkbox" id="review-confirm" ${entry.reviewed[l] ? 'checked' : ''} ${!value.trim() ? 'disabled' : ''}>我已检查并确认这条译文</label><button class="btn small-btn soft" data-action="save-review">${icon('check')}保存译文</button></div><div class="review-pagination"><button class="btn" data-action="review-prev" ${!state.reviewIndex ? 'disabled' : ''}>${icon('left')}上一条</button><span>${state.reviewIndex + 1} / ${entries.length}</span><button class="btn" data-action="review-next" ${state.reviewIndex >= entries.length - 1 ? 'disabled' : ''}>下一条${icon('right')}</button></div></div></section></div><div class="quality-bar ${issues.length ? 'warning' : ''}" id="quality-bar">${icon(issues.length ? 'alert' : 'shield')}<span>${issues.length ? `发现 ${issues.length} 项待处理问题，导出前需要检查。` : '完整性检查通过：key 唯一、译文齐全、占位符保持一致。'}</span><button class="text-button" data-action="show-issues">查看检查${icon('right')}</button></div>${flowFooter('to-export', '下一步：导出 JSON', '')}`;
  }
  function saveReview(showToast = false) {
    const entry = currentReviewEntry();
    if (!entry || !$('#review-text')) return true;
    const key = $('#review-key').value.trim();
    const value = $('#review-text').value;
    const project = sessionProject();
    if (!/^[a-z][a-z0-9_]{0,79}$/.test(key)) { $('#entry-errors').textContent = 'key 请使用小写英文、数字和下划线，以字母开头。'; return false; }
    if (sessionEntries().some(e => e.id !== entry.id && e.key === key) || project.entries.some(e => e.id !== entry.id && e.key === key)) { $('#entry-errors').textContent = '项目中已存在这个 key，请使用不同名称。'; return false; }
    const changed = textOf(entry.translations[state.reviewLocale]) !== value;
    entry.key = key;
    entry.translations[state.reviewLocale] = value;
    entry.reviewed[state.reviewLocale] = !!$('#review-confirm').checked && !!value.trim();
    if (changed) markManual(entry, state.reviewLocale);
    commitSession(); persist();
    if (showToast) { render(); toast('译文已保存，语言包预览会同步更新。'); }
    return true;
  }
  function exportEntries() { return selectedEntries(); }
  function selectedExportLocales() { const s = state.session; return s.exportLocales?.length ? s.exportLocales.filter(l => s.locales.includes(l)) : []; }
  function exportIssues() { return E.validate(exportEntries(), selectedExportLocales()).filter(i => i.type !== 'language' || !state.session.includeSource); }
  function packageFiles() {
    const s = state.session;
    const files = E.makePackages(exportEntries(), selectedExportLocales(), s.includeSource);
    if (!s.pretty) Object.keys(files).forEach(name => files[name] = JSON.stringify(JSON.parse(files[name])));
    return files;
  }
  function highlightedJSON(text) { return esc(text).replace(/(&quot;(?:[^&]|&(?!quot;))*?&quot;)(\s*:)?/g, (match, value, colon) => `<span class="${colon ? 'code-key' : 'code-string'}">${value}</span>${colon || ''}`); }
  function renderExport() {
    const s = state.session;
    const issues = exportIssues();
    const locales = selectedExportLocales();
    let files = {}, error = '';
    try { files = packageFiles(); } catch (e) { error = e.message; }
    const names = Object.keys(files);
    if (!names.includes(s.previewFile)) s.previewFile = names.find(n => n === 'en.json') || names[0];
    const preview = files[s.previewFile] || '{}';
    const canDownload = names.length && (locales.length || s.includeSource) && (!issues.length || s.draftExport) && !error;
    return workflowHeader(4, '准备好，交付全世界', '独立语言包，直接进入你的产品。') + (s.lastDownload ? `<div class="success-banner">${icon('circlecheck')}<div class="grow"><h3>语言包已生成</h3><p>${esc(s.lastDownload)} · 下载已发起，也可在导出记录中再次获取</p></div></div>` : '') + `<div class="export-layout"><section class="panel"><div class="panel-head"><h2>导出设置</h2><span class="badge ok">${exportEntries().length} 个 key</span></div><div class="panel-body"><div class="field-label">导出格式</div><div class="export-format"><span class="mono">{ }</span><div class="grow"><strong>JSON 语言包</strong><p>每种语言一个文件，扁平 key-value 结构</p></div>${icon('circlecheck')}</div><div class="export-settings"><div class="between"><h3 style="font-size:12px">选择导出语言</h3><span class="small muted">${locales.length + (s.includeSource ? 1 : 0)} 个文件</span></div><label class="export-choice"><input type="checkbox" id="include-source" ${s.includeSource ? 'checked' : ''}><span>简体中文 <span class="badge neutral" style="font-size:9px">源语言</span></span><span class="file-info">zh-Hans.json</span></label>${s.locales.map(l => `<label class="export-choice"><input type="checkbox" data-export-locale="${l}" ${locales.includes(l) ? 'checked' : ''}><span>${lang(l).name}</span><span class="file-info">${l}.json</span></label>`).join('')}</div><div class="divider"></div><label class="export-option"><input type="checkbox" id="pretty-json" ${s.pretty ? 'checked' : ''}>格式化 JSON · 2 空格缩进</label><label class="export-option"><input type="checkbox" id="draft-export" ${s.draftExport ? 'checked' : ''}>草稿导出 · 缺失译文保留空字符串</label>${issues.length || error ? `<div class="notice warning">${icon('alert')}<span>${error ? esc(error) : `有 ${issues.length} 项待处理问题。正式导出需修复；草稿导出会附带问题清单。`}</span></div>${issues.length ? `<div class="issue-list">${issues.slice(0, 12).map(i => `<div class="issue-item"><code>${esc(i.key)}</code> · ${esc(i.locale ? lang(i.locale).name : '')}<br>${esc(i.message)}</div>`).join('')}${issues.length > 12 ? `<p class="caption">还有 ${issues.length - 12} 项问题</p>` : ''}</div><button class="text-button" data-action="back-to-review">${icon('left')}返回校对并修复</button>` : ''}` : `<div class="notice">${icon('shield')}<span>已通过完整性校验。各语言 key 一致，特殊字符和占位符已检查。</span></div>`}</div></section><div><section class="panel code-preview"><div class="code-head"><span class="flex">${icon('code')}文件预览</span><select id="preview-file" aria-label="预览语言包">${names.map(n => `<option value="${n}" ${n === s.previewFile ? 'selected' : ''}>${n}</option>`).join('')}</select></div><pre id="json-preview">${highlightedJSON(preview)}</pre><div class="code-foot"><span>UTF-8 · ${exportEntries().length} 个 key · ${new TextEncoder().encode(preview).length} 字节</span><button class="text-button" data-action="copy-json">${icon('copy')}复制 JSON</button></div></section><div class="download-box"><h3>你的语言包，已井然有序</h3><p>按 key 排序，保留 Unicode；${s.draftExport ? '草稿 ZIP 会附带校验报告。' : '每种语言都使用相同的 key。'}</p><button class="btn primary" data-action="download-zip" ${canDownload ? '' : 'disabled'}>${icon('download')}下载全部语言包 .zip</button><button class="btn ghost" data-action="download-json" ${canDownload && s.previewFile ? '' : 'disabled'} style="width:100%;margin-top:7px">下载当前 ${esc(s.previewFile || 'JSON')}</button></div></div></div><div class="workflow-footer"><button class="btn ghost" data-action="back-to-review">${icon('left')}返回校对</button><button class="btn" data-action="project" data-id="${esc(s.projectId)}">返回项目 ${icon('right')}</button></div>`;
  }
  function renderProject() {
    const p = currentProject();
    if (!p) return renderHome();
    const st = stats(p);
    return pageHead(esc(p.name), esc(p.description || '你的多语言文案，都在这里。'), `<div class="flex"><button class="btn" data-action="review-project" ${p.entries.length ? '' : 'disabled'}>${icon('edit')}校对</button><button class="btn primary" data-action="add-content">${icon('plus')}新增文案</button></div>`, 'PROJECT / LOCALIZATION') + `<div class="panel project-summary"><div><p>中文文案</p><strong>${p.entries.length}<span style="font-size:10px;margin-left:5px">条</span></strong></div><div><p>目标语言</p><strong>${p.locales.length}<span style="font-size:10px;margin-left:5px">种</span></strong></div><div><p>译文齐全度</p><strong>${st.ratio}%</strong></div><div><p>命名风格</p><strong style="font-size:13px;padding-top:9px;display:block">snake_case</strong></div></div><div class="project-translation-cta"><div><strong>按变化增量翻译</strong><p>复用同项目中的有效译文，只补充新增、原文变更或缺失的目标语言。</p></div><button class="btn primary" data-action="translate-project" ${p.entries.length ? '' : 'disabled'}>${icon('globe')}翻译未完成项</button></div><div class="section-title"><h2>项目文案 <span class="small muted" style="font-weight:400;margin-left:8px">${p.entries.length} 条</span></h2><div class="flex"><button class="text-button" data-action="add-document">${icon('upload')}导入文档</button><button class="text-button" data-action="export-project" ${p.entries.length ? '' : 'disabled'}>${icon('download')}导出语言包</button></div></div><div class="panel table-overflow">${p.entries.length ? `<table class="entries-table"><thead><tr><th>#</th><th>中文原文 / 语义 key</th><th>目标语言</th><th>状态</th><th></th></tr></thead><tbody>${p.entries.map((e, i) => { const completed = p.locales.filter(l => textOf(e.translations[l]).trim()).length; return `<tr><td>${String(i + 1).padStart(2, '0')}</td><td class="source-cell">${esc(e.source)}<br><code>${esc(e.key)}</code></td><td><div class="flex" style="gap:4px">${p.locales.map(l => `<span class="language-mini" style="${!textOf(e.translations[l]).trim() ? 'opacity:.35' : ''}">${lang(l).label}</span>`).join('')}</div></td><td><span class="badge ${completed === p.locales.length ? 'ok' : 'warn'}">${completed === p.locales.length ? '译文齐全' : '待补译'}</span></td><td><button class="btn small-btn" data-action="edit-project-entry" data-index="${i}">校对${icon('chevron')}</button></td></tr>`; }).join('')}</tbody></table>` : emptyState('第一条文案，从这里开始', '输入中文或导入文档，生成你的第一组语言包。', '<button class="btn primary" data-action="add-content">' + icon('plus') + '添加文案</button>')}</div><div class="notice" style="margin-top:20px">${icon('sparkles')}<span>翻译通过你启用的平台真实接口生成；项目保存在当前浏览器。可翻译未完成项，人工修改和已确认译文会受到保护。</span></div>`;
  }
  function emptyState(title, subtitle, action = '') { return `<div class="empty-state"><div class="tag-icon">${icon('layers')}</div><h3>${title}</h3><p>${subtitle}</p>${action}</div>`; }
  function formatTime(value) { return new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Shanghai' }).format(new Date(value)); }
  function renderTasks() {
    return pageHead('翻译任务', '每一种语言的进度、失败原因与重试，都在这里。', '<button class="btn primary" data-action="quick-start">' + icon('plus') + '新建翻译</button>', 'TRANSLATION TASKS') + `<div class="panel">${state.jobs.length ? state.jobs.map(job => {
      const real = isRealJob(job);
      const summary = real ? J.summary(job) : { success: 0, failed: 0, processed: job.processed || 0, total: job.total || 0 };
      const label = !real ? '历史演示任务' : job.status === 'quota' ? '额度或预算已用完' : job.status === 'blocked' ? '备用不可用' : job.status === 'running' ? '翻译中' : job.status === 'paused' ? '已暂停' : summary.failed ? '部分失败' : '已完成';
      return `<div class="activity-row"><div class="tag-icon">${icon(job.status === 'completed' && !summary.failed ? 'circlecheck' : 'tasks')}</div><div class="grow"><h3>${esc(job.projectName)} <span class="badge ${real && job.status === 'completed' && !summary.failed ? 'ok' : 'warn'}" style="margin-left:5px">${label}</span></h3><p>${job.count || job.entries?.length || 0} 条文案 · ${(job.locales || []).map(l => lang(l).name).join(' / ')} · ${real ? `成功 ${summary.success} / 失败 ${summary.failed}` : '旧版记录'} · ${formatTime(job.createdAt)}</p></div><button class="btn small-btn" data-action="open-job" data-id="${job.id}">${real ? '查看任务' : '校对译文'}${icon('chevron')}</button></div>`;
    }).join('') : emptyState('还没有翻译任务', '从一段中文开始，生成第一组多语言译文。', '<button class="btn primary" data-action="quick-start">开始翻译' + icon('right') + '</button>')}</div>`;
  }
  function renderExports() {
    return pageHead('导出记录', '每一次交付，都可以重新获取。', '', 'EXPORT HISTORY') + `<div class="panel">${state.exports.length ? state.exports.map(record => `<div class="activity-row"><div class="tag-icon blue">${icon('code')}</div><div class="grow"><h3>${esc(record.name)}</h3><p>${esc(record.projectName)} · ${record.count} 个 key · ${record.fileCount} 个文件 · ${record.draft ? '草稿' : '正式'} · ${formatTime(record.createdAt)}</p></div><button class="btn small-btn" data-action="redownload" data-id="${record.id}">${icon('download')}下载</button></div>`).join('') : emptyState('语言包准备好时，就来这里', '完成翻译校对并导出后，记录会出现在这里。', '<button class="btn" data-action="nav" data-view="home">返回我的项目' + icon('right') + '</button>')}</div>`;
  }
  function renderSettings() {
    return pageHead(titleFor.settings, '', '', 'WORKSPACE PREFERENCES') + window.LangPackProviderSettings.render({ settings: state.settings, names: P.names, status(provider) {
      return providerPresentation(provider);
    } });
  }
  function providerPresentation(provider) {
    const value = credentialVault.get(provider), feedback = providerValidation.get(provider);
    return { ready: credentialVault.has(provider), remembered: credentialVault.remembered(provider), developer: !!value.developerToken, tenantId: value.tenantId, region: value.region, plan: value.plan, checking: !!feedback?.checking, validationStatus: feedback?.status || 'unverified', method: feedback?.method, billableCharacters: feedback?.billableCharacters, storage: feedback?.storage, checkedAt: feedback?.checkedAt };
  }
  function updateProviderFeedback(provider) {
    if (state.view !== 'settings') return;
    const value = providerPresentation(provider), ui = window.LangPackProviderSettings;
    const area = $(`#provider-${provider}-feedback`), badge = $(`#provider-${provider}-badge`), save = $(`#provider-${provider}-save`), retry = $(`#provider-${provider}-validate`);
    if (area) area.innerHTML = ui.feedback(provider, value);
    if (badge) { badge.textContent = ui.badge(provider, value); badge.className = 'badge ' + (value.validationStatus === 'valid' ? 'ok' : 'neutral'); }
    if (save) { save.disabled = value.checking; save.textContent = value.checking ? '正在验证…' : '保存并校验'; }
    if (retry) retry.disabled = value.checking || !value.ready && provider !== 'MyMemory';
  }
  function invalidateProviderValidation(provider) {
    providerValidation.get(provider)?.controller?.abort();
    providerValidationVersions.set(provider, (providerValidationVersions.get(provider) || 0) + 1);
    providerValidation.delete(provider);
  }
  function validationCredentials(provider, value) {
    return P.cleanCredentials(provider, { ...value, ...(provider === 'MyMemory' && state.settings.translationEmail ? { email: state.settings.translationEmail } : {}) });
  }
  function validationRace(promise, signal) {
    return new Promise((resolve, reject) => {
      const abort = () => { signal.removeEventListener('abort', abort); reject(new Error('Validation aborted')); };
      if (signal.aborted) return abort();
      signal.addEventListener('abort', abort, { once: true });
      Promise.resolve(promise).then(value => { signal.removeEventListener('abort', abort); resolve(value); }, () => { signal.removeEventListener('abort', abort); reject(new Error('Validation unavailable')); });
    });
  }
  async function validateProviderSnapshot(provider, credentials) {
    const existing = providerValidation.get(provider);
    if (existing?.checking) return;
    const controller = new AbortController(), version = providerValidationVersions.get(provider) || 0;
    const record = { storage: existing?.storage, status: 'unverified', checking: true, controller, version };
    providerValidation.set(provider, record); updateProviderFeedback(provider);
    const current = () => providerValidation.get(provider) === record && (providerValidationVersions.get(provider) || 0) === version;
    const timer = setTimeout(() => controller.abort(), 30000);
    try {
      const response = await validationRace(fetch('/api/translation/validate', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, credentials: 'same-origin', cache: 'no-store', referrerPolicy: 'no-referrer', body: JSON.stringify({ provider, credentials }), signal: controller.signal }), controller.signal);
      if (!current()) return;
      if (!response.ok || response.status !== 200) {
        record.status = [400, 401, 403, 422].includes(response.status) ? 'invalid' : [402, 429].includes(response.status) ? 'limited' : 'unavailable';
        return;
      }
      const body = await validationRace(response.json(), controller.signal);
      if (!current()) return;
      const expectedMethod = provider === 'MyMemory' && !credentials.apiKey ? 'anonymous' : ['DeepL', 'Google'].includes(provider) ? 'metadata' : 'translation';
      const validShape = body?.provider === provider && ['valid', 'invalid', 'limited', 'unavailable'].includes(body.status) && body.method === expectedMethod && body.billableCharacters === (expectedMethod === 'translation' ? 1 : 0);
      if (!validShape) { record.status = 'unavailable'; }
      else { record.status = body.status; record.method = body.method; record.billableCharacters = body.billableCharacters; }
    } catch (_) { if (current()) record.status = 'unavailable'; }
    finally {
      clearTimeout(timer);
      if (current()) { record.checking = false; record.checkedAt = new Date().toISOString(); delete record.controller; updateProviderFeedback(provider); }
    }
  }
  function refreshProviderConfiguration(provider) {
    if (state.session?.status === 'running') pauseTranslation(false);
    providerRevision++; translationClients.clear();
    if (provider) { providerCircuits[provider] = { until: 0 }; if (provider === 'MyMemory') state.settings.primaryCircuit = providerCircuits.MyMemory; }
    persist(); render();
  }
  function render() {
    const views = { home: renderHome, project: renderProject, input: renderInput, import: renderImport, languages: renderLanguages, translate: renderTranslate, review: renderReview, export: renderExport, tasks: renderTasks, exports: renderExports, settings: renderSettings };
    try { $('#app').innerHTML = shell((views[state.view] || renderHome)()); }
    catch (error) { console.error(error); $('#app').innerHTML = shell(emptyState('暂时无法打开这个页面', '已保存的数据仍会保留，请返回项目重试。', '<button class="btn" data-action="nav" data-view="home">返回项目</button>')); }
    bindDropZone();
  }
  function modal(title, body, footer = '') {
    const dialog = $('#modal');
    dialog.innerHTML = `<div class="modal-head"><h2>${title}</h2><button class="icon-button" data-action="close-modal" aria-label="关闭弹窗">${icon('close')}</button></div><div class="modal-body">${body}</div>${footer ? `<div class="modal-footer">${footer}</div>` : ''}`;
    if (!dialog.open) dialog.showModal();
  }
  function newProjectModal() {
    modal('给新的想法，一个名字', '<p>创建独立项目，管理中文文案、目标语言和导出记录。</p><label class="field-label" for="project-name">项目名称</label><input id="project-name" class="field" placeholder="例如：我的多语言 App" maxlength="50"><label class="field-label" for="project-description">项目简介（选填）</label><input id="project-description" class="field" placeholder="简单说说这个项目" maxlength="120"><div id="modal-error" class="error-text" role="alert"></div>', '<button class="btn" data-action="close-modal">取消</button><button class="btn primary" data-action="create-project">创建并添加文案' + icon('right') + '</button>');
    setTimeout(() => $('#project-name').focus(), 30);
  }
  function helpModal() {
    modal('从中文，到你的语言包', '<ol class="help-list"><li>输入中文，或导入 TXT、Markdown、DOCX，先调整原文与 key。</li><li>默认使用 MyMemory。需要其他平台时，在设置中填写自己的凭据，并选择首选与备用顺序。</li><li>只有额度耗尽或不支持语言才会自动换平台；鉴权和配置错误会停止，网络错误只有限重试。</li><li>凭据默认只保留当前标签页会话，可选择记住到本机浏览器；项目与备份不包含凭据。ZTAITrans 需要自备授权或开发者口令。</li><li>有效译文增量复用，长段落按平台限制安全拆分；人工校对后导出 JSON / ZIP。</li></ol><div class="notice warning"><span>各平台的语言支持、免费额度和计费规则不同，请查看设置中的官方说明；免费额度不代表永久免费或不会产生超额费用。</span></div>', '<button class="btn primary" data-action="close-modal">开始使用' + icon('right') + '</button>');
  }
  async function importFile(file) {
    if (!file) return;
    const errorEl = $('#import-error');
    if (file.size > 10 * 1024 * 1024) { if (errorEl) errorEl.textContent = '文档超过 10 MB，请拆分后导入。'; return; }
    const requestId = ++importRequest;
    const sessionId = state.session.id;
    state.session.importing = true;
    if (errorEl) errorEl.innerHTML = '<span class="spinner"></span> 正在解析文档…';
    try {
      const result = await E.parseDocument(file);
      if (state.session?.id !== sessionId || importRequest !== requestId || state.session.mode !== 'document') return;
      state.session.importing = false;
      if (!result.entries.length) throw new Error('没有提取到可翻译文本，请检查文档内容。');
      if (result.entries.length > 1000) throw new Error('文档超过 1000 个内容块，请拆分后导入。');
      state.session.entries = rekeyAgainstProject(result.entries);
      state.session.fileName = result.fileName;
      state.session.mode = 'document';
      persist(); if (state.view === 'import') render(); toast(`已提取 ${result.entries.length} 段内容，可以调整后继续。`);
    } catch (error) { if (state.session?.id !== sessionId || importRequest !== requestId) return; state.session.importing = false; if ($('#import-error')) $('#import-error').textContent = error.message || '文档解析失败，请尝试 TXT 或 Markdown。'; }
  }
  function bindDropZone() {
    const zone = $('#drop-zone');
    if (!zone) return;
    zone.addEventListener('dragover', event => { event.preventDefault(); zone.classList.add('dragging'); });
    zone.addEventListener('dragleave', () => zone.classList.remove('dragging'));
    zone.addEventListener('drop', event => { event.preventDefault(); zone.classList.remove('dragging'); importFile(event.dataTransfer.files[0]); });
  }
  function openProjectReview(index = 0, view = 'review') {
    if (state.session?.status === 'running') { toast('请先完成或暂停当前翻译任务。'); return nav('translate'); }
    cancelSingle();
    const p = currentProject();
    if (!p.entries.length) return newSession('text');
    const locales = view === 'languages' ? defaultLocales(p.locales) : [...p.locales];
    if (view === 'languages') languageSearch = '';
    state.session = { id: uid(), projectId: p.id, mode: 'project', entries: p.entries, locales, status: 'completed', processed: p.entries.length * p.locales.length, committed: true, includeSource: state.settings.includeSource, pretty: state.settings.pretty, exportLocales: [...locales] };
    state.reviewIndex = index; state.reviewLocale = p.locales[0]; nav(view);
  }
  function triggerDownload(data, name, type) {
    const blob = data instanceof Blob ? data : new Blob([data], { type });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = name; document.body.appendChild(anchor); anchor.click(); anchor.remove(); setTimeout(() => URL.revokeObjectURL(url), 30000);
  }
  function download(kind) {
    const issues = exportIssues();
    const s = state.session;
    if (!selectedExportLocales().length && !s.includeSource) return toast('至少选择一个语言文件。');
    if (issues.length && !s.draftExport) return toast('请先修复校验问题，或启用草稿导出。');
    let files;
    try { files = packageFiles(); } catch (error) { return toast(error.message); }
    const languageFileCount = Object.keys(files).length;
    if (s.draftExport && issues.length) files['_validation-report.json'] = JSON.stringify({ mode: 'draft', missingValue: '', issues }, null, 2);
    const p = sessionProject();
    const name = kind === 'zip' ? `${p.name.replace(/[\\/:*?"<>|]/g, '_')}-locales${s.draftExport ? '-draft' : ''}.zip` : s.previewFile;
    if (!name) return;
    if (kind === 'json') triggerDownload(files[s.previewFile], name, 'application/json;charset=utf-8');
    else triggerDownload(E.makeZip(files), name, 'application/zip');
    state.exports.unshift({ id: uid(), name, projectName: p.name, count: exportEntries().length, fileCount: kind === 'json' ? 1 : languageFileCount, createdAt: new Date().toISOString(), draft: !!s.draftExport, kind, files: kind === 'json' ? { [name]: files[name] } : files });
    state.exports = state.exports.slice(0, 20);
    s.lastDownload = name; persist(); render(); toast('语言包已生成，下载已发起。');
  }
  document.addEventListener('click', async event => {
    const button = event.target.closest('[data-action]');
    if (!button || button.disabled) return;
    const action = button.dataset.action;
    const s = state.session;
    if (state.view === 'review' && !['save-review', 'show-issues', 'close-modal', 'retranslate'].includes(action) && !$('#modal').open && !saveReview()) return;
    switch (action) {
      case 'nav': nav(button.dataset.view); break;
      case 'help': helpModal(); break;
      case 'close-modal': $('#modal').close(); break;
      case 'new-project': newProjectModal(); break;
      case 'create-project': {
        const name = $('#project-name').value.trim();
        if (!name) { $('#modal-error').textContent = '请先输入项目名称。'; $('#project-name').focus(); return; }
        const p = { id: uid(), name, description: $('#project-description').value.trim(), icon: 'layers', color: 'purple', entries: [], locales: [], updatedAt: new Date().toISOString() };
        state.projects.push(p); state.currentProjectId = p.id; $('#modal').close(); newSession('text'); break;
      }
      case 'project': state.currentProjectId = button.dataset.id; nav('project'); break;
      case 'quick-start': if (!currentProject()) return newProjectModal(); newSession('text'); break;
      case 'quick-import': if (!currentProject()) return newProjectModal(); newSession('document'); break;
      case 'add-content': newSession('text'); break;
      case 'add-document': newSession('document'); break;
      case 'filter-projects': state.homeFilter = button.dataset.filter; persist(); render(); break;
      case 'fill-example': s.text = SAMPLE; s.split = 'line'; updateInputEntries(); persist(); render(); toast('已填入示例文案，可直接进入下一步。'); break;
      case 'switch-mode': {
        const mode = button.dataset.mode;
        if (mode === s.mode || mode === 'text' && s.mode === 'text') break;
        importRequest++; s.importing = false; s.mode = mode; s.entries = mode === 'text' ? rekeyAgainstProject(E.splitText(s.text || '', s.split || 'line')) : []; s.fileName = ''; nav(mode === 'text' ? 'input' : 'import'); break;
      }
      case 'load-doc-example': s.entries = rekeyAgainstProject(E.splitText(DOC_SAMPLE, 'paragraph')); s.fileName = '产品介绍.md'; persist(); render(); toast('已载入示例文档，提取 4 个段落。'); break;
      case 'pick-file': $('#file-input').click(); break;
      case 'select-paragraphs': { const all = s.entries.every(e => e.selected); s.entries.forEach(e => e.selected = !all); persist(); render(); break; }
      case 'merge-paragraph': {
        const i = +button.dataset.index, entry = s.entries[i], next = s.entries[i + 1];
        if (!next) break;
        entry.source += '\n' + next.source; entry.sourceVersion = (entry.sourceVersion || 1) + 1; entry.translations = {}; entry.reviewed = {}; entry.edited = {}; entry.translationMeta = {}; s.entries.splice(i + 1, 1); persist(); render(); break;
      }
      case 'split-paragraph': {
        const i = +button.dataset.index, entry = s.entries[i];
        const pieces = entry.source.match(/[^。！？.!?\n]+[。！？.!?]?/gu)?.map(t => t.trim()).filter(Boolean) || [];
        if (pieces.length < 2) { toast('这段只有一句，可在原文中添加换行后再拆分。'); break; }
        const used = new Set([...currentProject().entries, ...s.entries].map(e => e.key));
        const newEntries = pieces.map((source, n) => { const e = E.splitText(source, 'line')[0]; e.key = n === 0 ? entry.key : E.uniqueKey(source, used); used.add(e.key); return e; });
        s.entries.splice(i, 1, ...newEntries); persist(); render(); break;
      }
      case 'to-languages': {
        if (s.importing) return toast('文档正在解析，请稍候再继续。');
        if (!selectedEntries().length) return toast('请先输入文案或选择需要翻译的段落。');
        if (selectedEntries().length > 1000) return toast('单次最多翻译 1000 条文案，请分批处理。');
        if (selectedEntries().some(e => !e.source.trim())) return toast('请移除空白段落，或先补充原文。');
        const keyIssues = E.validate(selectedEntries(), []).filter(i => ['key', 'duplicate', 'source', 'empty'].includes(i.type));
        if (keyIssues.length) return toast(keyIssues[0].message);
        const used = new Set(sessionProject().entries.map(e => e.key));
        if (selectedEntries().some(e => used.has(e.key) && !currentProject().entries.some(p => p.id === e.id))) return toast('项目中已有同名 key，请先修改冲突名称。');
        nav('languages'); break;
      }
      case 'toggle-all-languages': s.locales = normalizeLocales(s.locales).length === LANGS.length ? [] : LANGS.map(l => l.code); persist(); render(); break;
      case 'remove-locale': s.locales = normalizeLocales(s.locales).filter(l => l !== button.dataset.locale); persist(); render(); break;
      case 'start-translation': startTranslation(); break;
      case 'resume-translation': startTranslation(true); break;
      case 'pause-translation': pauseTranslation(); break;
      case 'retry-failed': startTranslation(true, true); break;
      case 'inspect-failed': state.reviewIndex = selectedEntries().findIndex(entry => entry.id === button.dataset.entryId); state.reviewLocale = button.dataset.locale; nav('review'); break;
      case 'to-review': state.reviewIndex = 0; state.reviewLocale = s.locales[0]; nav('review'); break;
      case 'review-locale': state.reviewLocale = button.dataset.locale; persist(); render(); break;
      case 'review-entry': state.reviewIndex = +button.dataset.index; persist(); render(); break;
      case 'review-prev': state.reviewIndex--; persist(); render(); break;
      case 'review-next': state.reviewIndex++; persist(); render(); break;
      case 'save-review': saveReview(true); break;
      case 'retranslate': {
        if (!saveReview()) break;
        const entry = currentReviewEntry();
        if (entry.edited?.[state.reviewLocale]) { modal('替换你编辑过的译文？', '<p>将把这条原文重新发送给翻译服务。成功后替换当前译文，失败时保留现有内容。</p>', '<button class="btn" data-action="close-modal">取消</button><button class="btn primary" data-action="confirm-retranslate">替换译文</button>'); }
        else retranslateEntry(); break;
      }
      case 'confirm-retranslate': $('#modal').close(); retranslateEntry(); break;
      case 'show-issues': {
        const issues = reviewIssues();
        modal('语言包完整性检查', issues.length ? `<p>共发现 ${issues.length} 项待处理问题。</p><div class="issue-list">${issues.map(i => `<div class="issue-item"><code>${esc(i.key)}</code> · ${i.locale ? lang(i.locale).name : 'key'}<br>${esc(i.message)}</div>`).join('')}</div>` : '<div class="notice">' + icon('shield') + '<span>key 唯一、译文齐全、占位符一致。语义准确性仍需人工校对。</span></div>', '<button class="btn primary" data-action="close-modal">知道了</button>'); break;
      }
      case 'to-export': s.exportLocales = [...s.locales]; nav('export'); break;
      case 'back-to-review': nav('review'); break;
      case 'copy-json': {
        const text = packageFiles()[s.previewFile] || '{}';
        try { await navigator.clipboard.writeText(text); toast('JSON 已复制。'); } catch { modal('复制 JSON', `<p>选中下方内容后复制。</p><textarea class="field" id="copy-fallback" rows="10">${esc(text)}</textarea>`, '<button class="btn primary" data-action="close-modal">完成</button>'); $('#copy-fallback').select(); } break;
      }
      case 'download-zip': download('zip'); break;
      case 'download-json': download('json'); break;
      case 'review-project': openProjectReview(); break;
      case 'translate-project': openProjectReview(0, 'languages'); break;
      case 'edit-project-entry': openProjectReview(+button.dataset.index); break;
      case 'export-project': openProjectReview(0, 'export'); break;
      case 'open-job': {
        const job = state.jobs.find(j => j.id === button.dataset.id);
        if (!job) break;
        cancelSingle();
        if (job.id === s?.jobId) { state.currentProjectId = job.projectId; nav(isRealJob(job) ? 'translate' : 'review'); break; }
        if (s?.status === 'running') { toast('请先完成或暂停当前任务。'); return nav('translate'); }
        state.currentProjectId = job.projectId;
        const p = currentProject();
        const entries = job.entries.map(e => p.entries.find(pe => pe.id === e.id) || e);
        state.session = { id: uid(), projectId: p.id, mode: 'text', entries, locales: [...job.locales], status: job.status, processed: job.processed, jobId: job.id, committed: job.status === 'completed', includeSource: state.settings.includeSource, pretty: state.settings.pretty, exportLocales: [...job.locales] };
        state.reviewIndex = 0; state.reviewLocale = job.locales[0]; nav(isRealJob(job) ? 'translate' : 'review'); break;
      }
      case 'redownload': {
        const record = state.exports.find(r => r.id === button.dataset.id); if (!record) break;
        triggerDownload(record.kind === 'zip' ? E.makeZip(record.files) : Object.values(record.files)[0], record.name, record.kind === 'zip' ? 'application/zip' : 'application/json;charset=utf-8'); toast('已重新发起下载。'); break;
      }
      case 'check-backup': {
        try { const response = await fetch('/api/translation/status', { cache: 'no-store', credentials: 'same-origin' }); const info = await response.json(); backupConfiguration = response.ok && typeof info.backupConfigured === 'boolean' ? info.backupConfigured ? 'configured' : 'missing' : 'unavailable'; } catch { backupConfiguration = 'unavailable'; }
        render(); toast(backupConfiguration === 'configured' ? '备用凭据已配置，密钥不会发送到浏览器。' : '备用配置暂不可用，请检查服务端设置。'); break;
      }
      case 'move-provider': {
        const order = state.settings.providerOrder, index = order.indexOf(button.dataset.provider), target = index + Number(button.dataset.direction);
        if (index >= 0 && target >= 0 && target < order.length) { [order[index], order[target]] = [order[target], order[index]]; refreshProviderConfiguration(); }
        break;
      }
      case 'save-provider-credentials': {
        const provider = button.dataset.provider;
        if (!P.known(provider)) break;
        const old = credentialVault.get(provider);
        const entered = (name, fallback = '') => $(`#provider-${provider}-${name}`)?.value.trim() || fallback;
        const key = entered('key');
        let credentials = { apiKey: key || old.apiKey || '' };
        if (provider === 'ZTAITrans') {
          const mode = $('#provider-ZTAITrans-mode').value || (old.developerToken ? 'developer' : 'apiKey');
          credentials = mode === 'developer' ? { developerToken: $('#provider-ZTAITrans-developer').value.trim() || old.developerToken || '' } : { apiKey: key || old.apiKey || '', tenantId: $('#provider-ZTAITrans-tenant').value.trim() };
        }
        if (provider === 'DeepL') credentials.plan = $('#provider-DeepL-plan').value || old.plan || 'free';
        if (provider === 'Azure') credentials.region = $('#provider-Azure-region').value.trim();
        if (provider === 'Baidu') credentials = { appId: entered('appId', old.appId), secretKey: entered('secretKey', old.secretKey) };
        if (provider === 'Tencent') credentials = { secretId: entered('secretId', old.secretId), secretKey: entered('secretKey', old.secretKey), region: entered('region', old.region || 'ap-guangzhou') };
        if (provider === 'Alibaba') credentials = { accessKeyId: entered('accessKeyId', old.accessKeyId), accessKeySecret: entered('accessKeySecret', old.accessKeySecret) };
        if (!P.configured(provider, credentials)) { toast('请填写所选授权方式的凭据。'); break; }
        const remember = !!$(`#provider-${provider}-remember`).checked;
        const snapshot = validationCredentials(provider, credentials);
        const sameCredentials = JSON.stringify(snapshot) === JSON.stringify(validationCredentials(provider, old));
        const previous = providerValidation.get(provider);
        if (sameCredentials && previous?.checking && remember === credentialVault.remembered(provider)) break;
        if (!sameCredentials) invalidateProviderValidation(provider);
        const saved = credentialVault.set(provider, credentials, remember);
        const record = sameCredentials && previous ? previous : { status: 'unverified', checking: false };
        record.storage = saved ? remember ? 'local' : 'session' : 'partial';
        providerValidation.set(provider, record);
        refreshProviderConfiguration(provider);
        if (sameCredentials && previous && (previous.checking || previous.status !== 'unverified')) { updateProviderFeedback(provider); toast(previous.checking ? '保存方式已更新，正在继续本次校验。' : '保存方式已更新，沿用当前会话上次校验的记录。'); break; }
        toast(saved ? '凭据已保存，正在校验；校验结果会单独显示。' : '当前页已保留凭据，但浏览器保存或旧副本清除未完成；校验结果会单独显示。');
        await validateProviderSnapshot(provider, snapshot); break;
      }
      case 'validate-provider': {
        const provider = button.dataset.provider;
        if (!P.known(provider) || providerValidation.get(provider)?.checking) break;
        const snapshot = validationCredentials(provider, credentialVault.get(provider));
        if (provider !== 'MyMemory' && !credentialVault.has(provider)) { toast('请先保存这个平台的凭据。'); break; }
        await validateProviderSnapshot(provider, snapshot); break;
      }
      case 'delete-provider-credentials': {
        const provider = button.dataset.provider;
        if (!P.known(provider)) break;
        invalidateProviderValidation(provider);
        const removed = credentialVault.remove(provider);
        providerValidation.set(provider, { status: 'unverified', checking: false, storage: removed ? 'deleted' : 'delete-partial' });
        refreshProviderConfiguration(provider); toast(removed ? '这个平台的本机凭据已删除，校验结果已清除。' : '当前页凭据已删除，但浏览器阻止了旧副本清除；请清理站点数据。'); break;
      }
      case 'verify-developer': {
        const token = $('#provider-ZTAITrans-developer').value.trim() || credentialVault.get('ZTAITrans').developerToken;
        if (!token) { toast('请先填写开发者口令。'); break; }
        const version = providerValidationVersions.get('ZTAITrans') || 0;
        const current = () => (providerValidationVersions.get('ZTAITrans') || 0) === version && state.view === 'settings' && ($('#provider-ZTAITrans-developer')?.value.trim() || credentialVault.get('ZTAITrans').developerToken) === token;
        try { const response = await fetch('/api/translation/status', { headers: { 'X-LangPack-Developer-Token': token }, credentials: 'same-origin', cache: 'no-store', referrerPolicy: 'no-referrer' }); const body = await response.json(); if (current()) toast(response.ok && body.backupConfigured === true ? '开发者身份验证通过；上游翻译凭据仍需保存后校验。' : '开发者口令未通过验证，请检查输入。'); } catch (_) { if (current()) toast('无法验证开发者口令，请检查网络。'); }
        break;
      }
      case 'save-translation-settings': {
        const field = $('#translation-email'), email = field.value.trim();
        if (email && (!field.validity.valid || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) { $('#settings-error').textContent = '请输入可接收联系的有效邮箱，或清空后使用匿名额度。'; break; }
        if (email !== state.settings.translationEmail) { invalidateProviderValidation('MyMemory'); cancelSingle(); if (state.session?.status === 'running') pauseTranslation(false); providerRevision++; providerCircuits.MyMemory = state.settings.primaryCircuit = { until: 0 }; translationClients.clear(); }
        state.settings.translationEmail = email; persist(); render(); toast(email ? '已保存，后续翻译将使用该联系邮箱。' : '已切换为匿名翻译。'); break;
      }
      case 'reset-confirm': modal('恢复初始示例？', '<p>本原型内的自定义项目、译文、任务和导出记录将被清除。建议先导出需要保留的语言包。</p>', '<button class="btn" data-action="close-modal">取消</button><button class="btn primary" data-action="reset">确认重置</button>'); break;
      case 'reset': { P.names.forEach(invalidateProviderValidation); providerValidation.clear(); const cleared = credentialVault.clear(); P.names.forEach(provider => { delete providerCircuits[provider]; }); providerRevision++; batchGeneration++; batchController?.abort(); batchController = null; cancelSingle(); translationClients.clear(); state = initialState(); persist(); $('#modal').close(); render(); toast(cleared ? '已恢复初始示例。' : '项目已重置，但部分浏览器凭据副本未能删除；请清理站点数据。'); break; }
      case 'flow-back': {
        if (state.view === 'input' || state.view === 'import') nav('project');
        else if (state.view === 'languages') nav(s.mode === 'project' ? 'project' : s.mode === 'document' ? 'import' : 'input');
        else if (state.view === 'translate') nav('tasks');
        else if (state.view === 'review') nav('project');
        else if (state.view === 'export') nav('review');
        break;
      }
    }
  });
  async function retranslateEntry() {
    const session = state.session, entry = currentReviewEntry(), locale = state.reviewLocale;
    if (!entry || session.status === 'running') return;
    cancelSingle();
    const controller = new AbortController(); singleController = controller;
    const revision = entry.translationRevision?.[locale] || 0;
    const source = entry.source, sourceVersion = entry.sourceVersion, reviewed = !!entry.reviewed[locale];
    singleRequest = { entryId: entry.id, locale };
    render();
    let notice = '';
    try {
      const result = await translationClient().translate(source, locale, { signal: controller.signal, bypassCache: true });
      if (controller.signal.aborted || state.session?.id !== session.id) return;
      if (entry.source !== source || entry.sourceVersion !== sourceVersion || (entry.translationRevision?.[locale] || 0) !== revision || !!entry.reviewed[locale] !== reviewed) { notice = '译文已被你修改，返回结果未覆盖现有内容。'; return; }
      entry.translations[locale] = result.text;
      entry.reviewed[locale] = false;
      entry.edited ||= {}; entry.edited[locale] = false;
      entry.translationMeta ||= {}; entry.translationMeta[locale] = { provider: result.provider || 'MyMemory', status: 'success', sourceText: source, sourceVersion: sourceVersion || 1, translatedAt: new Date().toISOString() };
      entry.translationRevision ||= {}; entry.translationRevision[locale] = revision + 1;
      commitSession(session); persist(); notice = `${result.provider || 'MyMemory'} 译文已保存，请校对。`;
    } catch (error) {
      if (controller.signal.aborted || state.session?.id !== session.id) return;
      notice = error.message || '翻译失败，原有译文已保留。';
    } finally {
      if (singleController === controller) {
        singleController = null; singleRequest = null;
        if (state.session?.id === session.id && state.view === 'review' && currentReviewEntry()?.id === entry.id && state.reviewLocale === locale) render();
        if (notice) toast(notice);
      }
    }
  }
  document.addEventListener('input', event => {
    const target = event.target, s = state.session;
    if (target.id === 'project-search') { state.search = target.value; $('#project-grid').innerHTML = projectCards(); saveSoon(); }
    if (target.id === 'source-text') {
      s.text = target.value; updateInputEntries(); $('#key-preview').innerHTML = previewRows(); $('#source-count').textContent = `${s.text.length} 字符 · ${s.entries.length} 条文案`; $('#preview-count').textContent = `${s.entries.length} 条`; $('[data-action="to-languages"]').disabled = !s.entries.length;
    }
    if (target.id === 'language-search') { languageSearch = target.value; $('#language-options').innerHTML = languageOptions(); $('#language-search-count').textContent = `${filteredLanguages().length} / ${LANGS.length} 种可选目标语言`; }
    if (target.id === 'context') { s.context = target.value; saveSoon(); }
    if (target.dataset.keyIndex !== undefined) { s.entries[+target.dataset.keyIndex].key = target.value; saveSoon(); }
    if (target.dataset.docSource !== undefined) { const entry = s.entries[+target.dataset.docSource]; if (entry.source !== target.value) { entry.source = target.value; entry.sourceVersion = (entry.sourceVersion || 1) + 1; entry.translations = {}; entry.reviewed = {}; entry.edited = {}; entry.translationMeta = {}; } saveSoon(); }
    if (target.id === 'review-text') {
      const e = currentReviewEntry(); e.translations[state.reviewLocale] = target.value; e.reviewed[state.reviewLocale] = false; markManual(e, state.reviewLocale);
      $('#review-confirm').checked = false; $('#review-confirm').disabled = !target.value.trim();
      const issues = E.validate([e], [state.reviewLocale]); $('#entry-errors').textContent = issues.map(i => i.message).join(' '); commitSession(); saveSoon();
    }
  });
  document.addEventListener('change', event => {
    const target = event.target, s = state.session;
    if (target.id === 'file-input') importFile(target.files[0]);
    if (target.name === 'split') { s.split = target.value; updateInputEntries(); persist(); render(); }
    if (target.dataset.locale) { s.locales = normalizeLocales(target.checked ? [...s.locales, target.dataset.locale] : s.locales.filter(l => l !== target.dataset.locale)); persist(); render(); }
    if (target.dataset.docSelect !== undefined) { s.entries[+target.dataset.docSelect].selected = target.checked; persist(); render(); }
    if (target.dataset.exportLocale) { if (target.checked) s.exportLocales.push(target.dataset.exportLocale); else s.exportLocales = s.exportLocales.filter(l => l !== target.dataset.exportLocale); s.lastDownload = ''; persist(); render(); }
    if (target.id === 'include-source') { s.includeSource = target.checked; s.lastDownload = ''; persist(); render(); }
    if (target.id === 'pretty-json') { s.pretty = target.checked; persist(); render(); }
    if (target.id === 'draft-export') { s.draftExport = target.checked; persist(); render(); }
    if (target.id === 'preview-file') { s.previewFile = target.value; persist(); render(); }
    if (target.id === 'review-confirm') saveReview();
    if (target.id === 'review-key') saveReview(false);
    if (target.id === 'primary-provider' && P.known(target.value)) { state.settings.providerOrder = [target.value, ...state.settings.providerOrder.filter(provider => provider !== target.value)]; refreshProviderConfiguration(); }
    if (target.dataset.providerEnabled && P.known(target.dataset.providerEnabled)) { const provider = target.dataset.providerEnabled; const order = state.settings.providerOrder.filter(value => value !== provider); if (target.checked) order.push(provider); if (!order.length) { toast('请至少保留一个翻译平台。'); render(); } else { state.settings.providerOrder = order; refreshProviderConfiguration(); } }
    if (target.id === 'provider-fallback') { state.settings.providerFallback = !!target.checked; refreshProviderConfiguration(); }
    if (target.id === 'setting-source') { state.settings.includeSource = target.checked; persist(); toast('已更新导出偏好。'); }
    if (target.id === 'setting-pretty') { state.settings.pretty = target.checked; persist(); toast('已更新格式偏好。'); }
  });
  document.addEventListener('keydown', event => {
    if ((event.key === 'Enter' || event.key === ' ') && event.target.matches('.project-card[role="button"]')) { event.preventDefault(); event.target.click(); }
    if (event.key === 'Enter' && event.target.id === 'project-name') $('[data-action="create-project"]').click();
  });
  $('#modal').addEventListener('click', event => { if (event.target === $('#modal')) { const rect = $('#modal').getBoundingClientRect(); if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) $('#modal').close(); } });
  window.addEventListener('beforeunload', persist);
  persist(); render();
})();
