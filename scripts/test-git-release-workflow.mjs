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
const cloudflarePublicProbe = fs.readFileSync(
  path.join(repoRoot, 'deploy', 'home-server', 'cloudflare-public-probe.sh'),
  'utf8',
);

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
  assert.deepEqual(evidence, {
    checkRunCount: 1,
    ignoredPromotionCheckRunCount: 0,
    statusCount: 0,
  });

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

test('GitHub CI verification ignores only promotion self-checks', async () => {
  const sha = 'b'.repeat(40);
  const responseFor = (checkRuns) => async (url) => ({
    ok: true,
    status: 200,
    async json() {
      return String(url).includes('/check-runs')
        ? { total_count: checkRuns.length, check_runs: checkRuns }
        : [];
    },
  });
  const failedPromotionCheck = {
    name: 'Fast-forward origin/staging to main',
    status: 'completed',
    conclusion: 'failure',
    details_url: 'https://github.com/example/repo/actions/runs/123/job/456',
    app: { slug: 'github-actions' },
  };
  const successfulSourceCheck = {
    name: 'Deploy OpsHub Staging',
    status: 'completed',
    conclusion: 'success',
    details_url: 'https://github.com/example/repo/actions/runs/120/job/450',
    app: { slug: 'github-actions' },
  };

  const evidence = await verifyGithubCi({
    apiUrl: 'https://example.invalid',
    repository: 'example/repo',
    sha,
    token: 'redacted-test-token',
    fetchImpl: responseFor([failedPromotionCheck, successfulSourceCheck]),
  });
  assert.deepEqual(evidence, {
    checkRunCount: 1,
    ignoredPromotionCheckRunCount: 1,
    statusCount: 0,
  });

  await assert.rejects(
    verifyGithubCi({
      apiUrl: 'https://example.invalid',
      repository: 'example/repo',
      sha,
      token: 'redacted-test-token',
      fetchImpl: responseFor([
        failedPromotionCheck,
        { ...successfulSourceCheck, conclusion: 'failure' },
      ]),
    }),
    /CI check chưa đạt: Deploy OpsHub Staging/,
  );
});

