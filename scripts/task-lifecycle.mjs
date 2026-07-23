#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const PROTECTED_BRANCHES = new Set(['main', 'staging']);
const SHA_PATTERN = /^[0-9a-f]{40}$/i;

function blocked(message) {
  throw new Error(message);
}

function run(command, args, { cwd, allowFailure = false } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true,
  });

  if (result.error) {
    blocked(`Không chạy được ${command}: ${result.error.message}`);
  }
  if (!allowFailure && result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    blocked(`${command} thất bại (${args[0]}): ${detail || `exit ${result.status}`}`);
  }
  return result;
}

function git(cwd, args, options = {}) {
  return run('git', args, { cwd, ...options });
}

function gitOutput(cwd, args) {
  return git(cwd, args).stdout.trim();
}

function refExists(cwd, ref) {
  return git(cwd, ['show-ref', '--verify', '--quiet', ref], { allowFailure: true }).status === 0;
}

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes('--help')) return { help: true };

  const command = argv[0];
  if (!['start', 'finish'].includes(command)) {
    blocked(`Lệnh không hỗ trợ: ${command}`);
  }

  const options = {
    command,
    execute: false,
    allowIgnored: false,
    remote: 'origin',
  };
  const valueOptions = new Map([
    ['--remote', 'remote'],
    ['--worktree', 'worktree'],
    ['--issue', 'issue'],
    ['--slug', 'slug'],
    ['--pr', 'pr'],
    ['--branch', 'branch'],
  ]);

  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--execute') {
      options.execute = true;
      continue;
    }
    if (argument === '--allow-ignored') {
      options.allowIgnored = true;
      continue;
    }
    if (valueOptions.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) blocked(`Thiếu giá trị cho ${argument}`);
      options[valueOptions.get(argument)] = value;
      index += 1;
      continue;
    }
    blocked(`Tham số không hỗ trợ: ${argument}`);
  }

  return options;
}

function printHelp(log) {
  log(`Usage:
  node scripts/task-lifecycle.mjs start \\
    --issue OPS-123 --slug short-description --worktree ..\\opshub-ops-123 [--execute]

  node scripts/task-lifecycle.mjs finish \\
    --pr 123 --branch codex/ops-123-short-description \\
    --worktree ..\\opshub-ops-123 [--execute] [--allow-ignored]

Run both commands from the canonical clean staging worktree. The default is a
dry-run. --execute may fast-forward local staging. start creates a task
worktree/local branch; finish removes a clean merged task worktree/local branch.
Remote branches are never deleted.`);
}

function validateRemote(remote) {
  if (!/^[A-Za-z0-9._-]+$/.test(remote || '')) blocked('Tên remote không hợp lệ.');
}

function canonicalStaging(cwd) {
  if (gitOutput(cwd, ['rev-parse', '--is-inside-work-tree']) !== 'true') {
    blocked('Thư mục hiện tại không phải Git worktree.');
  }

  const root = path.resolve(gitOutput(cwd, ['rev-parse', '--show-toplevel']));
  const branch = gitOutput(root, ['branch', '--show-current']);
  if (branch !== 'staging') {
    blocked('Phải chạy từ canonical worktree đang checkout branch staging.');
  }

  const dirty = gitOutput(root, ['status', '--porcelain=v1', '--untracked-files=all']);
  if (dirty) blocked('Canonical staging worktree không sạch; không được tiếp tục.');
  return root;
}

function liveStagingSha(cwd, remote) {
  const result = git(cwd, ['ls-remote', '--exit-code', remote, 'refs/heads/staging']);
  const lines = result.stdout.trim().split(/\r?\n/).filter(Boolean);
  if (lines.length !== 1) blocked(`Không xác định được duy nhất ${remote}/staging.`);
  const sha = lines[0].trim().split(/\s+/)[0]?.toLowerCase();
  if (!SHA_PATTERN.test(sha || '')) blocked(`SHA live của ${remote}/staging không hợp lệ.`);
  return sha;
}

