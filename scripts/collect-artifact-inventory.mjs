#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const AREAS = Object.freeze(['flutter', 'nestjs', 'go', 'deployment', 'assets', 'docs', 'harness', 'other']);
const DEPENDENCY_MANIFESTS = Object.freeze([
  'pubspec.yaml',
  'pubspec.lock',
  'backend-nest/package.json',
  'backend-nest/package-lock.json',
  'backend-go/go.mod',
  'backend-go/go.sum',
  'docker-compose.yml',
]);
const ASSET_ROOTS = Object.freeze(['assets/', 'fonts/', 'web/vendor/', 'data/']);
const OWNER_RULES = Object.freeze([
  { prefix: 'lib/', owner: 'Flutter app' },
  { prefix: 'test/', owner: 'Flutter tests' },
  { prefix: 'backend-nest/', owner: 'NestJS API' },
  { prefix: 'backend-go/', owner: 'Go realtime service' },
  { prefix: 'deploy/', owner: 'deployment/runtime operations' },
  { prefix: 'assets/', owner: 'Flutter/platform assets' },
  { prefix: 'fonts/', owner: 'Flutter typography assets' },
  { prefix: 'web/vendor/', owner: 'web runtime vendor assets' },
  { prefix: 'docs/', owner: 'repository authority/docs' },
  { prefix: 'scripts/', owner: 'repository tooling' },
  { prefix: '.github/', owner: 'CI/release automation' },
  { prefix: 'n8n/', owner: 'legacy workflow reference; deletion requires operational proof' },
]);

function git(args) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', windowsHide: true });
}

function pathsFromNul(output) {
  return String(output || '').split('\0').map((value) => value.replaceAll('\\', '/')).filter(Boolean).sort();
}

function trackedPaths() {
  return pathsFromNul(git(['ls-files', '--cached', '-z']));
}

function ignoredPaths() {
  return pathsFromNul(git(['ls-files', '--others', '--ignored', '--exclude-standard', '-z']));
}

function areaFor(relative) {
  if (relative.startsWith('lib/') || relative.startsWith('test/') || relative.startsWith('pubspec')) return 'flutter';
  if (relative.startsWith('backend-nest/')) return 'nestjs';
  if (relative.startsWith('backend-go/')) return 'go';
  if (relative.startsWith('deploy/') || relative === 'docker-compose.yml' || relative.startsWith('.github/')) return 'deployment';
  if (relative.startsWith('assets/') || relative.startsWith('fonts/') || relative.startsWith('web/vendor/')) return 'assets';
  if (relative.startsWith('docs/') || relative.endsWith('.md')) return 'docs';
  if (relative.startsWith('scripts/') || relative === 'AGENTS.md' || relative.startsWith('.agents/')) return 'harness';
  return 'other';
}

function ownerFor(relative) {
  return OWNER_RULES.find((rule) => relative.startsWith(rule.prefix))?.owner || 'repository authority review required';
}

function sha256(relative) {
  const absolute = path.resolve(ROOT, ...relative.split('/'));
  if (!existsSync(absolute) || !statSync(absolute).isFile()) return null;
  return createHash('sha256').update(readFileSync(absolute)).digest('hex');
}

function fileDescriptor(relative, { hash = false } = {}) {
  const absolute = path.resolve(ROOT, ...relative.split('/'));
  if (!existsSync(absolute) || !statSync(absolute).isFile()) {
    return { path: relative, exists: false, owner: ownerFor(relative) };
  }
  const descriptor = {
    path: relative,
    exists: true,
    bytes: statSync(absolute).size,
    area: areaFor(relative),
    owner: ownerFor(relative),
  };
  if (hash) descriptor.sha256 = sha256(relative);
  return descriptor;
}

function generatedPolicy() {
  const ignoreFile = path.join(ROOT, '.gitignore');
  const lines = readFileSync(ignoreFile, 'utf8').split(/\r?\n/);
  return lines
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .filter((line) => /build|dist|coverage|node_modules|\.dart_tool|tmp|generated|artifact|target|harness/i.test(line))
    .map((pattern) => ({ pattern, owner: 'generated/runtime output; keep ignored unless a release contract explicitly tracks it' }));
}

export function buildInventory() {
  const tracked = trackedPaths();
  const ignored = ignoredPaths();
  const byArea = Object.fromEntries(AREAS.map((area) => [area, tracked.filter((file) => areaFor(file) === area).length]));
  const assets = tracked.filter((file) => ASSET_ROOTS.some((prefix) => file.startsWith(prefix))).map((file) => fileDescriptor(file, { hash: true }));
  const dependencyManifests = DEPENDENCY_MANIFESTS.map((file) => fileDescriptor(file, { hash: true }));
  const runtimeHotspots = [
    'lib/features/home/presentation/widgets/home_summary_page.dart',
    'lib/features/payment_monitor/presentation/providers/payment_monitor_provider.dart',
    'backend-nest/src/home-summary/home-summary.service.ts',
    'backend-nest/src/sales-reports/sales-reports.service.ts',
    'backend-nest/src/map-vietin/map-vietin.service.ts',
    'backend-nest/src/user/user.service.ts',
  ].map((file) => fileDescriptor(file));
  return {
    formatVersion: 1,
    issue: 'OPS-73',
    phase: 'before',
    generatedAtUtc: new Date().toISOString(),
    repository: {
      head: git(['rev-parse', 'HEAD']).trim(),
      branch: git(['branch', '--show-current']).trim(),
      originStaging: (() => { try { return git(['rev-parse', 'origin/staging']).trim(); } catch { return null; } })(),
      worktreeStatus: git(['status', '--porcelain=v1', '--untracked-files=all']).trim(),
    },
    tracked: { fileCount: tracked.length, byArea, paths: tracked },
    ignoredExisting: { fileCount: ignored.length, paths: ignored.map((file) => ({ path: file, area: areaFor(file), owner: ownerFor(file) })) },
    generatedPolicy: generatedPolicy(),
    dependencies: dependencyManifests,
    assets,
    runtimeHotspots,
    ownerRules: OWNER_RULES,
    deletionBatches: [],
    rollback: { required: true, revertCommit: null, note: 'No deletion batch in this inventory-only slice.' },
  };
}

export function main(argv = process.argv.slice(2)) {
  const index = argv.indexOf('--output');
  const output = index >= 0 ? argv[index + 1] : null;
  if (!output || index !== 0 || argv.length !== 2 || output.startsWith('--')) {
    throw new Error('Usage: node scripts/collect-artifact-inventory.mjs --output <path>');
  }
  const target = path.resolve(ROOT, output);
  const inventory = buildInventory();
  writeFileSync(target, `${JSON.stringify(inventory, null, 2)}\n`, 'utf8');
  console.log(`artifact inventory written: ${path.relative(ROOT, target).replaceAll('\\', '/')}`);
  return 0;
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  try { process.exitCode = main(); } catch (error) { console.error(`ARTIFACT_INVENTORY_FAILED: ${error.message}`); process.exitCode = 2; }
}