test('workflow and policy preserve existing deploy consumers and never force push', () => {
  const promotionWorkflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'promote-production.yml'),
    'utf8',
  );
  const prWorkflow = fs.readFileSync(
    path.join(repoRoot, '.github', 'workflows', 'release-guard-pr.yml'),
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
  const homeCompose = fs.readFileSync(
    path.join(repoRoot, 'deploy', 'home-server', 'docker-compose.home.yml'),
    'utf8',
  );
  const bidvBootstrap = fs.readFileSync(
    path.join(repoRoot, 'deploy', 'home-server', 'bootstrap-bidv-kek.sh'),
    'utf8',
  );
  const policy = fs.readFileSync(path.join(repoRoot, 'AGENTS.md'), 'utf8');
  const playbook = fs.readFileSync(
    path.join(repoRoot, 'docs', 'runbooks', 'git-release-playbook.md'),
    'utf8',
  );
  const guard = fs.readFileSync(promotionScript, 'utf8');

  assert.match(promotionWorkflow, /workflow_dispatch:/);
  assert.match(promotionWorkflow, /run-name: Promote origin\/staging to main from workflow ref/);
  assert.match(promotionWorkflow, /group: production-promotion/);
  assert.match(promotionWorkflow, /environment: production/);
  assert.match(promotionWorkflow, /actions\/create-github-app-token@fee1f7d63c2ff003460e3d139729b119787bc349/);
  assert.match(promotionWorkflow, /--verify-github-ci/);
  assert.match(promotionWorkflow, /--execute/);
  assert.doesNotMatch(promotionWorkflow, /push\s+--force|--force-with-lease/);
  assert.doesNotMatch(guard, /push[^\n]*--force|--force-with-lease/);

  assert.match(prWorkflow, /name: Release Guard PR/);
  assert.match(prWorkflow, /pull_request:/);
  assert.match(prWorkflow, /- staging/);
  assert.match(prWorkflow, /- main/);
  assert.match(prWorkflow, /name: Release guard/);
  assert.match(prWorkflow, /node scripts\/test-git-release-workflow\.mjs/);
  assert.match(prWorkflow, /node scripts\/test-task-lifecycle\.mjs/);
  assert.match(prWorkflow, /git diff --check/);
  assert.doesNotMatch(prWorkflow, /secrets\.|GH_TOKEN|GITHUB_TOKEN/);

  assert.match(productionWorkflow, /push:\s*\n\s*branches:\s*\n\s*- main/);
  assert.match(stagingWorkflow, /push:\s*\n\s*branches:\s*\n\s*- staging/);
  for (const [environment, workflow] of [
    ['staging', stagingWorkflow],
    ['production', productionWorkflow],
  ]) {
    assert.match(
      workflow,
      /bash deploy\/home-server\/bootstrap-bidv-kek\.sh "\$OPSHUB_ENV_FILE"/,
      `${environment} deploy must run the BIDV KEK bootstrap`,
    );
  }
  assert.match(
    bidvBootstrap,
    /docker compose --env-file "\$ENV_FILE" -f "\$COMPOSE_FILE" "\$@" < \/dev\/null/,
    'BIDV bootstrap must isolate Compose from the remote SSH heredoc stdin',
  );
  assert.match(stagingWorkflow, /verify_download_artifact\(\)/);
  assert.match(stagingWorkflow, /opshub_cloudflare_public_artifact "\$url"/);
  assert.match(stagingWorkflow, /'staging\.phongvu\.work' 'opshub-staging\.hoanghochoi\.com'/);
  assert.match(stagingWorkflow, /Staging artifact verification attempt \$\{attempt\}\/12/);
  assert.doesNotMatch(stagingWorkflow, /curl -fIs/);
  assert.match(stagingWorkflow, /<title>Tải ứng dụng PhongVu OpsHub<\/title>/);
  assert.doesNotMatch(stagingWorkflow, /CF-Access-Client-Id:/);
  const stagingPublicVerification = stagingWorkflow.match(
    /- name: Verify staging public health and version metadata[\s\S]*?(?=\n\s+- name: Roll back staging after failed release verification)/,
  )?.[0];
  assert.ok(stagingPublicVerification, 'staging public verification step is missing');
  assert.match(stagingPublicVerification, /Cloudflare Bot Fight Mode challenges GitHub-hosted runner egress/);
  assert.match(stagingPublicVerification, /ssh opshub-staging/);
  assert.match(stagingPublicVerification, /source "\$PUBLIC_PROBE_SCRIPT"/);
  assert.match(stagingPublicVerification, /opshub_api_node -e/);
  assert.doesNotMatch(stagingPublicVerification, /\bnode -e/);
  assert.match(stagingPublicVerification, /opshub_cloudflare_headers_valid/);
  assert.match(stagingPublicVerification, /staging\.phongvu\.work/);
  assert.match(stagingPublicVerification, /api-staging\.phongvu\.work/);
  assert.match(stagingPublicVerification, /opshub-staging\.hoanghochoi\.com/);
  assert.doesNotMatch(
    stagingPublicVerification,
    /\bpublic_curl\b/,
    'staging shared-probe verification must not call the removed inline curl wrapper',
  );
  assert.ok(
    stagingPublicVerification.indexOf('ssh opshub-staging') <
      stagingPublicVerification.indexOf('source "$PUBLIC_PROBE_SCRIPT"'),
    'staging public probe must execute inside the remote SSH boundary',
  );
  const productionPublicVerification = productionWorkflow.match(
    /- name: Verify public health and version metadata[\s\S]*?(?=\n\s+- name: Restore production Tunnel after failed public verification)/,
  )?.[0];
  assert.ok(productionPublicVerification, 'production public verification step is missing');
  assert.match(productionPublicVerification, /Cloudflare Bot Fight Mode challenges GitHub-hosted runner egress/);
  assert.match(productionPublicVerification, /ssh opshub-vps/);
  assert.match(productionPublicVerification, /verify_cloudflare_edge_headers\(\)/);
  assert.match(productionPublicVerification, /\^cf-ray:/);
  assert.ok(
    productionPublicVerification.indexOf('ssh opshub-vps') <
      productionPublicVerification.indexOf('source "$PUBLIC_PROBE_SCRIPT"'),
    'production public probe must execute inside the remote SSH boundary',
  );
  assert.match(productionWorkflow, /name: Capture live app-version metadata through Cloudflare/);
  assert.match(productionWorkflow, /remote_public_curl\(\)/);
  assert.match(
    productionPublicVerification,
    /source "\$PUBLIC_PROBE_SCRIPT"/,
    'full production verification must use the shared Cloudflare probe',
  );
  assert.match(productionPublicVerification, /opshub_api_node -e/);
  assert.doesNotMatch(productionPublicVerification, /\bnode -e/);
  assert.doesNotMatch(
    productionPublicVerification,
    /fs\.readFileSync\(/,
    'containerized Node validation must not read host-only temporary files',
  );
  assert.match(productionPublicVerification, /token_json="\$\(cat "\$token_body"\)"/);
  assert.match(productionPublicVerification, /JSON\.parse\(payload\)\.error/);
  assert.ok(
    (productionWorkflow.match(/< deploy\/home-server\/cloudflare-public-probe\.sh/g) || []).length >= 5,
    'static capture, verification, artifact, and rollback probes must stream the shared validator',
  );
  assert.doesNotMatch(
    productionWorkflow,
    /\[\[ "\$status" == 2\* \]\] &&/,
    'public response probes must fail explicitly before emitting a body',
  );
  assert.match(cloudflarePublicProbe, /%\{url_effective\}/);
  assert.match(cloudflarePublicProbe, /opshub_cloudflare_final_headers\(\)/);
  assert.match(cloudflarePublicProbe, /opshub_cloudflare_artifact_host_allowed\(\)/);
  assert.match(cloudflarePublicProbe, /opshub_api_node\(\)/);
  assert.match(cloudflarePublicProbe, /exec -T api node "\$@" < \/dev\/null/);
  assert.match(cloudflarePublicProbe, /"\$\{allowed_hosts\[@\]\}"/);
  assert.match(cloudflarePublicProbe, /\^\(\[\[:alnum:\]\.\-\]\+\)\(:443\)\?\$/);
  assert.match(
    fs.readFileSync(path.join(repoRoot, 'scripts', 'build-runtime-release.mjs'), 'utf8'),
    /deploy\/home-server\/cloudflare-public-probe\.sh/,
    'full production runtime package must include the shared Cloudflare probe',
  );
  assert.doesNotMatch(
    productionWorkflow,
    /curl -fsS "\$\{OPSHUB_API_BASE_URL\}\/(?:app-version|help-content\/public)/,
    'GitHub-hosted production jobs must not probe public API URLs directly',
  );
  assert.match(stagingWorkflow, /compose_cmd up -d --no-deps --force-recreate --wait --wait-timeout 120 caddy/);
  assert.match(stagingWorkflow, /wait_for_caddy_ready\(\)/);
  assert.match(stagingWorkflow, /expected_caddy_config_hash/);
  assert.match(stagingWorkflow, /test -s \/srv\/web\/index\.html/);
  assert.match(
    stagingWorkflow,
    /Host: unknown\.staging\.phongvu\.work[\s\S]*?unknown\.staging\.phongvu\.work\/health returned \$\{unknown_host_status\}; expected 404/,
    'staging must reject unknown direct-origin hostnames before release acceptance',
  );
  assert.match(productionWorkflow, /run_compose_or_rollback up -d --no-deps --force-recreate --wait --wait-timeout 120 caddy/);
  assert.match(productionWorkflow, /expected_caddy_config_hash/);
  assert.match(homeCompose, /healthcheck:/);
  assert.match(
    fs.readFileSync(path.join(repoRoot, 'scripts', 'verification-profiles.mjs'), 'utf8'),
    /caddy-host-isolation-runtime-contract[\s\S]*?test-caddy-host-isolation\.mjs/,
    'deployment verification must execute the real Caddy host-isolation contract',
  );
  assert.match(homeCompose, /wget -qO- --header="Host: \$\$OPSHUB_DOMAIN"/);
  assert.match(homeCompose, /http:\/\/127\.0\.0\.1\/health \| grep -qx ok/);
  assert.match(
    stagingWorkflow,
    /action-staging\/\$\{GITHUB_RUN_ID\}\/android/,
  );
  assert.doesNotMatch(
    stagingWorkflow,
    /action-staging\/\$\{GITHUB_RUN_ID\}-\$\{GITHUB_RUN_ATTEMPT\}/,
  );
  assert.match(
    productionWorkflow,
    /action-staging\/\$\{GITHUB_RUN_ID\}\/android/,
  );
  assert.doesNotMatch(
    productionWorkflow,
    /action-staging\/\$\{GITHUB_RUN_ID\}-\$\{GITHUB_RUN_ATTEMPT\}/,
  );
  const productionRemoteEnvironment = productionWorkflow.match(
    /ssh opshub-vps \\\n+\s*"REMOTE_RELEASE_DIR[\s\S]*?\s+bash -s"/,
  )?.[0];
  assert.ok(
    productionRemoteEnvironment,
    'production deploy must define the remote SSH environment block',
  );
  assert.match(
    productionRemoteEnvironment,
    /OPSHUB_PUBLIC_BASE_URL='\$\{OPSHUB_PUBLIC_BASE_URL\}'/,
    'production remote deploy must receive the public base URL before using it under set -u',
  );
  assert.match(
    productionRemoteEnvironment,
    /OPSHUB_COMPOSE_PROJECT='home-server'/,
    'production deploy must use the existing home-server Compose project',
  );
  assert.doesNotMatch(
    productionWorkflow,
    /COMPOSE_PROJECT_NAME='opshub'|--project-name opshub/,
    'production must not create the retired parallel opshub Compose project',
  );
  assert.match(
    productionWorkflow,
    /prepare-rollback-env\.sh"[\s\S]*?"\$REMOTE_RELEASE_DIR\/rollback-authority\/\$rollback_source_commit\/env\.example"[\s\S]*?"\$rollback_source_commit"/,
    'production must prepare the exact previous release rollback env before promotion',
  );
  assert.match(
    productionWorkflow,
    /release-manifest\.json[\s\S]*?\["sourceCommit"\]/,
    'production must bind rollback authority to release-manifest sourceCommit',
  );
  assert.match(
    productionWorkflow,
    /git show "\$\{previous_release_sha\}:deploy\/home-server\/env\.example"/,
    'production must export rollback authority from the exact deployed release SHA',
  );
  assert.match(
    productionWorkflow,
    /rollback-authority\/\$\{previous_release_sha\}\/env\.example/,
    'production must deliver exact-release rollback authority with the candidate',
  );
  assert.doesNotMatch(
    productionWorkflow,
    /prepare-bidv-legacy-rollback\.sh/,
    'production deploy must not call the secret-bearing BIDV break-glass helper',
  );
  const directOriginAcceptanceIndex = productionWorkflow.indexOf(
    'bash deploy/home-server/verify-production-origin.sh',
  );
  const tunnelActivationIndex = productionWorkflow.indexOf(
    'name: Activate production Cloudflare ingress after direct-origin acceptance',
  );
  const publicVerificationIndex = productionWorkflow.indexOf(
    'name: Verify public health and version metadata',
  );
  const tunnelRestoreIndex = productionWorkflow.indexOf(
    'name: Restore production Tunnel after failed public verification',
  );
  assert.ok(
    directOriginAcceptanceIndex >= 0 &&
      directOriginAcceptanceIndex < tunnelActivationIndex &&
      tunnelActivationIndex < publicVerificationIndex &&
      publicVerificationIndex < tunnelRestoreIndex,
    'production must pass direct-origin proof before opening Tunnel ingress and restore Tunnel after public failure',
  );
  assert.match(
    productionWorkflow,
    /steps\.activate_tunnel\.outcome != 'skipped' && steps\.verify_public\.outcome != 'success'/,
    'production Tunnel restore must cover every attempted activation before failed or cancelled public verification',
  );
  const baselineReconcileIndex = productionWorkflow.indexOf(
    'verify_previous_baseline()',
  );
  const candidateEnvMutationIndex = productionWorkflow.indexOf(
    'upsert_env OPSHUB_DOMAIN "phongvu.work"',
  );
  assert.ok(
    baselineReconcileIndex >= 0 &&
      baselineReconcileIndex < candidateEnvMutationIndex,
    'production must reconcile the previous release baseline before candidate env mutation',
  );
  assert.match(productionWorkflow, /Production \/v1\/ws\/v2 without a one-time ticket returned/);
  for (const signalTrap of [
    "trap 'rollback_on_error 130' INT",
    "trap 'rollback_on_error 143' TERM",
    "trap 'rollback_on_error 129' HUP",
    'trap - ERR INT TERM HUP',
  ]) assert.match(productionWorkflow, new RegExp(signalTrap.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(productionWorkflow, /verify-release-manifest\.sh" "\$previous_current"/);
  assert.match(productionWorkflow, /production-runtime-identity\.sh/);
  assert.match(productionWorkflow, /reconcile-production-baseline\.sh/);
  assert.match(productionWorkflow, /verify_public_artifact\(\)/);
  assert.match(productionWorkflow, /verify-static-response/);
  const nestSourceRoot = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'backend-nest', 'nest-cli.json'), 'utf8'),
  ).sourceRoot;
  const helpDeployStateBuildPath = `dist/${nestSourceRoot}/help-content/help-content-deploy-state.js`;
  assert.match(
    productionWorkflow,
    new RegExp(helpDeployStateBuildPath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'production Help ownership probe must use the actual Nest build output path',
  );
  assert.doesNotMatch(
    productionWorkflow,
    /node dist\/help-content\/help-content-deploy-state\.js/,
    'production Help ownership probe must not omit the Nest sourceRoot segment',
  );
  assert.match(productionWorkflow, /help-state-before\.json/);
  assert.match(productionWorkflow, /--force-recreate --wait --wait-timeout 120 api/);
  assert.doesNotMatch(productionWorkflow, /\$CURRENT_DIR\/docs\/help/);
  assert.match(productionWorkflow, /tar -C docs\/help -czf dist\/help-assets\.tar\.gz \./);
  assert.match(stagingWorkflow, /tar -C docs\/help -czf dist\/help-assets\.tar\.gz \./);
  assert.match(homeCompose, /\/downloads\/help:\/app\/docs\/help:ro/);
  assert.doesNotMatch(homeCompose, /\.\.\/\.\.\/docs\/help:\/app\/docs\/help:ro/);
  assert.match(
    productionWorkflow,
    /the directly verified dual-domain candidate foundation and rollback checkpoint were retained/,
    'public failure must retain the accepted dual-domain candidate foundation',
  );
  assert.match(policy, /explicit\s+command in the current task/);
  assert.match(policy, /Never promote an\s+arbitrary task branch or SHA to `main`/);
  assert.match(policy, /Never force-push or delete `staging` or `main`/);
  assert.match(policy, /scripts\/task-lifecycle\.mjs/);
  assert.match(playbook, /gh workflow run promote-production\.yml --ref main/);
});
