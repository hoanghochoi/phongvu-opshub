#!/usr/bin/env node

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { runTaskLifecycle } from './task-lifecycle.mjs';

function run(command, args, { cwd, expectedStatus = 0 } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
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

function gitRefExists(cwd, ref) {
  return spawnSync('git', ['show-ref', '--verify', '--quiet', ref], {
    cwd,
    windowsHide: true,
  }).status === 0;
}

function write(file, content) {
  fs.writeFileSync(file, content, 'utf8');
}

function createFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'opshub-task-lifecycle-'));
  const seed = path.join(root, 'seed');
  const remote = path.join(root, 'remote.git');
  const canonical = path.join(root, 'canonical');
  fs.mkdirSync(seed);

  git(seed, 'init', '--initial-branch=staging');
  git(seed, 'config', 'user.name', 'OpsHub Task Lifecycle Test');
  git(seed, 'config', 'user.email', 'opshub-task-lifecycle@example.invalid');
  write(path.join(seed, 'base.txt'), 'base\n');
  write(path.join(seed, '.gitignore'), 'ignored-local.txt\n');
  git(seed, 'add', 'base.txt', '.gitignore');
  git(seed, 'commit', '-m', 'base');
  const baseSha = git(seed, 'rev-parse', 'HEAD');

  git(root, 'init', '--bare', remote);
  git(seed, 'remote', 'add', 'origin', remote);
  git(seed, 'push', '-u', 'origin', 'staging');
  git(root, '--git-dir', remote, 'symbolic-ref', 'HEAD', 'refs/heads/staging');
  git(root, 'clone', '--branch', 'staging', remote, canonical);
  git(canonical, 'config', 'user.name', 'OpsHub Task Lifecycle Test');
  git(canonical, 'config', 'user.email', 'opshub-task-lifecycle@example.invalid');

  return { root, seed, remote, canonical, baseSha };
}

function cleanupFixture(fixture) {
  const resolvedRoot = path.resolve(fixture.root);
  const resolvedTemp = path.resolve(os.tmpdir());
  assert.equal(path.dirname(resolvedRoot), resolvedTemp);
  assert.match(path.basename(resolvedRoot), /^opshub-task-lifecycle-/);
  fs.rmSync(resolvedRoot, { recursive: true, force: true });
}

function advanceRemote(fixture, name = 'remote-change') {
  const file = `${name}.txt`;
  write(path.join(fixture.seed, file), `${name}\n`);
  git(fixture.seed, 'add', file);
  git(fixture.seed, 'commit', '-m', name);
  git(fixture.seed, 'push', 'origin', 'staging');
  return git(fixture.seed, 'rev-parse', 'HEAD');
}

function createTask(fixture, branch = 'codex/ops-18-finished-task') {
  const task = path.join(fixture.root, `task-${Math.random().toString(16).slice(2)}`);
  git(fixture.canonical, 'worktree', 'add', '-b', branch, task, 'staging');
  write(path.join(task, 'task.txt'), 'task change\n');
  git(task, 'add', 'task.txt');
  git(task, 'commit', '-m', 'task change');
  return { task, branch, head: git(task, 'rev-parse', 'HEAD') };
}

function mergeTaskToRemote(fixture, task, number = 18) {
  write(path.join(fixture.seed, 'task.txt'), 'task change\n');
  git(fixture.seed, 'add', 'task.txt');
  git(fixture.seed, 'commit', '-m', `[OPS-18] Squash merge fixture (#${number})`);
  git(fixture.seed, 'push', 'origin', 'staging');
  const mergeCommit = git(fixture.seed, 'rev-parse', 'HEAD');
  return {
    number,
    state: 'MERGED',
    mergedAt: '2026-07-23T00:00:00Z',
    baseRefName: 'staging',
    headRefName: task.branch,
    headRefOid: task.head,
    mergeCommit: { oid: mergeCommit },
  };
}

function lifecycle(argv, fixture, overrides = {}) {
  return runTaskLifecycle(argv, {
    cwd: fixture.canonical,
    log: () => {},
    ...overrides,
  });
}

