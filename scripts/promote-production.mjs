#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const ALLOWED_CHECK_CONCLUSIONS = new Set(['success', 'neutral', 'skipped']);

function blocked(message) {
  throw new Error(message);
}

function git(args, { allowFailure = false } = {}) {
  const result = spawnSync('git', args, {
    cwd: process.cwd(),
    encoding: 'utf8',
    windowsHide: true,
  });

  if (result.error) {
    blocked(`Không chạy được Git: ${result.error.message}`);
  }
  if (!allowFailure && result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    blocked(`Git thất bại (${args[0]}): ${detail || `exit ${result.status}`}`);
  }
  return result;
}

function output(args) {
  return git(args).stdout.trim();
}

function parseArgs(argv) {
  const options = {
    remote: 'origin',
    execute: false,
    ciConfirmed: false,
    qaConfirmed: false,
    releaseWindowLocked: false,
    verifyGithubCi: false,
    authorizedBy: process.env.GITHUB_ACTOR || 'local-operator',
  };

  const valueOptions = new Map([
    ['--expected-sha', 'expectedSha'],
    ['--remote', 'remote'],
    ['--authorized-by', 'authorizedBy'],
  ]);
  const booleanOptions = new Map([
    ['--execute', 'execute'],
    ['--ci-confirmed', 'ciConfirmed'],
    ['--qa-confirmed', 'qaConfirmed'],
    ['--release-window-locked', 'releaseWindowLocked'],
    ['--verify-github-ci', 'verifyGithubCi'],
  ]);

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help') {
      options.help = true;
      continue;
    }
    if (booleanOptions.has(argument)) {
      options[booleanOptions.get(argument)] = true;
      continue;
    }
    if (valueOptions.has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        blocked(`Thiếu giá trị cho ${argument}`);
      }
      options[valueOptions.get(argument)] = value;
      index += 1;
      continue;
    }
    blocked(`Tham số không hỗ trợ: ${argument}`);
  }

  return options;
}

function printHelp() {
  console.log(`Usage:
  node scripts/promote-production.mjs --expected-sha <40-char-sha> \\
    --ci-confirmed --qa-confirmed --release-window-locked [--verify-github-ci] [--execute]

The command only promotes origin/staging to main. It defaults to dry-run and
never performs a force push. --verify-github-ci reads GITHUB_REPOSITORY and a
GH_TOKEN or GITHUB_TOKEN without printing the token.`);
}

async function githubJson({ apiUrl, repository, token, path, fetchImpl }) {
  const response = await fetchImpl(`${apiUrl}/repos/${repository}${path}`, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'User-Agent': 'opshub-production-promotion',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!response.ok) {
    blocked(`GitHub CI API trả HTTP ${response.status} cho ${path.split('?')[0]}`);
  }
  return response.json();
}

async function githubPages({ apiUrl, repository, token, path, key, fetchImpl }) {
  const items = [];
  for (let page = 1; page <= 20; page += 1) {
    const separator = path.includes('?') ? '&' : '?';
    const body = await githubJson({
      apiUrl,
      repository,
      token,
      path: `${path}${separator}per_page=100&page=${page}`,
      fetchImpl,
    });
    const pageItems = key ? body[key] : body;
    if (!Array.isArray(pageItems)) {
      blocked(`GitHub CI API trả payload không hợp lệ cho ${path.split('?')[0]}`);
    }
    items.push(...pageItems);
    if (pageItems.length < 100) return items;
  }
  blocked('GitHub CI API vượt quá giới hạn 2.000 kết quả; dừng promotion để kiểm tra thủ công.');
}