function remoteBranchExists(cwd, remote, branch) {
  const result = git(cwd, ['ls-remote', '--heads', remote, `refs/heads/${branch}`]);
  return result.stdout.trim().length > 0;
}

function syncCanonicalStaging({ cwd, remote, execute }) {
  const root = canonicalStaging(cwd);
  const remoteRef = `refs/remotes/${remote}/staging`;
  git(root, [
    'fetch',
    '--no-tags',
    remote,
    `refs/heads/staging:${remoteRef}`,
  ]);

  const fetchedSha = gitOutput(root, ['rev-parse', remoteRef]).toLowerCase();
  const liveBefore = liveStagingSha(root, remote);
  if (fetchedSha !== liveBefore) {
    blocked(
      `${remote}/staging đổi trong lúc fetch: fetched=${fetchedSha} live=${liveBefore}. Chạy lại.`,
    );
  }

  const localBefore = gitOutput(root, ['rev-parse', 'staging']).toLowerCase();
  const changed = localBefore !== fetchedSha;
  if (changed) {
    const ancestor = git(root, ['merge-base', '--is-ancestor', localBefore, fetchedSha], {
      allowFailure: true,
    });
    if (ancestor.status !== 0) {
      blocked(
        `Local staging không thể fast-forward tới ${remote}/staging: ` +
          `local=${localBefore} remote=${fetchedSha}.`,
      );
    }
    if (execute) git(root, ['merge', '--ff-only', remoteRef]);
  }

  const localAfter = gitOutput(root, ['rev-parse', 'staging']).toLowerCase();
  if (execute && localAfter !== fetchedSha) {
    blocked(`Fast-forward không đạt: local=${localAfter} remote=${fetchedSha}.`);
  }
  const dirtyAfterSync = gitOutput(root, ['status', '--porcelain=v1', '--untracked-files=all']);
  if (dirtyAfterSync) {
    blocked('Fast-forward làm canonical staging bẩn; không được mở task mới.');
  }
  if (!execute && localAfter !== localBefore) {
    blocked('Dry-run đã làm thay đổi local staging; dừng để kiểm tra.');
  }

  const liveAfter = liveStagingSha(root, remote);
  if (liveAfter !== fetchedSha) {
    blocked(
      `${remote}/staging đổi sau preflight: fetched=${fetchedSha} live=${liveAfter}. Chạy lại.`,
    );
  }

  return {
    root,
    remoteRef,
    stagingSha: fetchedSha,
    localBefore,
    localAfter,
    changed,
  };
}

function pathKey(value) {
  const resolved = path.resolve(value);
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
}

function registeredWorktrees(cwd) {
  const result = new Map();
  for (const line of gitOutput(cwd, ['worktree', 'list', '--porcelain']).split(/\r?\n/)) {
    if (!line.startsWith('worktree ')) continue;
    const worktreePath = path.resolve(line.slice('worktree '.length));
    result.set(pathKey(worktreePath), worktreePath);
  }
  return result;
}

function isInside(candidate, parent) {
  const relative = path.relative(parent, candidate);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function validateStartOptions(options, root) {
  const issue = (options.issue || '').toUpperCase();
  if (!/^OPS-\d+$/.test(issue)) blocked('--issue phải có dạng OPS-123.');
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(options.slug || '')) {
    blocked('--slug chỉ dùng chữ thường, số và dấu gạch nối.');
  }
  if (!options.worktree) blocked('Thiếu --worktree cho task mới.');

  const branch = `codex/${issue.toLowerCase()}-${options.slug}`;
  const worktree = path.resolve(root, options.worktree);
  if (isInside(worktree, root)) {
    blocked('Task worktree phải nằm ngoài canonical repository directory.');
  }
  if (!fs.existsSync(path.dirname(worktree))) {
    blocked(`Thư mục cha của task worktree không tồn tại: ${path.dirname(worktree)}`);
  }
  return { issue, branch, worktree };
}

