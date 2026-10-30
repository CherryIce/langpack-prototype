import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const catalog = require('../web/languages.js');
// Taken from MediaServiceClient's Language-*.json resource suffixes.
const expected = ['zh-Hant', 'en', 'pt-BR', 'pt-PT', 'ms', 'th', 'fr', 'es', 'ar', 'fil', 'vi', 'ru', 'tr', 'id', 'ja', 'ko', 'de', 'hi', 'hu', 'it', 'ro', 'sv', 'bg', 'pl', 'da', 'fi', 'nl', 'cs', 'sk', 'uk', 'el', 'nb', 'hr', 'si'];

test('Web and Flutter expose the same 35 resource languages with Chinese source-only', async () => {
  assert.equal(catalog.source.code, 'zh-Hans');
  assert.equal(catalog.all.length, 35);
  assert.deepEqual(catalog.targets.map(language => language.code), expected);
  const dart = await readFile(new URL('../flutter_app/lib/models.dart', import.meta.url), 'utf8');
  const languages = [...dart.matchAll(/Language\('([^']+)'/g)].map(match => match[1]);
  assert.deepEqual(languages, expected);
});
