// The workflow passes typed inputs as environment values, never shell source.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { appendFile, lstat, readdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const targets = [
  { id: 'apk', flag: 'BUILD_APK', label: 'Android APK (debug)', suffix: 'apk-debug', extension: 'apk' },
  { id: 'web', flag: 'BUILD_WEB', label: 'Web (release)', suffix: 'web-release', extension: 'zip' },
  { id: 'macos', flag: 'BUILD_MACOS', label: 'macOS (release)', suffix: 'macos-release', extension: 'zip' },
  { id: 'windows', flag: 'BUILD_WINDOWS', label: 'Windows (release)', suffix: 'windows-release', extension: 'zip' },
];

function flag(value, name) {
  if (value === undefined || value === '' || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error(`${name} must be true or false.`);
}

export function readConfig(env = process.env) {
  const selected = targets.filter(target => flag(env[target.flag], target.flag));
  if (!selected.length) throw new Error('Select at least one platform to build.');
  const publish = flag(env.PUBLISH_RELEASE, 'PUBLISH_RELEASE');
  const tag = (env.RELEASE_TAG || '').trim();
  const buildId = env.BUILD_ID || '';
  if (!/^\d+-\d+$/.test(buildId)) throw new Error('BUILD_ID must identify the run and attempt.');
  const repository = env.GITHUB_REPOSITORY || '';
  const sha = env.GITHUB_SHA || '';
  if (publish) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/.test(tag) || tag.includes('..') || tag.endsWith('.') || tag.endsWith('.lock')) {
      throw new Error('A new release tag is required, for example v1.0.0. Use letters, digits, dots, +, _ or -.');
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) throw new Error('Invalid GitHub repository.');
    if (!/^[a-f0-9]{40}$/.test(sha)) throw new Error('A full source commit SHA is required.');
  }
  return {
    selected, publish, tag, buildId, repository, sha,
    assetDir: resolve(env.RELEASE_ASSET_DIR || 'release-assets'),
    summaryFile: env.GITHUB_STEP_SUMMARY || '',
    runUrl: /^\d+$/.test(env.GITHUB_RUN_ID || '') ? `https://github.com/${repository}/actions/runs/${env.GITHUB_RUN_ID}` : '',
    files: selected.map(target => `langpack-${target.suffix}-${buildId}.${target.extension}`),
  };
}

function runGitHub(args) {
  try {
    return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    throw new Error(`GitHub CLI request failed (exit ${error.status ?? 'unknown'}). Check repository permissions and network access.`);
  }
}

export function assertReleaseAvailable(config, run = runGitHub) {
  const refs = JSON.parse(run(['api', `repos/${config.repository}/git/matching-refs/tags/${config.tag}`]));
  if (!Array.isArray(refs)) throw new Error('GitHub returned an invalid tag lookup.');
  if (refs.some(ref => ref.ref === `refs/tags/${config.tag}`)) throw new Error('This release tag already exists; choose a new tag.');
  const releases = run(['api', '--paginate', `repos/${config.repository}/releases?per_page=100`, '--jq', '.[].tag_name']);
  if (releases.split(/\r?\n/).includes(config.tag)) throw new Error('A release or draft already uses this tag; choose a new tag.');
}

export function validate(config, run = runGitHub) {
  if (config.publish) assertReleaseAvailable(config, run);
  return config.selected.map(target => target.label);
}

export async function publishPackages(config, run = runGitHub) {
  if (!config.publish) throw new Error('Release publishing was not selected.');
  // Recheck immediately before any write; never edit an existing release or tag.
  assertReleaseAvailable(config, run);
  const members = await readdir(config.assetDir, { withFileTypes: true });
  if (members.some(member => !member.isFile() || ![...config.files, 'SHA256SUMS.txt'].includes(member.name))) {
    throw new Error('The download contains unexpected files or directories.');
  }
  const checksums = [];
  const assets = [];
  for (const name of config.files) {
    const path = resolve(config.assetDir, name);
    const stat = await lstat(path);
    if (!stat.isFile() || stat.size === 0) throw new Error(`Missing or empty package: ${name}`);
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(path)) hash.update(chunk);
    checksums.push(`${hash.digest('hex')}  ${name}`);
    assets.push(path);
  }
  const checksumPath = resolve(config.assetDir, 'SHA256SUMS.txt');
  await writeFile(checksumPath, checksums.join('\n') + '\n');
  assets.push(checksumPath);
  const notesPath = resolve(dirname(config.assetDir), `release-notes-${config.buildId}.md`);
  const notes = [
    `LangPack ${config.tag}`,
    '',
    `Source: https://github.com/${config.repository}/commit/${config.sha}`,
    ...(config.runUrl ? [`Build: ${config.runUrl}`] : []),
    '',
    ...config.selected.map(target => `- ${target.label}`),
    '',
    'APK is a debug-signed test build. macOS is not notarized. These packages are not store releases.',
    'Extract the complete Windows archive, including DLL and data files. Web contains static Flutter files; hosted translation needs its same-origin API.',
    'SHA256SUMS.txt contains checksums for every selected package.',
    '',
  ].join('\n');
  await writeFile(notesPath, notes);
  // Upload while still a draft; an upload failure must not publish a partial release.
  run(['release', 'create', config.tag, ...assets, '--repo', config.repository,
    '--target', config.sha, '--title', `LangPack ${config.tag}`, '--notes-file', notesPath, '--draft']);
  run(['release', 'edit', config.tag, '--repo', config.repository, '--draft=false']);
  const url = `https://github.com/${config.repository}/releases/tag/${encodeURIComponent(config.tag)}`;
  if (config.summaryFile) await appendFile(config.summaryFile, `\nRelease: ${url}\n\n${config.files.map(name => `- ${name}`).join('\n')}\n`);
  return { url, files: [...config.files, 'SHA256SUMS.txt'] };
}

async function main() {
  const command = process.argv[2];
  const config = readConfig();
  if (command === 'validate') {
    console.log(`Selected packages: ${validate(config).join(', ')}. Release: ${config.publish ? config.tag : 'off'}.`);
  } else if (command === 'publish') {
    const result = await publishPackages(config);
    console.log(`Published ${result.files.length} files: ${result.url}`);
  } else throw new Error('Use validate or publish.');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
