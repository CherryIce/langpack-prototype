(function (root, factory) {
  'use strict';
  const api = factory();
  root.LangPackProviders = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis, function () {
  'use strict';
  const names = Object.freeze(['MyMemory', 'ZTAITrans', 'DeepL', 'Azure', 'Google', 'Baidu', 'Tencent', 'Alibaba']);
  const SESSION_KEY = 'langpack-provider-session-v1';
  const LOCAL_KEY = 'langpack-provider-credentials-v1';
  const known = value => names.includes(value);
  const normalizeOrder = values => [...new Set((Array.isArray(values) ? values : []).filter(known))];
  function supports(provider, locale, sourceLocale = 'zh-Hans') {
    if (!known(provider)) return false;
    if (locale === sourceLocale || !['zh-Hans', 'en'].includes(sourceLocale)) return false;
    if (locale === 'zh-Hans') return sourceLocale === 'en';
    if (provider === 'MyMemory') return !['pt-BR', 'fil', 'nb'].includes(locale);
    if (provider === 'DeepL') return !['fil', 'si'].includes(locale);
    if (provider === 'Google') return locale !== 'nb';
    if (provider === 'Baidu') return !['pt-BR', 'pt-PT'].includes(locale);
    if (provider === 'Tencent') return ['zh-Hant', 'en', 'ms', 'th', 'fr', 'es', 'ar', 'vi', 'ru', 'tr', 'id', 'ja', 'ko', 'de', 'it'].includes(locale);
    if (provider === 'Alibaba') return !['pt-BR', 'pt-PT', 'nb', 'hr', 'uk'].includes(locale);
    return true;
  }
  function cleanCredentials(provider, value = {}) {
    value = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
    const text = name => typeof value[name] === 'string' ? value[name].trim() : '';
    if (provider === 'MyMemory') return { apiKey: text('apiKey'), ...(text('email') ? { email: text('email') } : {}) };
    if (provider === 'ZTAITrans') return text('developerToken') ? { developerToken: text('developerToken') } : { apiKey: text('apiKey'), ...(text('tenantId') ? { tenantId: text('tenantId') } : {}) };
    if (provider === 'DeepL') return { apiKey: text('apiKey'), plan: value.plan === 'pro' ? 'pro' : 'free' };
    if (provider === 'Azure') return { apiKey: text('apiKey'), ...(text('region') ? { region: text('region') } : {}) };
    if (provider === 'Google') return { apiKey: text('apiKey') };
    if (provider === 'Baidu') return { appId: text('appId'), secretKey: text('secretKey') };
    if (provider === 'Tencent') return { secretId: text('secretId'), secretKey: text('secretKey'), region: text('region') || 'ap-guangzhou' };
    if (provider === 'Alibaba') return { accessKeyId: text('accessKeyId'), accessKeySecret: text('accessKeySecret') };
    return {};
  }
  function configured(provider, value) {
    if (provider === 'MyMemory') return true;
    const clean = cleanCredentials(provider, value);
    if (provider === 'Baidu') return !!(clean.appId && clean.secretKey);
    if (provider === 'Tencent') return !!(clean.secretId && clean.secretKey);
    if (provider === 'Alibaba') return !!(clean.accessKeyId && clean.accessKeySecret);
    return !!(clean.apiKey || clean.developerToken);
  }
  function createVault({ sessionStorage, localStorage } = {}) {
    const read = (storage, key) => { try { const parsed = JSON.parse(storage?.getItem(key) || '{}'); return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}; } catch (_) { return {}; } };
    const saved = read(localStorage, LOCAL_KEY), session = read(sessionStorage, SESSION_KEY);
    const memory = {};
    for (const provider of names) {
      const value = session[provider] || saved[provider];
      if (value && (provider !== 'MyMemory' ? configured(provider, value) : cleanCredentials(provider, value).apiKey)) memory[provider] = cleanCredentials(provider, value);
    }
    let revision = 0;
    function write(storage, key, values) { try { if (Object.keys(values).length) storage?.setItem(key, JSON.stringify(values)); else storage?.removeItem(key); return !!storage; } catch (_) { return false; } }
    function set(provider, credentials, remember = false) {
      if (!known(provider)) return false;
      const clean = cleanCredentials(provider, credentials);
      if (!configured(provider, clean)) throw new Error('请填写这个平台的 API 凭据。');
      delete saved[provider]; delete session[provider]; memory[provider] = clean;
      if (remember) saved[provider] = clean; else session[provider] = clean;
      revision++;
      const localOK = write(localStorage, LOCAL_KEY, saved), sessionOK = write(sessionStorage, SESSION_KEY, session);
      return localOK && sessionOK;
    }
    function remove(provider) {
      delete memory[provider]; delete saved[provider]; delete session[provider]; revision++;
      const localOK = write(localStorage, LOCAL_KEY, saved), sessionOK = write(sessionStorage, SESSION_KEY, session);
      return localOK && sessionOK;
    }
    return Object.freeze({ get: provider => ({ ...(memory[provider] || {}) }), has: provider => provider === 'MyMemory' ? !!memory[provider]?.apiKey : configured(provider, memory[provider]), remembered: provider => Object.hasOwn(saved, provider) && !Object.hasOwn(session, provider), set, remove, clear() { return names.map(remove).every(Boolean); }, get revision() { return revision; } });
  }
  return Object.freeze({ names, known, normalizeOrder, supports, cleanCredentials, configured, createVault, SESSION_KEY, LOCAL_KEY });
});
