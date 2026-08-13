#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const activeDir = path.join(root, 'docs/plans/active');
const completedDir = path.join(root, 'docs/plans/completed');
const ledgerPath = path.join(root, 'docs/migrations/ops-71-plan-disposition.json');
const allowed = new Set([
  'active',
  'execution-complete',
  'release-pending',
  'superseded',
  'cancelled',
  'duplicate/stale',
]);

function fail(message) {
  throw new Error(`PLAN_DISPOSITION_FAILED: ${message}`);
}

function normalize(value) {
  return String(value).trim().replaceAll('\\', '/').replace(/^\.\//, '');
}

function isUnsafePath(value) {
  return value.startsWith('/') || /^[A-Za-z]:\//.test(value) || value.split('/').includes('..');
}

function filesIn(directory) {
  return readdirSync(directory)
    .filter((name) => statSync(path.join(directory, name)).isFile())
    .map((name) => normalize(path.relative(root, path.join(directory, name))))
    .sort();
}

function assertRelativePath(label, value) {
  if (!value || isUnsafePath(value)) fail(`${label} is not a sanitized repository path`);
  if (!value.startsWith('docs/plans/')) fail(`${label} leaves docs/plans: ${value}`);
}

function existsAtRevision(revision, repositoryPath) {
  try {
    execFileSync('git', ['cat-file', '-e', `${revision}:${repositoryPath}`], {
      cwd: root,
      stdio: 'ignore',
      windowsHide: true,
    });
    return true;
  } catch {
    return false;
  }
}

function validate() {
  if (!existsSync(ledgerPath)) fail('ledger is missing');
  const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
  if (ledger.formatVersion !== 1 || ledger.issue !== 'OPS-71') fail('invalid ledger header');
  if (!/^[0-9a-f]{40}$/i.test(String(ledger.sourceRevision || ''))) fail('sourceRevision is invalid');
  if (!Array.isArray(ledger.records) || ledger.records.length === 0) fail('records are missing');

  const activeFiles = filesIn(activeDir);
  const completedFiles = filesIn(completedDir);
  const seenPaths = new Set();
  const seenSourcePaths = new Set();
  const activeRecords = [];

  for (const [index, record] of ledger.records.entries()) {
    if (!record || typeof record !== 'object') fail(`record ${index} is not an object`);
    const recordPath = normalize(record.path || '');
    assertRelativePath(`record ${index}.path`, recordPath);
    if (seenPaths.has(recordPath)) fail(`duplicate path: ${recordPath}`);
    seenPaths.add(recordPath);
    if (!allowed.has(record.disposition)) fail(`unsupported disposition for ${recordPath}`);
    if (!record.owner || !record.reasonCode) fail(`missing owner/reason for ${recordPath}`);
    if (record.location === 'active') {
      if (!recordPath.startsWith('docs/plans/active/')) fail(`active record outside active/: ${recordPath}`);
      activeRecords.push(recordPath);
      if (!record.nextAction) fail(`active record has no nextAction: ${recordPath}`);
      if (!activeFiles.includes(recordPath)) fail(`active record path does not exist: ${recordPath}`);
    } else if (record.location === 'completed') {
      if (!recordPath.startsWith('docs/plans/completed/')) fail(`completed record outside completed/: ${recordPath}`);
      if (!completedFiles.includes(recordPath)) fail(`completed record path does not exist: ${recordPath}`);
    } else {
      fail(`record location is invalid for ${recordPath}`);
    }

    if (record.sourcePath) {
      const sourcePath = normalize(record.sourcePath);
      assertRelativePath(`sourcePath for ${recordPath}`, sourcePath);
      if (!existsAtRevision(ledger.sourceRevision, sourcePath)) {
        fail(`sourcePath does not exist at sourceRevision: ${sourcePath}`);
      }
      if (seenSourcePaths.has(sourcePath)) fail(`duplicate sourcePath: ${sourcePath}`);
      seenSourcePaths.add(sourcePath);
      if (activeFiles.includes(sourcePath) && normalize(record.canonicalPath || '') !== sourcePath) {
        fail(`retired sourcePath still active: ${sourcePath}`);
      }
    }

    if (record.disposition === 'superseded' || record.disposition === 'execution-complete' || record.disposition === 'duplicate/stale') {
      if (!record.canonicalPath) fail(`canonicalPath missing for ${recordPath}`);
      const canonical = normalize(record.canonicalPath);
      assertRelativePath(`canonicalPath for ${recordPath}`, canonical);
      if (!activeFiles.includes(canonical) && !completedFiles.includes(canonical)) {
        fail(`canonicalPath does not exist for ${recordPath}: ${canonical}`);
      }
    }
    if (record.disposition === 'cancelled' && !record.reason) fail(`cancelled record has no reason: ${recordPath}`);
    if ((record.disposition === 'active' || record.disposition === 'release-pending') && !record.canonicalPath) {
      fail(`current record has no canonicalPath: ${recordPath}`);
    }
    if (record.canonicalPath) assertRelativePath(`canonicalPath for ${recordPath}`, normalize(record.canonicalPath));
    if (record.evidence && /(?:[A-Za-z]:[\\/]|\\\\|%USERPROFILE%|%APPDATA%)/i.test(String(record.evidence))) {
      fail(`evidence contains a local path: ${recordPath}`);
    }
  }

  activeRecords.sort();
  if (activeRecords.length !== activeFiles.length) {
    fail(`active coverage mismatch: ledger=${activeRecords.length}, filesystem=${activeFiles.length}`);
  }
  for (let index = 0; index < activeFiles.length; index += 1) {
    if (activeFiles[index] !== activeRecords[index]) fail(`active file missing or duplicated: ${activeFiles[index]}`);
  }

  const summary = {
    status: 'passed',
    issue: ledger.issue,
    sourceRevision: ledger.sourceRevision,
    activeCount: activeFiles.length,
    completedDispositionCount: ledger.records.filter((record) => record.location === 'completed').length,
    dispositionCounts: Object.fromEntries([...allowed].map((value) => [value, ledger.records.filter((record) => record.disposition === value).length])),
  };
  console.log(JSON.stringify(summary, null, 2));
}

try {
  validate();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 2;
}
