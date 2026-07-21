#!/usr/bin/env node

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { verifyGithubCi } from './promote-production.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const promotionScript = path.join(repoRoot, 'scripts', 'promote-production.mjs');

function run(command, args, { cwd, expectedStatus = 0, env = {} } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
    env: { ...process.env, ...env },
  });
  if (result.error) throw result.error;
  assert.equal(
    result.status,
    expectedStatus,
    `${command} ${args.join(' ')}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
  return result;
}

function git(cwd, ...args) {
  return run('git', args, { cwd }).stdout.trim();
}

function write(file, content) {
  fs.writeFileSync(file, content, 'utf8');
}

function createFixture({ diverged = false } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'opshub-promotion-'));
  const seed = path.join(root, 'seed');
  const remote = path.join(root, 'remote.git');
  const worker = path.join(root, 'worker');
  fs.mkdirSync(seed);

  git(seed, 'init', '--initial-branch=main');
  git(seed, 'config', 'user.name', 'OpsHub Promotion Test');
  git(seed, 'config', 'user.email', 'opshub-promotion-test@example.invalid');
  write(path.join(seed, 'release.txt'), 'base\n');
  git(seed, 'add', 'release.txt');
  git(seed, 'commit', '-m', 'base');
  const baseSha = git(seed, 'rev-parse', 'HEAD');

  git(root, 'init', '--bare', remote);
  git(seed, 'remote', 'add', 'origin', remote);
  git(seed, 'push', 'origin', 'main');

  if (diverged) {
    write(path.join(seed, 'main.txt'), 'main-only\n');
    git(seed, 'add', 'main.txt');
    git(seed, 'commit', '-m', 'main diverges');
    git(seed, 'push', 'origin', 'main');
    git(seed, 'checkout', '-b', 'staging', baseSha);
  } else {
    git(seed, 'checkout', '-b', 'staging');
  }

  write(path.join(seed, 'staging.txt'), 'staging release\n');
  git(seed, 'add', 'staging.txt');
  git(seed, 'commit', '-m', 'staging release');
  const stagingSha = git(seed, 'rev-parse', 'HEAD');
  git(seed, 'push', 'origin', 'staging');
  git(root, '--git-dir', remote, 'symbolic-ref', 'HEAD', 'refs/heads/main');
  git(root, 'clone', '--branch', 'main', remote, worker);

  return {
    root,
    remote,
    worker,
    baseSha,
    stagingSha,
    originalMainSha: git(root, '--git-dir', remote, 'rev-parse', 'refs/heads/main'),
  };
}

function cleanupFixture(fixture) {
  const resolvedRoot = path.resolve(fixture.root);
  const resolvedTemp = path.resolve(os.tmpdir());
  assert.equal(path.dirname(resolvedRoot), resolvedTemp);
  assert.match(path.basename(resolvedRoot), /^opshub-promotion-/);
  fs.rmSync(resolvedRoot, { recursive: true, force: true });
}

function promotionArgs(stagingSha, extra = []) {
  return [
    promotionScript,
    '--expected-sha',
    stagingSha,
    '--authorized-by',
    'test-suite',
    '--ci-confirmed',
    '--qa-confirmed',
    '--release-window-locked',
    ...extra,
  ];
}

function remoteSha(fixture, branch) {
  return git(fixture.root, '--git-dir', fixture.remote, 'rev-parse', `refs/heads/${branch}`);
}

test('dry-run passes without changing remote main', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));

  const result = run(process.execPath, promotionArgs(fixture.stagingSha), { cwd: fixture.worker });
  assert.match(result.stdout, /DRY RUN PASS/);
  assert.equal(remoteSha(fixture, 'main'), fixture.originalMainSha);
  assert.equal(remoteSha(fixture, 'staging'), fixture.stagingSha);
});

test('execute fast-forwards main to the exact staging SHA', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));

  const result = run(process.execPath, promotionArgs(fixture.stagingSha, ['--execute']), {
    cwd: fixture.worker,
  });
  assert.match(result.stdout, /PROMOTION PASS/);
  assert.equal(remoteSha(fixture, 'main'), fixture.stagingSha);
  assert.equal(remoteSha(fixture, 'staging'), fixture.stagingSha);
});

test('diverged main and staging are blocked without changing either ref', (t) => {
  const fixture = createFixture({ diverged: true });
  t.after(() => cleanupFixture(fixture));

  const result = run(process.execPath, promotionArgs(fixture.stagingSha, ['--execute']), {
    cwd: fixture.worker,
    expectedStatus: 1,
  });
  assert.match(result.stderr, /không phải ancestor/);
  assert.equal(remoteSha(fixture, 'main'), fixture.originalMainSha);
  assert.equal(remoteSha(fixture, 'staging'), fixture.stagingSha);
});

test('stale expected staging SHA is blocked', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));

  const result = run(process.execPath, promotionArgs(fixture.originalMainSha, ['--execute']), {
    cwd: fixture.worker,
    expectedStatus: 1,
  });
  assert.match(result.stderr, /Staging SHA đã đổi/);
  assert.equal(remoteSha(fixture, 'main'), fixture.originalMainSha);
});

test('missing QA confirmation is blocked', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));

  const args = [
    promotionScript,
    '--expected-sha',
    fixture.stagingSha,
    '--ci-confirmed',
    '--release-window-locked',
    '--execute',
  ];
  const result = run(process.execPath, args, { cwd: fixture.worker, expectedStatus: 1 });
  assert.match(result.stderr, /Thiếu --qa-confirmed/);
  assert.equal(remoteSha(fixture, 'main'), fixture.originalMainSha);
});

test('dirty worktree is blocked', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  write(path.join(fixture.worker, 'untracked.txt'), 'dirty\n');

  const result = run(process.execPath, promotionArgs(fixture.stagingSha, ['--execute']), {
    cwd: fixture.worker,
    expectedStatus: 1,
  });
  assert.match(result.stderr, /Working tree không sạch/);
  assert.equal(remoteSha(fixture, 'main'), fixture.originalMainSha);
});

test('GitHub CI verification accepts completed checks and rejects failures', async () => {
  const sha = 'a'.repeat(40);
  const successFetch = async (url) => {
    const isCheckRuns = String(url).includes('/check-runs');
    return {
      ok: true,
      status: 200,
      async json() {
        return isCheckRuns
          ? {
              total_count: 1,
              check_runs: [{ name: 'Deploy OpsHub Staging', status: 'completed', conclusion: 'success' }],
            }
          : [];
      },
    };
  };
  const evidence = await verifyGithubCi({
    apiUrl: 'https://example.invalid',
    repository: 'example/repo',
    sha,
    token: 'redacted-test-token',
    fetchImpl: successFetch,
  });
  assert.deepEqual(evidence, { checkRunCount: 1, statusCount: 0 });

  const failureFetch = async (url) => ({
    ok: true,
    status: 200,
    async json() {
      return String(url).includes('/check-runs')
        ? {
            total_count: 1,
            check_runs: [{ name: 'Deploy OpsHub Staging', status: 'completed', conclusion: 'failure' }],
          }
        : [];
    },
  });
  await assert.rejects(
    verifyGithubCi({
      apiUrl: 'https://example.invalid',
      repository: 'example/repo',
      sha,
      token: 'redacted-test-token',
      fetchImpl: failureFetch,
    }),
    /CI check chưa đạt/,
  );
});

test('workflow and policy preserve existing deploy consumers and never force push', () => {
  const promotionWorkflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'promote-production.yml'),
    'utf8',
  );
  const productionWorkflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'deploy-opshub.yml'),
    'utf8',
  );
  const stagingWorkflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'deploy-opshub-staging.yml'),
    'utf8',
  );
  const policy = fs.readFileSync(path.join(repoRoot, 'AGENTS.md'), 'utf8');
  const guard = fs.readFileSync(promotionScript, 'utf8');

  assert.match(promotionWorkflow, /workflow_dispatch:/);
  assert.match(promotionWorkflow, /group: production-promotion/);
  assert.match(promotionWorkflow, /environment: production/);
  assert.match(promotionWorkflow, /actions\/create-github-app-token@fee1f7d63c2ff003460e3d139729b119787bc349/);
  assert.match(promotionWorkflow, /--verify-github-ci/);
  assert.match(promotionWorkflow, /--execute/);
  assert.doesNotMatch(promotionWorkflow, /push\s+--force|--force-with-lease/);
  assert.doesNotMatch(guard, /push[^\n]*--force|--force-with-lease/);

  assert.match(productionWorkflow, /push:\s*\n\s*branches:\s*\n\s*- main/);
  assert.match(stagingWorkflow, /push:\s*\n\s*branches:\s*\n\s*- staging/);
  assert.match(policy, /explicit\s+command in the current task/);
  assert.match(policy, /Never promote an\s+arbitrary task branch or SHA to `main`/);
  assert.match(policy, /Never force-push or delete `staging` or `main`/);
});
