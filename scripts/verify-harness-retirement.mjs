#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifestPath = path.join(root, 'docs/migrations/harness-v1-retirement-manifest.json');
const allowedRetainedLegacy = new Set([
  'AGENTS.md',
  'docs/decisions/0029-adopt-upstream-repository-protocol-and-retire-protocol-v1.md',
  'docs/migrations/harness-v1-archive-manifest.json',
  'docs/migrations/harness-v1-authority-promotion.json',
  'docs/migrations/harness-v1-disposition-summary.md',
  'docs/migrations/harness-v1-disposition.json',
  'docs/migrations/harness-v1-linear-targets.json',
  'docs/migrations/harness-v1-retirement-manifest.json',
  'docs/decisions/0003-adopt-harness-durable-layer.md',
  'docs/decisions/0004-sqlite-durable-layer.md',
  'docs/decisions/0005-prebuilt-rust-harness-cli.md',
  'docs/decisions/0007-improvement-proposal-rules.md',
  'docs/decisions/0008-self-improving-harness-lifecycle.md',
  'docs/decisions/0009-separate-symphony-product-repository.md',
  'docs/decisions/0010-proof-before-cli-release-promotion.md',
  'docs/decisions/0011-reproducible-core-state.md',
  'docs/decisions/0019-repository-centered-default-workflow.md',
  'docs/decisions/0020-installation-profiles-and-knowledge-boundaries.md',
  'docs/decisions/0021-consumer-first-application-legibility-phase.md',
  'docs/decisions/0022-control-plane-freeze-and-compatibility-runway.md',
  'docs/decisions/0023-optional-consumer-ownership.md',
  'docs/decisions/0024-rust-harness-core-maintenance-cli.md',
  'docs/decisions/0025-latest-release-self-update-and-human-directed-conflicts.md',
  'docs/plans/active/OPS-64-upstream-harness-repository-cleanup.md',
  'docs/plans/active/OPS-15-harness-upstream.md',
  'docs/plans/completed/OPS-17-harness-strict-audit-wrapper.md',
]);

const deletedPatterns = [
  /(^|\/)harness-cli(?:[-.]|\/)/i,
  /(^|\/)harness\.db(?:[-.]|$)/i,
  /(^|\/)scripts\/(?:schema|adapter)\//i,
  /(^|\/)scripts\/(?:bootstrap-harness|materialize-core-state|build-harness-cli-release|harness-cli-release-changed|promote-harness-cli-release-tag|verify-harness-cli-release-identity|verify-core-snapshot|verify-core-state-ownership|verify-materialized-core-parity|validate-changeset-rebuild|verify-revision-coherence|harness-epoch-transition)\./i,
  /(^|\/)tests\/(?:adapter|changesets|ci|coherence|core|protocol|snapshot|worktrees)\//i,
  /(^|\/)docs\/contracts\/harness-(?:local-authority-adapter|orchestration|strict-audit)-v1\.md$/i,
  /(^|\/)docs\/HARNESS_(?:AUDIT|BACKLOG|COMPONENTS|MATURITY)\.md$/i,
  /(^|\/)docs\/(?:IMPROVEMENT_PROTOCOL|TRACE_SPEC|TOOL_REGISTRY)\.md$/i,
  /(^|\/)\.github\/workflows\/harness-cli-release\.yml$/i,
];

function fail(message) {
  throw new Error(`HARNESS_RETIREMENT_FAILED: ${message}`);
}

function gitFiles(args) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8', windowsHide: true })
    .split(/\r?\n/).filter(Boolean).map((value) => value.replaceAll('\\', '/'));
}

function repositoryPaths() {
  const head = gitFiles(['ls-tree', '-r', '--name-only', 'HEAD']);
  const index = gitFiles(['ls-files']);
  return [...new Set([...head, ...index])].sort();
}

function validateManifest() {
  if (!existsSync(manifestPath)) fail(`manifest missing: ${path.relative(root, manifestPath)}`);
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  if (manifest.formatVersion !== 1 || manifest.issue !== 'OPS-70') fail('manifest header is invalid');
  if (manifest.policy.databaseWritten || manifest.policy.databaseDeleted || manifest.policy.rawArchiveDeleted) {
    fail('retirement policy permits destructive database/archive action');
  }
  const entries = manifest.dispositions.flatMap((item) => item.paths.map((file) => ({ ...item, file })));
  const seen = new Set();
  for (const entry of entries) {
    if (seen.has(entry.file)) fail(`duplicate manifest path: ${entry.file}`);
    seen.add(entry.file);
    if (!entry.disposition || !entry.reasonCode || !entry.owner) fail(`incomplete entry: ${entry.file}`);
  }
  // Inspect both HEAD and the index. A staged deletion must still be covered
  // by the retirement ledger; checking only `git ls-files` would let a staged
  // legacy path disappear from the proof before the commit exists.
  const tracked = repositoryPaths();
  for (const file of tracked) {
    if (!deletedPatterns.some((pattern) => pattern.test(file))) continue;
    if (allowedRetainedLegacy.has(file)) continue;
    if (![...seen].some((entry) => entry === file || file.startsWith(`${entry.replace(/\/$/, '')}/`))) {
      fail(`legacy tracked path is not dispositioned: ${file}`);
    }
  }
  for (const entry of entries) {
    const absolute = path.join(root, entry.file);
    if (entry.disposition !== 'deleted' || !existsSync(absolute)) continue;
    if (statSync(absolute).isDirectory() && readdirSync(absolute).length === 0) continue;
    fail(`deleted path still exists: ${entry.file}`);
  }
  return { formatVersion: 1, issue: manifest.issue, entryCount: entries.length, trackedCount: tracked.length };
}

const result = validateManifest();
console.log(JSON.stringify({ status: 'passed', ...result }, null, 2));