function validateFinishOptions(options) {
  if (!/^[1-9]\d*$/.test(options.pr || '')) blocked('--pr phải là số PR hợp lệ.');
  if (!options.branch) blocked('Thiếu --branch của task đã merge.');
  if (PROTECTED_BRANCHES.has(options.branch)) {
    blocked(`Không được cleanup protected branch ${options.branch}.`);
  }
  if (!/^codex\/ops-\d+-[a-z0-9]+(?:-[a-z0-9]+)*$/.test(options.branch)) {
    blocked('--branch phải có dạng codex/ops-123-short-description.');
  }
  if (!options.worktree) blocked('Thiếu --worktree của task đã merge.');
  return { pr: Number(options.pr), branch: options.branch };
}

function readPullRequest({ cwd, pr }) {
  const result = run(
    'gh',
    [
      'pr',
      'view',
      String(pr),
      '--json',
      'number,state,mergedAt,baseRefName,headRefName,headRefOid,mergeCommit',
    ],
    { cwd },
  );
  try {
    return JSON.parse(result.stdout);
  } catch {
    blocked(`GitHub CLI trả JSON không hợp lệ cho PR #${pr}.`);
  }
}

function validateMergedPr(pr, { number, branch, head }) {
  if (pr.number !== number) blocked(`PR trả về sai số: expected=${number} actual=${pr.number}.`);
  if (pr.state !== 'MERGED' || !pr.mergedAt) blocked(`PR #${number} chưa merge.`);
  if (pr.baseRefName !== 'staging') blocked(`PR #${number} không merge vào staging.`);
  if (pr.headRefName !== branch) {
    blocked(`PR #${number} thuộc branch ${pr.headRefName}, không phải ${branch}.`);
  }
  const prHead = String(pr.headRefOid || '').toLowerCase();
  if (!SHA_PATTERN.test(prHead) || prHead !== head) {
    blocked(`PR #${number} head không khớp task worktree: pr=${prHead} worktree=${head}.`);
  }
  const mergeCommit = String(pr.mergeCommit?.oid || '').toLowerCase();
  if (!SHA_PATTERN.test(mergeCommit)) blocked(`PR #${number} thiếu merge commit hợp lệ.`);
  return mergeCommit;
}

function inspectTaskWorktree(root, worktree, expectedBranch, { allowIgnored = false } = {}) {
  const target = path.resolve(root, worktree);
  if (pathKey(target) === pathKey(root)) blocked('Không được cleanup canonical staging worktree.');
  const registered = registeredWorktrees(root);
  if (!registered.has(pathKey(target))) blocked(`Task worktree chưa đăng ký: ${target}`);
  if (!fs.existsSync(target)) blocked(`Task worktree không tồn tại: ${target}`);

  const branch = gitOutput(target, ['branch', '--show-current']);
  if (branch !== expectedBranch) {
    blocked(`Task worktree checkout ${branch || '(detached)'}, không phải ${expectedBranch}.`);
  }
  const head = gitOutput(target, ['rev-parse', 'HEAD']).toLowerCase();
  const status = gitOutput(target, [
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
    '--ignored',
  ]);
  const entries = status ? status.split(/\r?\n/).filter(Boolean) : [];
  const dirty = entries.filter((entry) => !entry.startsWith('!! '));
  const ignored = entries.filter((entry) => entry.startsWith('!! '));
  if (dirty.length > 0) blocked(`Task worktree không sạch: ${target}`);
  if (ignored.length > 0 && !allowIgnored) {
    blocked(
      `Task worktree có ignored artifact; thêm --allow-ignored nếu đã review việc xoá: ${target}`,
    );
  }
  return { target, head, ignoredCount: ignored.length };
}