test('start dry-run fetches proof but does not move staging or create a task', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  const remoteSha = advanceRemote(fixture, 'dry-run-remote');
  const worktree = path.join(fixture.root, 'ops-19');

  const result = lifecycle(
    ['start', '--issue', 'OPS-19', '--slug', 'dry-run', '--worktree', worktree],
    fixture,
  );

  assert.equal(result.dryRun, true);
  assert.equal(result.stagingSha, remoteSha);
  assert.equal(git(fixture.canonical, 'rev-parse', 'staging'), fixture.baseSha);
  assert.equal(fs.existsSync(worktree), false);
  assert.equal(gitRefExists(fixture.canonical, 'refs/heads/codex/ops-19-dry-run'), false);
});

test('start fast-forwards staging and creates the task at the exact remote head', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  const remoteSha = advanceRemote(fixture, 'start-remote');
  const worktree = path.join(fixture.root, 'ops-19');

  const result = lifecycle(
    [
      'start',
      '--issue',
      'OPS-19',
      '--slug',
      'fresh-task',
      '--worktree',
      worktree,
      '--execute',
    ],
    fixture,
  );

  assert.equal(result.stagingSha, remoteSha);
  assert.equal(git(fixture.canonical, 'rev-parse', 'staging'), remoteSha);
  assert.equal(git(worktree, 'rev-parse', 'HEAD'), remoteSha);
  assert.equal(git(worktree, 'branch', '--show-current'), 'codex/ops-19-fresh-task');
});

test('start blocks a dirty canonical staging worktree', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  write(path.join(fixture.canonical, 'untracked.txt'), 'dirty\n');
  const worktree = path.join(fixture.root, 'ops-19');

  assert.throws(
    () =>
      lifecycle(
        [
          'start',
          '--issue',
          'OPS-19',
          '--slug',
          'dirty-block',
          '--worktree',
          worktree,
          '--execute',
        ],
        fixture,
      ),
    /staging worktree không sạch/,
  );
  assert.equal(fs.existsSync(worktree), false);
});

test('start blocks when fast-forward exposes an ignored legacy artifact', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  write(path.join(fixture.canonical, 'ignored-local.txt'), 'legacy artifact\n');
  write(path.join(fixture.seed, '.gitignore'), '');
  git(fixture.seed, 'add', '.gitignore');
  git(fixture.seed, 'commit', '-m', 'remove legacy ignore rule');
  git(fixture.seed, 'push', 'origin', 'staging');
  const remoteSha = git(fixture.seed, 'rev-parse', 'HEAD');
  const worktree = path.join(fixture.root, 'ops-19');

  assert.throws(
    () =>
      lifecycle(
        [
          'start',
          '--issue',
          'OPS-19',
          '--slug',
          'legacy-artifact-block',
          '--worktree',
          worktree,
          '--execute',
        ],
        fixture,
      ),
    /Fast-forward làm canonical staging bẩn/,
  );
  assert.equal(git(fixture.canonical, 'rev-parse', 'staging'), remoteSha);
  assert.equal(fs.existsSync(worktree), false);
});

test('start blocks diverged staging without changing either history', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  write(path.join(fixture.canonical, 'local.txt'), 'local\n');
  git(fixture.canonical, 'add', 'local.txt');
  git(fixture.canonical, 'commit', '-m', 'local divergence');
  const localSha = git(fixture.canonical, 'rev-parse', 'HEAD');
  const remoteSha = advanceRemote(fixture, 'remote-divergence');
  const worktree = path.join(fixture.root, 'ops-19');

  assert.throws(
    () =>
      lifecycle(
        [
          'start',
          '--issue',
          'OPS-19',
          '--slug',
          'diverged-block',
          '--worktree',
          worktree,
          '--execute',
        ],
        fixture,
      ),
    /không thể fast-forward/,
  );
  assert.equal(git(fixture.canonical, 'rev-parse', 'staging'), localSha);
  assert.equal(git(fixture.root, '--git-dir', fixture.remote, 'rev-parse', 'staging'), remoteSha);
  assert.equal(fs.existsSync(worktree), false);
});

