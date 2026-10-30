const { test } = require('node:test');
const assert = require('node:assert/strict');
const Languages = require('../web/languages.js');
require('../web/engine.js');
const Engine = globalThis.LangPackEngine;

const resourceCodes = ['zh-Hans', 'zh-Hant', 'en', 'pt-BR', 'pt-PT', 'ms', 'th', 'fr', 'es', 'ar', 'fil', 'vi', 'ru', 'tr', 'id', 'ja', 'ko', 'de', 'hi', 'hu', 'it', 'ro', 'sv', 'bg', 'pl', 'da', 'fi', 'nl', 'cs', 'sk', 'uk', 'el', 'nb', 'hr', 'si'];

test('language catalogue covers the 35 resource languages with a fixed source and 34 distinct targets', () => {
  assert.deepEqual(Languages.all.map(language => language.code), resourceCodes);
  assert.equal(Languages.source.code, 'zh-Hans');
  assert.equal(Languages.targets.length, 34);
  assert.equal(new Set(Languages.targets.map(language => language.code)).size, 34);
  assert.equal(Languages.targets.some(language => language.code === 'zh-Hans'), false);
  assert.equal(Object.keys(Languages.primaryMap).length, 31);
  assert.equal(Languages.primaryMap['zh-Hant'], 'zh-TW');
  assert.equal(Languages.primaryMap['pt-PT'], 'pt-PT');
  assert.equal(Languages.primaryMap.si, 'si-LK');
  assert.deepEqual(Languages.backupOnly, ['pt-BR', 'fil', 'nb']);
  for (const code of Languages.backupOnly) assert.equal(Object.hasOwn(Languages.primaryMap, code), false);
});

test('recent target normalization preserves canonical regions, filters source/unknown values and removes duplicates', () => {
  assert.deepEqual(Languages.normalizeTargets(['EN', ' en ', 'pt-br', 'pt-PT', 'zh-Hans', 'xx', null, 12, 'fil', 'tl-PH', 'nb', 'no', 'si', 'sl']), ['en', 'pt-BR', 'pt-PT', 'fil', 'nb', 'si']);
  assert.deepEqual(Languages.normalizeTargets(null), []);
  assert.deepEqual(Languages.normalizeTargets('en'), []);
});

test('new language exports use canonical file names and never invent demonstration translations', () => {
  assert.deepEqual(Engine.localeCodes, ['en', 'ja', 'ko', 'fr', 'de', 'es', 'zh-Hant']);
  for (const code of ['pt-BR', 'pt-PT', 'fil', 'nb', 'si']) assert.deepEqual(Engine.translate('登录', code), { text: '', demo: true, known: false });
  const entries = [{ id: 'one', key: 'login', source: '登录', translations: Object.fromEntries(Languages.targets.map(language => [language.code, 'Provider result: ' + language.code])) }];
  const packages = Engine.makePackages(entries, Languages.targets.map(language => language.code), true);
  assert.deepEqual(Object.keys(packages).sort(), resourceCodes.map(code => code + '.json').sort());
  assert.equal(JSON.parse(packages['pt-BR.json']).login, 'Provider result: pt-BR');
  assert.equal(JSON.parse(packages['pt-PT.json']).login, 'Provider result: pt-PT');
  assert.equal(JSON.parse(packages['fil.json']).login, 'Provider result: fil');
  assert.equal(JSON.parse(packages['nb.json']).login, 'Provider result: nb');
  assert.equal(JSON.parse(packages['si.json']).login, 'Provider result: si');
});
