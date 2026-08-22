import path from "node:path";

/**
 * Repository verification profiles.
 *
 * Keep commands structured so the runner can report exactly what it executed
 * and can fingerprint the command contract before and after the proof.
 */
export const PROFILES = Object.freeze([
  {
    id: "harness",
    pathPatterns: [
      /^AGENTS\.md$/,
      /^\.agents\//,
      /^\.harness\//,
      /^\.gitignore$/,
      /^\.vscode\//,
      /^docs\/(?:WORKFLOW|README|FEATURE_INTAKE|TEST_MATRIX)\.md$/,
      /^scripts\/README\.md$/,
      /^docs\/(?:contracts|decisions|migrations|plans|templates)\//,
      /^deploy\/home-server\/README\.md$/,
      /^scripts\/(?:adapter|schema)\//,
      /^scripts\/(?:validate-contract-appendix|validate-ops-11-payment-audio|validate-ops(?:39|40)-affected-consumers|run-affected-consumer-suite|opshub-web-smoke-proxy)\.(?:mjs|ps1|sh)$/,
      /^scripts\/(?:prepare-task-toolchain|run-toolchain-command|run-with-toolchain|task-lifecycle|toolchain-doctor|verify-cold-dependency-canary|verify-toolchain-boundary)\.mjs$/,
      /^backend-nest\/scripts\/run-prisma-migrate-deploy\.mjs$/,
      /^\.gitattributes$/,
      /^scripts\/bootstrap-harness\.(?:ps1|sh)$/,
      /^scripts\/bin\/harness(?:-cli)?\.exe\.sha256$/,
      /^scripts\/verify-ops193-upstream-release\.mjs$/,
      /^scripts\/verify-ops198-residual-gates\.mjs$/,
      /^scripts\/verify-ops75-final-release-proof\.mjs$/,
      /^scripts\/verify-ops204-preflight\.mjs$/,
      /^scripts\/verify-ops205-reconciliation\.mjs$/,
      /^scripts\/verify-ops207-reconciliation\.mjs$/,
      /^tests\/(?:README\.md|(?:bootstrap|fixtures|workflow)\/)/,
      /^scripts\/(?:agent-harness-block|archive-harness|build-harness|collect-(?:harness|artifact-inventory|ops72-shadow-metrics|ops72-failure-injection|ops72-live-shadow-evidence)|harness(?:-|$)|install-harness|materialize-core-state|promote-harness|review-harness-disposition|task-lifecycle|test-task-lifecycle|verify-(?:artifact-inventory|core|harness|materialized|migration-eol|ops72-final-decision|ops72-live-shadow-evidence|ops72-shadow|ops72-failure-injection|plan-disposition|retained-owner-review|revision|task-shadow)|validate-changeset-rebuild)/,
      /^tests\/(?:adapter|boundary|changesets|ci|coherence|core|protocol|snapshot|worktrees)\//,
      /^tests\/docs\/test-doc-contracts\.sh$/,
      /^tests\/migration\//,
      /^tests\/toolchain\//,
      /^tests\/(?:installer|maintenance|migration|verification)\//,
      /^\.github\/workflows\/(?:cold-dependency-canary|deploy-opshub(?:-staging)?|post-merge-maintenance|release-guard-pr)\.yml$/,
    ],
    consumers: [
      "repository-harness-adoption",
      "task-lifecycle-and-affected-consumer-proof",
    ],
    prerequisites: ["git repository", "Node.js"],
    commands: [
      {
        id: "git-diff-check",
        cwd: ".",
        executable: "git",
        argv: ["diff", "--check"],
      },
      {
        id: "toolchain-tests",
        cwd: ".",
        executable: process.execPath,
        argv: ["--test", "tests/toolchain/*.test.mjs"],
      },
      {
        id: "migration-eol-preflight",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-migration-eol.mjs"],
      },
      {
        id: "toolchain-boundary-scan",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-toolchain-boundary.mjs"],
      },
      {
        id: "toolchain-command-tee-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/run-toolchain-command.mjs"],
      },
      {
        id: "retained-owner-review",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "scripts/verify-retained-owner-review.mjs",
          "--input",
          "docs/migrations/ops-73-retained-owner-review.json",
        ],
      },
      {
        id: "upstream-updater-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-harness-updater-blocked.mjs"],
      },
      {
        id: "upstream-updater-contract-tests",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "--test",
          "tests/migration/verify-harness-updater-blocked.test.mjs",
        ],
      },
      {
        id: "ops193-upstream-release-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops193-upstream-release.mjs"],
      },
      {
        id: "ops193-upstream-release-contract-tests",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "--test",
          "tests/migration/verify-ops193-upstream-release.test.mjs",
        ],
      },
      {
        id: "ops204-migration-home-preflight-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops204-preflight.mjs"],
      },
      {
        id: "ops204-migration-home-preflight-contract-tests",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "--test",
          "tests/migration/verify-ops204-preflight.test.mjs",
        ],
      },
      {
        id: "ops205-master-plan-reconciliation",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops205-reconciliation.mjs"],
      },
      {
        id: "ops205-master-plan-reconciliation-tests",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "--test",
          "tests/migration/verify-ops205-reconciliation.test.mjs",
        ],
      },
      {
        id: "ops207-master-plan-reconciliation",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops207-reconciliation.mjs"],
      },
      {
        id: "ops207-master-plan-reconciliation-tests",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "--test",
          "tests/migration/verify-ops207-reconciliation.test.mjs",
        ],
      },
      {
        id: "ops72-final-decision-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops72-final-decision.mjs"],
      },
      {
        id: "ops198-residual-gates-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops198-residual-gates.mjs"],
      },
      {
        id: "ops75-final-release-proof-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops75-final-release-proof.mjs"],
      },
    ],
  },
  {
    id: "docs",
    pathPatterns: [
      /^README(?:-backend)?\.md$/,
      /^docs\//,
      /^app-.*\.md$/,
      /^ui-ux\.md$/,
    ],
    consumers: ["repository documentation", "product and release authority"],
    prerequisites: ["Git", "Node.js"],
    commands: [
      {
        id: "docs-diff-check",
        cwd: ".",
        executable: "git",
        argv: ["diff", "--check"],
      },
    ],
  },
  {
    id: "verification-runner",
    pathPatterns: [
      /^scripts\/verify-task(?:-(?:canary|shadow))?\.mjs$/,
      /^scripts\/verify-ops191-phase9-closure\.mjs$/,
      /^scripts\/verify-ops72-(?:execution-canary-progress|final-decision)\.mjs$/,
      /^scripts\/verification-profiles\.mjs$/,
      /^tests\/verification\//,
    ],
    consumers: [
      "generic-verification-runner",
      "affected-consumer-orchestrator",
    ],
    prerequisites: ["Node.js", "Git"],
    commands: [
      {
        id: "runner-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/verify-task.mjs"],
      },
      {
        id: "ops126-collector-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/collect-ops72-failure-injection.mjs"],
      },
      {
        id: "ops126-validator-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/verify-ops72-failure-injection.mjs"],
      },
      {
        id: "ops72-live-evidence-collector-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/collect-ops72-live-shadow-evidence.mjs"],
      },
      {
        id: "shadow-runner-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/verify-task-shadow.mjs"],
      },
      {
        id: "ops72-execution-canary-progress-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/verify-ops72-execution-canary-progress.mjs"],
      },
      {
        id: "ops72-final-decision-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/verify-ops72-final-decision.mjs"],
      },
      {
        id: "ops191-phase9-closure-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-ops191-phase9-closure.mjs"],
      },
      {
        id: "ops191-phase9-closure-syntax",
        cwd: ".",
        executable: process.execPath,
        argv: ["--check", "scripts/verify-ops191-phase9-closure.mjs"],
      },
      {
        id: "ops191-phase9-closure-tests",
        cwd: ".",
        executable: process.execPath,
        argv: ["--test", "tests/verification/verify-ops191-phase9-closure.test.mjs"],
      },
      {
        id: "ops72-final-decision-tests",
        cwd: ".",
        executable: process.execPath,
        argv: ["--test", "tests/verification/verify-ops72-final-decision.test.mjs"],
      },
    ],
  },
  {
    id: "release",
    pathPatterns: [
      /^\.github\/workflows\//,
      /^\.github\/actions\/setup-flutter\//,
      /^docs\/runbooks\/git-release-playbook\.md$/,
      /^scripts\/build-windows-msix-(?:internal|store)\.ps1$/,
      /^scripts\/(?:task-lifecycle|test-git-release-workflow|validate-premerge|validate-release|release-guard)/,
      /^tests\/release\//,
    ],
    consumers: [
      "task lifecycle",
      "staging release gates",
      "production promotion guards",
    ],
    prerequisites: ["Git", "Node.js"],
    commands: [
      {
        id: "release-diff-check",
        cwd: ".",
        executable: "git",
        argv: ["diff", "--check"],
      },
      {
        id: "task-lifecycle-tests",
        cwd: ".",
        executable: process.execPath,
        argv: ["--test", "scripts/test-task-lifecycle.mjs"],
      },
    ],
  },
  {
    id: "flutter",
    pathPatterns: [
      /^lib\//,
      /^test\//,
      /^\.github\/actions\/setup-flutter\//,
      /^pubspec(?:\.yaml|\.lock)$/,
      /^(?:android|ios|linux|macos|web|windows)\//,
    ],
    consumers: ["Flutter app", "Flutter widget/unit/integration tests"],
    prerequisites: ["Flutter SDK", "pub dependencies"],
    commands: [
      {
        id: "flutter-analyze",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "scripts/run-with-toolchain.mjs",
          "--profile",
          "flutter",
          "--",
          "flutter",
          "analyze",
        ],
      },
    ],
  },
  {
    id: "nestjs",
    pathPatterns: [/^backend-nest\//],
    consumers: ["NestJS API", "Flutter API repositories"],
    prerequisites: ["Node.js", "backend-nest dependencies"],
    commands: [
      {
        id: "nestjs-build",
        cwd: ".",
        executable: process.execPath,
        argv: [
          "scripts/run-with-toolchain.mjs",
          "--profile",
          "nestjs",
          "--cwd",
          "backend-nest",
          "--",
          "npm",
          "run",
          "build",
        ],
      },
    ],
  },
  {
    id: "go-realtime",
    pathPatterns: [/^backend-go\//],
    consumers: ["Go realtime service", "Flutter realtime clients"],
    prerequisites: ["Go toolchain"],
    commands: [
      {
        id: "go-test",
        cwd: "backend-go",
        executable: "go",
        argv: ["test", "./..."],
      },
    ],
  },
  {
    id: "deployment",
    pathPatterns: [
      /^deploy\//,
      /^docker-compose\.yml$/,
      /^tests\/release\/test-cloudflare-public-probe\.sh$/,
      /^tests\/release\/test-caddy-host-isolation\.mjs$/,
      /^scripts\/(?:build-runtime-release|validate-ops39-(?:backup-boundary|caddy|local-boundary)|verify-(?:help-content-sentinel|platform-security))\.mjs$/,
      /^scripts\/generate-bidv-h2h-playbook-pdf\.py$/,
      /^scripts\/load\/opshub-staging-(?:home-100qps|rate-limit-semantics|targets(?:\.test)?)\.(?:js|mjs)$/,
      /^scripts\/(?:opshub-web-visual-smoke|test-cloudflare-api-tunnel-installer)\.mjs$/,
    ],
    consumers: ["deployment manifests", "runtime configuration"],
    prerequisites: ["deployment tooling"],
    commands: [
      {
        id: "deployment-whitespace",
        cwd: ".",
        executable: "git",
        argv: ["diff", "--check"],
      },
      {
        id: "ops39-caddy-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/validate-ops39-caddy.mjs"],
      },
      {
        id: "caddy-host-isolation-runtime-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["tests/release/test-caddy-host-isolation.mjs"],
      },
      {
        id: "platform-security-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["scripts/verify-platform-security.mjs"],
      },
      {
        id: "cloudflare-public-probe-contract",
        cwd: ".",
        executable: "bash",
        argv: ["tests/release/test-cloudflare-public-probe.sh"],
      },
      {
        id: "production-cutover-transaction-contract",
        cwd: ".",
        executable: "bash",
        argv: ["tests/release/test-production-cutover-transaction.sh"],
      },
      {
        id: "help-content-behavior-sentinel",
        cwd: ".",
        executable: process.execPath,
        argv: ["tests/release/test-help-content-sentinel.mjs"],
      },
      {
        id: "static-transaction-rehearsal",
        cwd: ".",
        executable: "bash",
        argv: ["tests/release/test-static-transaction-rehearsal.sh"],
      },
      {
        id: "blue-green-topology-contract-tests",
        cwd: ".",
        executable: process.execPath,
        argv: ["--test", "deploy/staging/blue-green-topology.test.mjs"],
      },
      {
        id: "ops206-candidate-health-parity-contract",
        cwd: ".",
        executable: process.execPath,
        argv: ["deploy/staging/candidate-health-parity.mjs"],
      },
      {
        id: "ops206-candidate-health-parity-tests",
        cwd: ".",
        executable: process.execPath,
        argv: ["--test", "deploy/staging/candidate-health-parity.test.mjs"],
      },
    ],
  },
]);

export const FULL_PROFILE_ID = "full";

export function profileById(id) {
  return PROFILES.find((profile) => profile.id === id) ?? null;
}

export function matchProfiles(changedPaths, requested = []) {
  const auto = PROFILES.filter((profile) =>
    changedPaths.some((changedPath) =>
      profile.pathPatterns.some((pattern) => pattern.test(changedPath)),
    ),
  );
  const explicit = requested.map((id) => {
    const profile = profileById(id);
    if (!profile) throw new Error(`Unknown verification profile: ${id}`);
    return profile;
  });
  const selected = new Map(auto.map((profile) => [profile.id, profile]));
  for (const profile of explicit) selected.set(profile.id, profile);
  return [...selected.values()];
}

export function allProfiles() {
  return [...PROFILES];
}

export function resolveCommandCwd(root, command) {
  return path.resolve(root, command.cwd || ".");
}
