#!/usr/bin/env node

import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const AREAS = new Set(['flutter', 'nestjs', 'go', 'deployment', 'assets', 'docs', 'harness', 'other']);

function fail(message) { throw new Error(`ARTIFACT_INVENTORY_INVALID: ${message}`); }
function noAbsolute(value) { return typeof value === 'string' && !/^(?:[A-Za-z]:[\\/]|[\\/]{2}|file:)/.test(value); }
function isSafeRelativePath(value) {
  const normalized = typeof value === 'string' ? value.replaceAll('\\', '/') : '';
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    noAbsolute(value) &&
    !normalized.split('/').includes('..')
  );
}

export function validateInventory(document) {
  if (document?.formatVersion !== 1 || document.issue !== 'OPS-73' || document.phase !== 'before') fail('invalid header');
  if (!/^[0-9a-f]{40}$/.test(document.repository?.head || '')) fail('repository head is not a SHA');
  for (const collection of ['tracked', 'ignoredExisting', 'dependencies', 'assets', 'runtimeHotspots']) {
    if (!document[collection]) fail(`missing ${collection}`);
  }
  if (document.tracked.fileCount !== document.tracked.paths.length) fail('tracked count mismatch');
  if (document.ignoredExisting.fileCount !== document.ignoredExisting.paths.length) fail('ignored count mismatch');
  const seen = new Set();
  for (const relative of document.tracked.paths) {
    if (!isSafeRelativePath(relative) || seen.has(relative)) fail(`invalid/duplicate tracked path: ${relative}`);
    seen.add(relative);
  }
  for (const entry of [...document.ignoredExisting.paths, ...document.dependencies, ...document.assets, ...document.runtimeHotspots]) {
    if (!isSafeRelativePath(entry.path)) fail(`invalid path: ${entry.path}`);
    if (entry.area && !AREAS.has(entry.area)) fail(`unknown area for ${entry.path}`);
    if (!entry.owner) fail(`missing owner for ${entry.path}`);
  }
  if (!Array.isArray(document.ownerRules) || document.ownerRules.length === 0) fail('owner rules missing');
  if (!Array.isArray(document.deletionBatches) || document.deletionBatches.length !== 0) fail('inventory-only slice cannot contain deletion batches');
  if (document.rollback?.required !== true || document.rollback?.revertCommit !== null) fail('rollback checkpoint invalid');
  return { status: 'passed', trackedCount: document.tracked.fileCount, ignoredCount: document.ignoredExisting.fileCount, dependencyCount: document.dependencies.length, assetCount: document.assets.length, deletionBatchCount: document.deletionBatches.length };
}

export function main(argv = process.argv.slice(2)) {
  const index = argv.indexOf('--input');
  const input = index >= 0 ? argv[index + 1] : null;
  if (!input || index !== 0 || argv.length !== 2 || input.startsWith('--')) throw new Error('Usage: node scripts/verify-artifact-inventory.mjs --input <path>');
  const target = path.resolve(ROOT, input);
  if (!existsSync(target)) fail(`missing input: ${input}`);
  const result = validateInventory(JSON.parse(readFileSync(target, 'utf8')));
  console.log(JSON.stringify(result, null, 2));
  return 0;
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  try { process.exitCode = main(); } catch (error) { console.error(error.message); process.exitCode = 2; }
}