function rollbackNewTask({ root, worktree, branch }) {
  const registered = registeredWorktrees(root);
  if (registered.has(pathKey(worktree))) {
    const dirty = gitOutput(worktree, ['status', '--porcelain=v1', '--untracked-files=all']);
    if (dirty) blocked(`Không thể rollback task mới vì worktree đã bẩn: ${worktree}`);
    git(root, ['-c', 'core.longpaths=true', 'worktree', 'remove', '--', worktree]);
  }
  if (refExists(root, `refs/heads/${branch}`)) git(root, ['branch', '-D', branch]);
}

function printSync(log, sync, remote, execute) {
  log(`Canonical staging: ${sync.localBefore}`);
  log(`${remote}/staging: ${sync.stagingSha}`);
  if (sync.changed) {
    log(execute ? 'Fast-forward staging: PASS' : 'Fast-forward staging: REQUIRED on --execute');
  } else {
    log('Fast-forward staging: already current');
  }
}

function startTask(options, dependencies) {
  const { cwd, log, afterWorktreeCreated } = dependencies;
  const root = canonicalStaging(cwd);
  if (options.allowIgnored) blocked('--allow-ignored chỉ áp dụng cho finish sau khi review artifact.');
  const task = validateStartOptions(options, root);
  const sync = syncCanonicalStaging({ cwd: root, remote: options.remote, execute: options.execute });
  if (fs.existsSync(task.worktree)) blocked(`Task worktree path đã tồn tại: ${task.worktree}`);
  if (refExists(root, `refs/heads/${task.branch}`)) blocked(`Local branch đã tồn tại: ${task.branch}`);
  if (
    refExists(root, `refs/remotes/${options.remote}/${task.branch}`) ||
    remoteBranchExists(root, options.remote, task.branch)
  ) {
    blocked(`Remote branch đã tồn tại: ${options.remote}/${task.branch}`);
  }
  log('=== OpsHub task start gate ===');
  printSync(log, sync, options.remote, options.execute);
  log(`Task branch: ${task.branch}`);
  log(`Task worktree: ${task.worktree}`);

  if (!options.execute) {
    log(`DRY RUN PASS: task sẽ bắt đầu tại ${sync.stagingSha}; chưa tạo worktree/branch.`);
    return { action: 'start', dryRun: true, ...task, stagingSha: sync.stagingSha };
  }

  const localBeforeCreate = gitOutput(root, ['rev-parse', 'staging']).toLowerCase();
  if (localBeforeCreate !== sync.stagingSha) {
    blocked(
      `Local staging đổi sau preflight: expected=${sync.stagingSha} actual=${localBeforeCreate}.`,
    );
  }
  git(root, ['worktree', 'add', '-b', task.branch, task.worktree, sync.stagingSha]);
  try {
    const created = inspectTaskWorktree(root, task.worktree, task.branch);
    if (created.head !== sync.stagingSha) {
      blocked(`Task HEAD sai: expected=${sync.stagingSha} actual=${created.head}.`);
    }
    afterWorktreeCreated({ root, ...task, stagingSha: sync.stagingSha });
    const liveAfterCreate = liveStagingSha(root, options.remote);
    if (liveAfterCreate !== sync.stagingSha) {
      blocked(
        `${options.remote}/staging đổi khi đang tạo task: ` +
          `task=${sync.stagingSha} live=${liveAfterCreate}.`,
      );
    }
  } catch (error) {
    rollbackNewTask({ root, worktree: task.worktree, branch: task.branch });
    throw error;
  }

  log(`START PASS: ${task.branch} @ ${sync.stagingSha}`);
  return { action: 'start', dryRun: false, ...task, stagingSha: sync.stagingSha };
}