test('start rolls back its new clean task when remote staging advances mid-create', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  const worktree = path.join(fixture.root, 'ops-19');
  const branch = 'codex/ops-19-stale-race';

  assert.throws(
    () =>
      lifecycle(
        [
          'start',
          '--issue',
          'OPS-19',
          '--slug',
          'stale-race',
          '--worktree',
          worktree,
          '--execute',
        ],
        fixture,
        { afterWorktreeCreated: () => advanceRemote(fixture, 'mid-create-remote') },
      ),
    /staging đổi khi đang tạo task/,
  );
  assert.equal(fs.existsSync(worktree), false);
  assert.equal(gitRefExists(fixture.canonical, `refs/heads/${branch}`), false);
});

test('finish fast-forwards staging then removes the clean merged worktree and branch', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  const task = createTask(fixture);
  const pr = mergeTaskToRemote(fixture, task);

  const result = lifecycle(
    [
      'finish',
      '--pr',
      '18',
      '--branch',
      task.branch,
      '--worktree',
      task.task,
      '--execute',
    ],
    fixture,
    { getPullRequest: () => pr },
  );

  assert.equal(result.stagingSha, pr.mergeCommit.oid);
  assert.equal(git(fixture.canonical, 'rev-parse', 'staging'), pr.mergeCommit.oid);
  assert.equal(fs.existsSync(task.task), false);
  assert.equal(gitRefExists(fixture.canonical, `refs/heads/${task.branch}`), false);
});

test('finish blocks an unmerged PR and preserves the task', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  const task = createTask(fixture);
  const pr = {
    number: 18,
    state: 'OPEN',
    mergedAt: null,
    baseRefName: 'staging',
    headRefName: task.branch,
    headRefOid: task.head,
    mergeCommit: null,
  };

  assert.throws(
    () =>
      lifecycle(
        [
          'finish',
          '--pr',
          '18',
          '--branch',
          task.branch,
          '--worktree',
          task.task,
          '--execute',
        ],
        fixture,
        { getPullRequest: () => pr },
      ),
    /chưa merge/,
  );
  assert.equal(fs.existsSync(task.task), true);
  assert.equal(gitRefExists(fixture.canonical, `refs/heads/${task.branch}`), true);
});

test('finish blocks a dirty merged task worktree', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  const task = createTask(fixture);
  const pr = mergeTaskToRemote(fixture, task);
  write(path.join(task.task, 'untracked.txt'), 'dirty\n');

  assert.throws(
    () =>
      lifecycle(
        [
          'finish',
          '--pr',
          '18',
          '--branch',
          task.branch,
          '--worktree',
          task.task,
          '--execute',
        ],
        fixture,
        { getPullRequest: () => pr },
      ),
    /Task worktree không sạch/,
  );
  assert.equal(fs.existsSync(task.task), true);
  assert.equal(gitRefExists(fixture.canonical, `refs/heads/${task.branch}`), true);
});

test('finish blocks ignored artifacts unless deletion is explicitly allowed', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));
  const task = createTask(fixture);
  const pr = mergeTaskToRemote(fixture, task);
  write(path.join(task.task, 'ignored-local.txt'), 'ignored artifact\n');
  const finishArgs = [
    'finish',
    '--pr',
    '18',
    '--branch',
    task.branch,
    '--worktree',
    task.task,
    '--execute',
  ];

  assert.throws(
    () => lifecycle(finishArgs, fixture, { getPullRequest: () => pr }),
    /ignored artifact/,
  );
  assert.equal(fs.existsSync(task.task), true);

  const result = lifecycle([...finishArgs, '--allow-ignored'], fixture, {
    getPullRequest: () => pr,
  });
  assert.equal(result.stagingSha, pr.mergeCommit.oid);
  assert.equal(fs.existsSync(task.task), false);
  assert.equal(gitRefExists(fixture.canonical, `refs/heads/${task.branch}`), false);
});

test('finish rejects protected branches before inspecting a deletion target', (t) => {
  const fixture = createFixture();
  t.after(() => cleanupFixture(fixture));

  assert.throws(
    () =>
      lifecycle(
        [
          'finish',
          '--pr',
          '18',
          '--branch',
          'staging',
          '--worktree',
          path.join(fixture.root, 'never-touch'),
          '--execute',
        ],
        fixture,
      ),
    /protected branch staging/,
  );
});
