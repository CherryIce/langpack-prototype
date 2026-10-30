/* Canonical export codes match MediaServiceClient's 35 iOS resource languages. */
(function (root, factory) {
  'use strict';
  const api = factory();
  root.LangPackLanguages = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis, function () {
  'use strict';
  const source = Object.freeze({ code: 'zh-Hans', name: '简体中文', native: '简体中文', label: '简' });
  const rows = [
    ['zh-Hant', '繁体中文', '繁體中文', '繁', 'zh-TW'],
    ['en', '英语', 'English', 'EN'],
    ['pt-BR', '葡萄牙语（巴西）', 'Português (Brasil)', 'BR'],
    ['pt-PT', '葡萄牙语（葡萄牙）', 'Português (Portugal)', 'PT'],
    ['ms', '马来语', 'Bahasa Melayu', 'MS'],
    ['th', '泰语', 'ไทย', 'TH'],
    ['fr', '法语', 'Français', 'FR'],
    ['es', '西班牙语', 'Español', 'ES'],
    ['ar', '阿拉伯语', 'العربية', 'AR'],
    ['fil', '菲律宾语', 'Filipino', 'FIL'],
    ['vi', '越南语', 'Tiếng Việt', 'VI'],
    ['ru', '俄语', 'Русский', 'RU'],
    ['tr', '土耳其语', 'Türkçe', 'TR'],
    ['id', '印度尼西亚语', 'Bahasa Indonesia', 'ID'],
    ['ja', '日语', '日本語', 'JA'],
    ['ko', '韩语', '한국어', 'KO'],
    ['de', '德语', 'Deutsch', 'DE'],
    ['hi', '印地语', 'हिन्दी', 'HI'],
    ['hu', '匈牙利语', 'Magyar', 'HU'],
    ['it', '意大利语', 'Italiano', 'IT'],
    ['ro', '罗马尼亚语', 'Română', 'RO'],
    ['sv', '瑞典语', 'Svenska', 'SV'],
    ['bg', '保加利亚语', 'Български', 'BG'],
    ['pl', '波兰语', 'Polski', 'PL'],
    ['da', '丹麦语', 'Dansk', 'DA'],
    ['fi', '芬兰语', 'Suomi', 'FI'],
    ['nl', '荷兰语', 'Nederlands', 'NL'],
    ['cs', '捷克语', 'Čeština', 'CS'],
    ['sk', '斯洛伐克语', 'Slovenčina', 'SK'],
    ['uk', '乌克兰语', 'Українська', 'UK'],
    ['el', '希腊语', 'Ελληνικά', 'EL'],
    ['nb', '书面挪威语', 'Norsk bokmål', 'NB'],
    ['hr', '克罗地亚语', 'Hrvatski', 'HR'],
    ['si', '僧伽罗语', 'සිංහල', 'SI', 'si-LK']
  ];
  // MyMemory's published choices do not distinguish these exact resource languages.
  const backupOnly = Object.freeze(['pt-BR', 'fil', 'nb']);
  const targets = Object.freeze(rows.map(([code, name, native, label, primary = code]) => Object.freeze({ code, name, native, label, primary: backupOnly.includes(code) ? null : primary, backupOnly: backupOnly.includes(code) })));
  const canonical = new Map([source, ...targets].map(language => [language.code.toLowerCase(), language.code]));
  const sourceCodes = Object.freeze(['zh-Hans', 'en']);
  const sourceFor = code => code === 'en' ? targets.find(language => language.code === 'en') : source;
  const targetsForSource = code => code === 'en' ? Object.freeze([source, ...targets.filter(language => language.code !== 'en')]) : targets;
  function normalizeTargets(values, sourceLocale = 'zh-Hans') {
    const allowed = new Set(targetsForSource(sourceLocale).map(language => language.code));
    return [...new Set((Array.isArray(values) ? values : []).map(code => typeof code === 'string' ? canonical.get(code.trim().toLowerCase()) : undefined).filter(code => allowed.has(code)))];
  }
  const primaryMap = Object.freeze(Object.fromEntries(targets.filter(language => !language.backupOnly).map(language => [language.code, language.primary])));
  const wordSpaced = Object.freeze(targets.filter(language => !['zh-Hant', 'ja', 'th'].includes(language.code)).map(language => language.code));
  return Object.freeze({ source, targets, all: Object.freeze([source, ...targets]), sourceCodes, sourceFor, targetsForSource, primaryMap, backupOnly, wordSpaced, normalizeTargets });
});