function finishTask(options, dependencies) {
  const { cwd, log, getPullRequest } = dependencies;
  const root = canonicalStaging(cwd);
  const finish = validateFinishOptions(options);
  const inspected = inspectTaskWorktree(root, options.worktree, finish.branch, {
    allowIgnored: options.allowIgnored,
  });
  const pr = getPullRequest({ cwd: root, pr: finish.pr });
  const mergeCommit = validateMergedPr(pr, {
    number: finish.pr,
    branch: finish.branch,
    head: inspected.head,
  });
  const sync = syncCanonicalStaging({ cwd: root, remote: options.remote, execute: options.execute });

  const reachable = git(root, ['merge-base', '--is-ancestor', mergeCommit, sync.remoteRef], {
    allowFailure: true,
  });
  if (reachable.status !== 0) {
    blocked(`Merge commit ${mergeCommit} của PR #${finish.pr} chưa có trong ${options.remote}/staging.`);
  }

  log('=== OpsHub merged task finish gate ===');
  printSync(log, sync, options.remote, options.execute);
  log(`Merged PR: #${finish.pr}`);
  log(`Task branch: ${finish.branch} @ ${inspected.head}`);
  log(`Task worktree: ${inspected.target}`);

  if (!options.execute) {
    log('DRY RUN PASS: đủ điều kiện cleanup; chưa xoá worktree/branch.');
    return {
      action: 'finish',
      dryRun: true,
      ...finish,
      worktree: inspected.target,
      taskHead: inspected.head,
      stagingSha: sync.stagingSha,
    };
  }

  const rechecked = inspectTaskWorktree(root, inspected.target, finish.branch, {
    allowIgnored: options.allowIgnored,
  });
  if (rechecked.head !== inspected.head) blocked('Task HEAD đổi sau preflight; dừng cleanup.');
  const liveBeforeCleanup = liveStagingSha(root, options.remote);
  if (liveBeforeCleanup !== sync.stagingSha) {
    blocked(`${options.remote}/staging đổi trước cleanup; chạy lại finish.`);
  }

  git(root, ['-c', 'core.longpaths=true', 'worktree', 'remove', '--', inspected.target]);
  if (registeredWorktrees(root).has(pathKey(inspected.target)) || fs.existsSync(inspected.target)) {
    blocked(`Worktree cleanup chưa hoàn tất: ${inspected.target}`);
  }

  const branchRef = `refs/heads/${finish.branch}`;
  if (!refExists(root, branchRef)) blocked(`Local branch biến mất trước cleanup: ${finish.branch}`);
  const branchHead = gitOutput(root, ['rev-parse', branchRef]).toLowerCase();
  if (branchHead !== inspected.head) {
    blocked(`Local branch head đổi trước cleanup: expected=${inspected.head} actual=${branchHead}.`);
  }
  git(root, ['branch', '-D', finish.branch]);

  const localFinal = gitOutput(root, ['rev-parse', 'staging']).toLowerCase();
  const liveFinal = liveStagingSha(root, options.remote);
  if (localFinal !== liveFinal) {
    blocked(
      `Cleanup đã xong nhưng staging vừa đổi: local=${localFinal} live=${liveFinal}. ` +
        'Phải đồng bộ staging lại trước task mới.',
    );
  }

  log(`FINISH PASS: staging=${localFinal}; đã cleanup ${finish.branch}`);
  return {
    action: 'finish',
    dryRun: false,
    ...finish,
    worktree: inspected.target,
    taskHead: inspected.head,
    stagingSha: localFinal,
  };
}

export function runTaskLifecycle(argv, overrides = {}) {
  const options = parseArgs(argv);
  const dependencies = {
    cwd: overrides.cwd || process.cwd(),
    log: overrides.log || console.log,
    getPullRequest: overrides.getPullRequest || readPullRequest,
    afterWorktreeCreated: overrides.afterWorktreeCreated || (() => {}),
  };
  if (options.help) {
    printHelp(dependencies.log);
    return { action: 'help' };
  }

  validateRemote(options.remote);
  return options.command === 'start'
    ? startTask(options, dependencies)
    : finishTask(options, dependencies);
}

const invokedAsScript = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedAsScript) {
  try {
    runTaskLifecycle(process.argv.slice(2));
  } catch (error) {
    console.error(`BLOCKED: ${error.message}`);
    process.exitCode = 1;
  }
}