export async function verifyGithubCi({
  apiUrl = 'https://api.github.com',
  repository,
  sha,
  token,
  fetchImpl = fetch,
}) {
  if (!repository || !/^[^/]+\/[^/]+$/.test(repository)) {
    blocked('Thiếu hoặc sai GITHUB_REPOSITORY để kiểm tra CI.');
  }
  if (!token) blocked('Thiếu GH_TOKEN/GITHUB_TOKEN để kiểm tra CI.');

  const encodedSha = encodeURIComponent(sha);
  const checkRuns = await githubPages({
    apiUrl,
    repository,
    token,
    path: `/commits/${encodedSha}/check-runs?filter=latest`,
    key: 'check_runs',
    fetchImpl,
  });
  const statuses = await githubPages({
    apiUrl,
    repository,
    token,
    path: `/commits/${encodedSha}/statuses`,
    fetchImpl,
  });

  if (checkRuns.length === 0 && statuses.length === 0) {
    blocked('Không tìm thấy CI/status nào cho staging SHA; không được promotion.');
  }

  const failedRuns = checkRuns.filter(
    (run) => run.status !== 'completed' || !ALLOWED_CHECK_CONCLUSIONS.has(run.conclusion),
  );
  if (failedRuns.length > 0) {
    const names = failedRuns.slice(0, 5).map((run) => run.name || 'unnamed').join(', ');
    blocked(`CI check chưa đạt: ${names}`);
  }

  const latestStatuses = new Map();
  for (const status of statuses) {
    if (!latestStatuses.has(status.context)) latestStatuses.set(status.context, status);
  }
  const failedStatuses = [...latestStatuses.values()].filter((status) => status.state !== 'success');
  if (failedStatuses.length > 0) {
    const names = failedStatuses.slice(0, 5).map((status) => status.context || 'unnamed').join(', ');
    blocked(`Commit status chưa đạt: ${names}`);
  }

  return { checkRunCount: checkRuns.length, statusCount: latestStatuses.size };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  if (!/^[A-Za-z0-9._-]+$/.test(options.remote)) blocked('Tên remote không hợp lệ.');
  if (!/^[0-9a-fA-F]{40}$/.test(options.expectedSha || '')) {
    blocked('--expected-sha phải là SHA 40 ký tự đã QA trên staging.');
  }
  if (!options.ciConfirmed) blocked('Thiếu --ci-confirmed.');
  if (!options.qaConfirmed) blocked('Thiếu --qa-confirmed.');
  if (!options.releaseWindowLocked) blocked('Thiếu --release-window-locked.');

  if (output(['rev-parse', '--is-inside-work-tree']) !== 'true') {
    blocked('Thư mục hiện tại không phải Git worktree.');
  }
  const dirty = output(['status', '--porcelain=v1', '--untracked-files=normal']);
  if (dirty) blocked('Working tree không sạch; dừng promotion.');

  const mainRef = `refs/remotes/${options.remote}/main`;
  const stagingRef = `refs/remotes/${options.remote}/staging`;
  git([
    'fetch',
    '--no-tags',
    options.remote,
    `refs/heads/main:${mainRef}`,
    `refs/heads/staging:${stagingRef}`,
  ]);

  const stagingSha = output(['rev-parse', stagingRef]).toLowerCase();
  const mainSha = output(['rev-parse', mainRef]).toLowerCase();
  if (stagingSha !== options.expectedSha.toLowerCase()) {
    blocked(`Staging SHA đã đổi: expected=${options.expectedSha.toLowerCase()} actual=${stagingSha}`);
  }

  const ancestor = git(['merge-base', '--is-ancestor', mainRef, stagingRef], { allowFailure: true });
  if (ancestor.status !== 0) {
    blocked('origin/main không phải ancestor của origin/staging; chỉ cho phép fast-forward.');
  }

  let githubCi = null;
  if (options.verifyGithubCi) {
    githubCi = await verifyGithubCi({
      apiUrl: process.env.GITHUB_API_URL || 'https://api.github.com',
      repository: process.env.GITHUB_REPOSITORY,
      sha: stagingSha,
      token: process.env.GH_TOKEN || process.env.GITHUB_TOKEN,
    });
  }

  console.log('=== OpsHub production promotion gate ===');
  console.log(`Nguồn: ${options.remote}/staging (${stagingSha})`);
  console.log(`Đích: ${options.remote}/main (${mainSha})`);
  console.log(`Người yêu cầu: ${options.authorizedBy}`);
  console.log(`Working tree: PASS`);
  console.log(`Fast-forward: PASS`);
  console.log(`QA: PASS (explicit confirmation)`);
  console.log(
    githubCi
      ? `CI: PASS (checks=${githubCi.checkRunCount}, statuses=${githubCi.statusCount})`
      : 'CI: PASS (operator confirmation; GitHub API verification not requested)',
  );
  console.log(`Release window: PASS (locked)`);

  if (!options.execute) {
    console.log('DRY RUN PASS: không push ref nào.');
    return;
  }

  console.log('Hành động: push trực tiếp origin/staging -> main theo lệnh explicit.');
  git(['push', options.remote, `${stagingSha}:refs/heads/main`]);
  git([
    'fetch',
    '--no-tags',
    options.remote,
    `refs/heads/main:${mainRef}`,
    `refs/heads/staging:${stagingRef}`,
  ]);

  const finalMainSha = output(['rev-parse', mainRef]).toLowerCase();
  const finalStagingSha = output(['rev-parse', stagingRef]).toLowerCase();
  if (finalMainSha !== stagingSha || finalStagingSha !== stagingSha) {
    blocked(
      `Promotion đã push nhưng refs không còn đồng nhất: main=${finalMainSha} staging=${finalStagingSha}. ` +
        'Khóa release và đánh giá lại; không tự rollback.',
    );
  }

  console.log(`PROMOTION PASS: origin/main = origin/staging = ${stagingSha}`);
}

const invokedAsScript = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedAsScript) {
  main().catch((error) => {
    console.error(`BLOCKED: ${error.message}`);
    process.exitCode = 1;
  });
}
