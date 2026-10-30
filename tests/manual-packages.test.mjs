import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
  assertReleaseAvailable,
  publishPackages,
  readConfig,
  validate,
} from '../scripts/manual-packages.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixtureRoot = join(root, '.codex-build/manual-packages-20261030/test-fixtures');
const sha = '1234567890abcdef1234567890abcdef12345678';
const platforms = ['apk', 'web', 'macos', 'windows'];

function environment(overrides = {}) {
  return {
    BUILD_APK: 'true', BUILD_WEB: 'false', BUILD_MACOS: 'false', BUILD_WINDOWS: 'false',
    PUBLISH_RELEASE: 'true', RELEASE_TAG: 'v1.2.3', BUILD_ID: '42-2',
    GITHUB_REPOSITORY: 'example/langpack', GITHUB_SHA: sha, GITHUB_RUN_ID: '987',
    ...overrides,
  };
}

function github({ refs = [], releases = '', createError } = {}) {
  const calls = [];
  const run = args => {
    calls.push([...args]);
    if (args[0] === 'api') return args.some(arg => arg.includes('matching-refs')) ? JSON.stringify(refs) : releases;
    if (args[0] === 'release' && args[1] === 'create' && createError) throw createError;
    return '';
  };
  return { calls, run };
}

async function fixture(t, overrides = {}) {
  await mkdir(fixtureRoot, { recursive: true });
  const dir = await mkdtemp(join(fixtureRoot, 'case-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const assetDir = join(dir, 'release-assets');
  await mkdir(assetDir);
  const config = readConfig(environment({ RELEASE_ASSET_DIR: assetDir, ...overrides }));
  return { dir, assetDir, config };
}

for (let mask = 1; mask < 16; mask++) {
  test(`platform selection ${mask.toString(2).padStart(4, '0')} creates only the chosen package names`, () => {
    const overrides = Object.fromEntries(platforms.map((name, index) => [`BUILD_${name.toUpperCase()}`, String(Boolean(mask & (1 << index)))]));
    const config = readConfig(environment(overrides));
    assert.deepEqual(config.selected.map(target => target.id), platforms.filter((_, index) => mask & (1 << index)));
    assert.equal(config.files.length, config.selected.length);
    for (const file of config.files) assert.match(file, /^langpack-(?:apk-debug|web-release|macos-release|windows-release)-42-2\.(?:apk|zip)$/);
  });
}

test('no selected platform fails before any build is requested', () => {
  assert.throws(() => readConfig(environment({ BUILD_APK: 'false' })), /at least one platform/);
});

for (const key of ['BUILD_APK', 'BUILD_WEB', 'BUILD_MACOS', 'BUILD_WINDOWS', 'PUBLISH_RELEASE']) {
  test(`rejects non-boolean ${key} instead of treating a truthy string as selected`, () => {
    assert.throws(() => readConfig(environment({ [key]: 'yes' })), /must be true or false/);
  });
}

for (const tag of ['', '-v1', '../v1', 'v1..2', 'v1.', 'v1.lock', 'v1; echo unsafe', 'v1$(whoami)', 'v1\nv2', 'v1/ref', 'x'.repeat(81)]) {
  test(`rejects unsafe or missing tag ${JSON.stringify(tag)}`, () => {
    assert.throws(() => readConfig(environment({ RELEASE_TAG: tag })), /release tag is required/);
  });
}

test('semantic build metadata remains a literal tag argument', () => {
  const config = readConfig(environment({ RELEASE_TAG: '  v1.2.3+build.4  ' }));
  assert.equal(config.tag, 'v1.2.3+build.4');
});

test('release-off validation needs no tag, repository credential or GitHub request', () => {
  const config = readConfig(environment({ PUBLISH_RELEASE: 'false', RELEASE_TAG: '', GITHUB_REPOSITORY: '', GITHUB_SHA: '' }));
  assert.deepEqual(validate(config, () => assert.fail('release-off validation contacted GitHub')), ['Android APK (debug)']);
});

test('publishing validates repository, run identity and complete source SHA', () => {
  assert.throws(() => readConfig(environment({ GITHUB_REPOSITORY: 'other/owner/repo' })), /Invalid GitHub repository/);
  assert.throws(() => readConfig(environment({ GITHUB_SHA: 'main' })), /full source commit SHA/);
  assert.throws(() => readConfig(environment({ BUILD_ID: '42;evil' })), /BUILD_ID/);
});

test('exact existing tag blocks publication but a similar prefix does not', () => {
  const config = readConfig(environment());
  assert.throws(() => assertReleaseAvailable(config, github({ refs: [{ ref: 'refs/tags/v1.2.3' }] }).run), /tag already exists/);
  const mock = github({ refs: [{ ref: 'refs/tags/v1.2.30' }] });
  assertReleaseAvailable(config, mock.run);
  assert.equal(mock.calls.length, 2);
});

test('an existing draft or release blocks a tag even before its git ref exists', () => {
  const config = readConfig(environment());
  assert.throws(() => assertReleaseAvailable(config, github({ releases: 'v1.2.2\nv1.2.3\nv1.2.4\n' }).run), /release or draft/);
});

test('GitHub lookup errors and malformed responses fail closed', () => {
  const config = readConfig(environment());
  assert.throws(() => assertReleaseAvailable(config, () => { throw new Error('unauthorized'); }), /unauthorized/);
  assert.throws(() => assertReleaseAvailable(config, () => '{}'), /invalid tag lookup/);
  assert.throws(() => assertReleaseAvailable(config, () => 'not json'), SyntaxError);
});

test('publish cannot be called when the operator did not select release', async t => {
  const { config } = await fixture(t, { PUBLISH_RELEASE: 'false', RELEASE_TAG: '' });
  await assert.rejects(publishPackages(config, () => assert.fail('unexpected GitHub request')), /not selected/);
});

test('missing or empty selected artifacts cannot create a release', async t => {
  const { assetDir, config } = await fixture(t, { BUILD_WEB: 'true' });
  const missing = github();
  await writeFile(join(assetDir, config.files[0]), 'test APK');
  await assert.rejects(publishPackages(config, missing.run), /ENOENT/);
  assert.ok(missing.calls.every(args => args[0] === 'api'));
  await writeFile(join(assetDir, config.files[1]), '');
  const empty = github();
  await assert.rejects(publishPackages(config, empty.run), /Missing or empty package/);
  assert.ok(empty.calls.every(args => args[0] === 'api'));
});

for (const extra of ['unexpected-file', 'unexpected-directory', 'symlink']) {
  test(`${extra} in the artifact download is rejected before release writes`, async t => {
    const { assetDir, config } = await fixture(t);
    const packagePath = join(assetDir, config.files[0]);
    if (extra === 'symlink') {
      const external = join(dirname(assetDir), 'outside.txt');
      await writeFile(external, 'outside');
      await symlink(external, packagePath);
    } else {
      await writeFile(packagePath, 'fake APK test fixture');
      if (extra === 'unexpected-file') await writeFile(join(assetDir, 'other.zip'), 'not selected');
      else await mkdir(join(assetDir, 'folder'));
    }
    const mock = github();
    await assert.rejects(publishPackages(config, mock.run), /unexpected files or directories/);
    assert.ok(mock.calls.every(args => args[0] === 'api'));
  });
}

test('complete selected packages produce SHA256 sums and a draft tied to the exact tested commit', async t => {
  const { dir, assetDir, config } = await fixture(t, { BUILD_WEB: 'true', BUILD_WINDOWS: 'true' });
  const contents = new Map(config.files.map((name, index) => [name, Buffer.from(`package ${index}\n`)]));
  for (const [name, content] of contents) await writeFile(join(assetDir, name), content);
  config.summaryFile = join(dir, 'summary.md');
  const mock = github();
  const result = await publishPackages(config, mock.run);
  assert.deepEqual(result.files, [...config.files, 'SHA256SUMS.txt']);
  assert.equal(result.url, 'https://github.com/example/langpack/releases/tag/v1.2.3');
  const sums = await readFile(join(assetDir, 'SHA256SUMS.txt'), 'utf8');
  assert.equal(sums, [...contents].map(([name, content]) => `${createHash('sha256').update(content).digest('hex')}  ${name}\n`).join(''));
  const writes = mock.calls.filter(args => args[0] === 'release');
  assert.equal(writes.length, 2);
  const create = writes[0];
  assert.deepEqual(create.slice(0, 3), ['release', 'create', 'v1.2.3']);
  assert.equal(create[create.indexOf('--target') + 1], sha);
  assert.equal(create[create.indexOf('--repo') + 1], 'example/langpack');
  assert.ok(create.includes('--draft'));
  assert.deepEqual(create.slice(3, 3 + config.files.length + 1), [...config.files.map(name => join(assetDir, name)), join(assetDir, 'SHA256SUMS.txt')]);
  assert.deepEqual(writes[1], ['release', 'edit', 'v1.2.3', '--repo', 'example/langpack', '--draft=false']);
  assert.ok(mock.calls.indexOf(create) < mock.calls.indexOf(writes[1]));
  const notes = await readFile(create[create.indexOf('--notes-file') + 1], 'utf8');
  assert.match(notes, new RegExp(sha));
  assert.match(notes, /actions\/runs\/987/);
  assert.match(notes, /debug-signed/);
  assert.match(notes, /DLL and data/);
  assert.match(await readFile(config.summaryFile, 'utf8'), /releases\/tag\/v1\.2\.3/);
});

test('draft creation or upload failure never calls publish', async t => {
  const { assetDir, config } = await fixture(t);
  await writeFile(join(assetDir, config.files[0]), 'fake APK test fixture');
  const mock = github({ createError: new Error('upload failed') });
  await assert.rejects(publishPackages(config, mock.run), /upload failed/);
  assert.equal(mock.calls.filter(args => args[0] === 'release' && args[1] === 'create').length, 1);
  assert.equal(mock.calls.filter(args => args[0] === 'release' && args[1] === 'edit').length, 0);
});

test('availability is rechecked before creating any new release', async t => {
  const { assetDir, config } = await fixture(t);
  await writeFile(join(assetDir, config.files[0]), 'fake APK test fixture');
  const mock = github({ refs: [{ ref: `refs/tags/${config.tag}` }] });
  await assert.rejects(publishPackages(config, mock.run), /already exists/);
  assert.ok(mock.calls.every(args => args[0] === 'api'));
});

test('workflow publishes every nonempty successful selection, including skipped unselected jobs', async () => {
  const workflow = await readFile(join(root, '.github/workflows/manual-packages.yml'), 'utf8');
  const match = workflow.match(/  release:\n[\s\S]*?    if: >-\n([\s\S]*?)\n    runs-on:/);
  assert.ok(match, 'release job condition must be explicit');
  const expression = match[1].trim().replace(/^\$\{\{\s*/, '').replace(/\s*\}\}$/, '');
  function eligible(selected, { publish = true, cancelled = false, quality = 'success', failed } = {}) {
    const code = expression
      .replaceAll('always()', 'true')
      .replaceAll('cancelled()', String(cancelled))
      .replaceAll('inputs.publish_release', String(publish))
      .replaceAll('needs.validate.result', JSON.stringify(quality))
      .replace(/inputs\.build_(apk|web|macos|windows)/g, (_, platform) => String(selected.includes(platform)))
      .replace(/needs\.(apk|web|macos|windows)\.result/g, (_, platform) => JSON.stringify(platform === failed ? 'failure' : selected.includes(platform) ? 'success' : 'skipped'));
    assert.doesNotMatch(code, /\binputs\.|\bneeds\./);
    return Function(`"use strict"; return (${code});`)();
  }
  for (let mask = 1; mask < 16; mask++) {
    const selected = platforms.filter((_, index) => mask & (1 << index));
    assert.equal(eligible(selected), true, `selection ${selected}`);
    for (const failed of selected) assert.equal(eligible(selected, { failed }), false, `${failed} failure`);
    assert.equal(eligible(selected, { publish: false }), false);
    assert.equal(eligible(selected, { cancelled: true }), false);
    assert.equal(eligible(selected, { quality: 'failure' }), false);
  }
});
