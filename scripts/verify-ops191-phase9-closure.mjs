#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_ARTIFACT = 'docs/migrations/ops-191-phase9-closure.json';
const SHA1_RE = /^[0-9a-f]{40}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;

export class Ops191Phase9ClosureError extends Error {}

function assert(condition, message) {
  if (!condition) throw new Ops191Phase9ClosureError(message);
}

function sha256(root, relativePath) {
  return createHash('sha256')
    .update(readFileSync(path.resolve(root, relativePath)))
    .digest('hex');
}

export function validateClosure(document, { root = ROOT } = {}) {
  assert(document && typeof document === 'object', 'closure must be an object');
  assert(document.formatVersion === 1, 'formatVersion must be 1');
  assert(document.issue === 'OPS-191', 'issue must be OPS-191');
  assert(SHA1_RE.test(String(document.sourceRevision || '')), 'sourceRevision is invalid');
  assert(document.rawArtifactsCommitted === false, 'raw artifacts must remain uncommitted');

  const authority = document.authority;
  assert(authority?.atomicAssignment?.status === 'resolved', 'atomic assignment must be resolved');
  assert(authority.atomicAssignment.issue === 'OPS-175', 'atomic assignment must point to OPS-175');
  assert(authority.atomicAssignment.pullRequest === 301, 'atomic assignment PR must be #301');
  assert(authority.atomicAssignment.implementationCommit === '2e5dc7b29beb90a9ab059d2b0ba5a8e1c8c3b95a', 'atomic assignment commit is invalid');
  assert(authority?.adminPolicyScope?.status === 'resolved', 'admin policy scope must be resolved');
  assert(authority.adminPolicyScope.issue === 'OPS-188', 'admin policy scope must point to OPS-188');
  assert(authority.adminPolicyScope.pullRequest === 314, 'admin policy scope PR must be #314');
  assert(authority.adminPolicyScope.implementationCommit === '4c1c55f081eab1470b1f45c810c874b937a4f0ea', 'admin policy scope commit is invalid');
  assert(authority?.bigQueryBatchAtomicity?.status === 'unapproved-follow-up', 'BigQuery batch atomicity must remain unapproved follow-up');

  const readiness = document.dependencyReadiness;
  assert(readiness?.status === 'passed', 'dependency readiness must pass');
  assert(readiness.doctor?.status === 'passed' && readiness.doctor.profile === 'all', 'all-profile doctor must pass');
  assert(SHA256_RE.test(String(readiness.doctor.artifactSha256 || '')), 'doctor artifact hash is invalid');
  assert(readiness.doctor.nestInstalledPackageCount === 941, 'Nest installed package count changed');
  assert(readiness.doctor.nestMissingDependencies === 0, 'Nest dependencies are missing');
  assert(readiness.doctor.flutterPackageCount === 174, 'Flutter package count changed');
  assert(readiness.doctor.flutterMissingPackages === 0 && readiness.doctor.flutterMissingPlugins === 0, 'Flutter dependencies/plugins are missing');
  assert(readiness.doctor.generatedRootsWritable === true, 'generated roots must be writable');
  assert(readiness.coldCanary?.status === 'passed', 'cold dependency canary must pass');
  assert(Array.isArray(readiness.coldCanary.profiles) && readiness.coldCanary.profiles.join(',') === 'nestjs,flutter', 'cold canary profile set is incomplete');

  const proof = document.proof;
  assert(SHA1_RE.test(String(proof?.baseRevision || '')), 'proof baseRevision is invalid');
  assert(proof.baseRevision === document.sourceRevision, 'proof must bind to source revision');
  assert(proof.flutter?.analyze?.status === 'passed' && proof.flutter.analyze.issues === 0, 'Flutter analyze must pass cleanly');
  assert(proof.flutter?.test?.status === 'passed' && proof.flutter.test.passed === 864 && proof.flutter.test.skipped === 3, 'Flutter full test result is invalid');
  assert(proof.flutter.test.retries === 0 && proof.flutter.test.missingPluginException === false, 'Flutter proof contains retry or plugin noise');
  assert(proof.nestjs?.build?.status === 'passed', 'Nest build must pass');
  assert(proof.nestjs?.test?.status === 'passed' && proof.nestjs.test.suites === 124 && proof.nestjs.test.passedSuites === 124 && proof.nestjs.test.passed === 1315 && proof.nestjs.test.skipped === 6, 'Nest full test result is invalid');
  assert(proof.nestjs.test.retries === 0, 'Nest proof contains retries');
  assert(proof.go?.test?.status === 'passed' && proof.go.test.command === 'go test ./...', 'Go proof must pass');
  assert(proof.go.test.retries === 0, 'Go proof contains retries');
  assert(Array.isArray(proof.affectedConsumers) && proof.affectedConsumers.length === 6, 'affected consumer matrix is incomplete');
  assert(Array.isArray(proof.profilesSuppressed) && proof.profilesSuppressed.length === 0, 'profiles must not be suppressed');
  assert(proof.productFailuresRetriedToGreen === 0, 'product failures must not be retried to green');
  assert(proof.stale === false, 'proof must not be stale');
  assert(document.remainingGates?.upstreamHarnessUpdater === 'blocked-upstream', 'upstream updater residual must remain explicit');
  assert(document.remainingGates?.authenticatedStagingQa === 'open', 'authenticated staging QA must remain open until observed');
  assert(document.remainingGates?.productionDeployment === 'open', 'production deployment must remain open until performed');
  assert(!/[A-Za-z]:[\\/]|\\\\|\/Users\/|\/home\//.test(JSON.stringify(document)), 'closure contains an absolute local path');

  const historicalAudit = path.resolve(root, authority.historicalAudit);
  assert(readFileSync(historicalAudit, 'utf8').length > 0, 'historical ownership audit is missing');
  return {
    status: 'passed',
    issue: document.issue,
    sourceRevision: document.sourceRevision,
    dependencyReady: readiness.status,
    flutterPassed: proof.flutter.test.passed,
    nestSuites: proof.nestjs.test.suites,
    nestPassed: proof.nestjs.test.passed,
    goStatus: proof.go.test.status,
    remainingGates: document.remainingGates,
  };
}

function parseArgs(argv) {
  const options = { artifact: DEFAULT_ARTIFACT, json: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--artifact' || argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new Ops191Phase9ClosureError(`${argument} requires a value`);
      if (argument === '--artifact') options.artifact = value;
      else options.json = value;
      index += 1;
    } else if (argument === '--help' || argument === '-h') options.help = true;
    else throw new Ops191Phase9ClosureError(`unknown argument: ${argument}`);
  }
  return options;
}

export function main(argv = process.argv.slice(2), { root = ROOT } = {}) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      console.log('Usage: node scripts/verify-ops191-phase9-closure.mjs [--artifact <path>] [--json <path>]');
      return 0;
    }
    const result = validateClosure(JSON.parse(readFileSync(path.resolve(root, options.artifact), 'utf8')), { root });
    if (options.json) writeFileSync(path.resolve(root, options.json), `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    console.log(`OPS-191 PHASE 9 CLOSURE PASS flutter=${result.flutterPassed} nest=${result.nestPassed} suites=${result.nestSuites} go=${result.goStatus}`);
    return 0;
  } catch (error) {
    console.error(`OPS-191 Phase 9 closure failed: ${error.message}`);
    return 2;
  }
}

const invoked = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
