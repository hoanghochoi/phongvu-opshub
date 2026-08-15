import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..", "..");

// These are live execution entrypoints, rather than historical proof in docs.
// The source command must be wrapped inline: a preflight in a different CI job,
// shell block or manually resumed terminal is not sufficient proof of readiness.
const dependencyConsumers = [
  {
    relativePath: "scripts/validate-contract-appendix.sh",
    pattern:
      /(?:flutter\s+(?:analyze|test|build)|npm\s+(?:test|run|ci|install)|npx\s+.*prisma)/i,
  },
  {
    relativePath: "scripts/validate-ops-11-payment-audio.ps1",
    pattern:
      /(?:flutter\s+(?:analyze|test|build)|npm\s+(?:test|run|ci|install)|npx\s+.*prisma)/i,
  },
  {
    relativePath: ".github/workflows/build-windows-msix.yml",
    pattern: /flutter\s+(?:analyze|test|build)/i,
  },
  {
    relativePath: ".github/workflows/deploy-opshub-staging.yml",
    pattern: /flutter\s+(?:analyze|test|build)/i,
  },
  {
    relativePath: ".github/workflows/deploy-opshub.yml",
    pattern: /flutter\s+(?:analyze|test|build)/i,
  },
];

const structuredAffectedConsumerValidators = [
  "scripts/validate-ops39-affected-consumers.mjs",
  "scripts/validate-ops40-affected-consumers.mjs",
];

const localPrismaMigrationVerifiers = [
  "backend-nest/scripts/recover-failed-prisma-migration.mjs",
  "backend-nest/scripts/verify-home-summary-migration.mjs",
  "backend-nest/scripts/verify-home-summary-deadlock-migration.mjs",
  "backend-nest/scripts/verify-map-vietin-bigquery-migration.mjs",
  "backend-nest/scripts/verify-ops41-postgres-concurrency.mjs",
  "backend-nest/src/home-summary/home-summary-projection.postgres.spec.ts",
];

const localConsumerPattern =
  /(?:flutter\s+(?:analyze|test|build)|npm\s+(?:test|run|ci|install)|npx\s+.*prisma)/i;

function source(relativePath) {
  return readFileSync(path.join(root, relativePath), "utf8");
}

function sourceLine(contents, index) {
  const start = contents.lastIndexOf("\n", index) + 1;
  const end = contents.indexOf("\n", index);
  return contents.slice(start, end < 0 ? contents.length : end);
}

function consumerLines(contents, pattern) {
  return contents.split(/\r?\n/).filter((line) => {
    const trimmed = line.trimStart();
    return (
      pattern.test(trimmed) &&
      (/^(?:flutter|npm|npx)\s/i.test(trimmed) ||
        /(?:--|run:)\s+(?:flutter|npm|npx)\s/i.test(trimmed))
    );
  });
}

export function assertStructuredToolchainBoundary(
  contents,
  relativePath = "<fixture>",
) {
  const lines = contents.split(/\r?\n/);
  const commandLines = lines
    .map((line, index) => ({ line, index }))
    .filter(({ line }) =>
      /\bcommand:\s*(?:npm(?:\.cmd)?|flutter(?:\.bat)?)/i.test(line),
    );
  assert.ok(
    commandLines.length > 0,
    `${relativePath} must declare at least one dependency-owning suite command`,
  );
  for (const { index, line } of commandLines) {
    const nearby = lines.slice(index, index + 4).join("\n");
    assert.match(
      nearby,
      /toolchainProfile:\s*['"](?:flutter|nestjs)['"]/i,
      `${relativePath} has a dependency suite without an explicit toolchain profile: ${line.trim()}`,
    );
  }
  assert.match(
    contents,
    /runAffectedConsumerSuite\(/,
    `${relativePath} must dispatch suites through the shared affected-consumer boundary`,
  );
  assert.doesNotMatch(
    contents,
    /prepareTaskToolchain\(/,
    `${relativePath} must not hand off from a detached one-time preflight`,
  );
}

export function assertInlineToolchainBoundary(
  contents,
  relativePath = "<fixture>",
  pattern = localConsumerPattern,
) {
  const lines = consumerLines(contents, pattern);
  assert.ok(
    lines.length > 0,
    `${relativePath} must contain a dependency consumer`,
  );
  for (const line of lines) {
    const failure = `${relativePath} runs a dependency consumer outside its own toolchain command block: ${line.trim()}`;
    assert.match(line, /run-with-toolchain\.mjs\b/i, failure);
    assert.match(line, /--profile\s+(?:flutter|nestjs)\b/i, failure);
    assert.match(line, /\s--\s+(?:flutter|npm|npx)\b/i, failure);
  }
}

test("dependency-consuming scripts and release workflows use an inline shared boundary", () => {
  for (const { relativePath, pattern } of dependencyConsumers) {
    assertInlineToolchainBoundary(source(relativePath), relativePath, pattern);
  }
});

test("affected-consumer validators keep nested Flutter/Nest suites behind the shared boundary", () => {
  for (const relativePath of structuredAffectedConsumerValidators) {
    assertStructuredToolchainBoundary(source(relativePath), relativePath);
  }
});

test("local Prisma migration verifiers enter through the shared toolchain helper", () => {
  for (const relativePath of localPrismaMigrationVerifiers) {
    const contents = source(relativePath);
    const boundaryPattern = relativePath.endsWith(
      "recover-failed-prisma-migration.mjs",
    )
      ? /run-with-toolchain\.mjs/
      : /run-prisma-migrate-deploy\.mjs/;
    assert.match(
      contents,
      boundaryPattern,
      `${relativePath} must invoke the shared Nest toolchain boundary`,
    );
    if (relativePath.endsWith("recover-failed-prisma-migration.mjs")) {
      assert.match(contents, /existsSync\(toolchainRunner\)/);
      assert.match(contents, /process\.platform === ['"]win32['"]/);
    }
    assert.doesNotMatch(
      contents,
      /spawnSync\(\s*['"]npx['"]\s*,\s*\[['"]prisma['"]?/,
      `${relativePath} must not spawn a raw Prisma command`,
    );
  }
});

test("a structured suite without an explicit profile is rejected", () => {
  assert.throws(
    () =>
      assertStructuredToolchainBoundary(
        `const suites = [{ command: flutter, args: ['test'] }];\nspawnSync(suite.command, suite.args);`,
        "raw-nested-suite.mjs",
      ),
    /without an explicit toolchain profile/,
  );
});

test("a preflight in an earlier CI job or shell block cannot authorize a raw consumer", () => {
  assert.throws(
    () =>
      assertInlineToolchainBoundary(
        `
jobs:
  prepare:
    steps:
      - run: node scripts/prepare-task-toolchain.mjs --profile flutter
  build:
    steps:
      - run: flutter build web --no-pub
`,
        "separate-workflow-job.yml",
      ),
    /outside its own toolchain command block/,
  );
});

test("standalone Flutter validation forbids an implicit second pub writer", () => {
  const contents = source("scripts/validate-contract-appendix.sh");
  assert.match(
    contents,
    /node scripts\/run-with-toolchain\.mjs --profile flutter -- flutter test --no-pub/,
  );
  assert.doesNotMatch(contents, /\nflutter test \\\n/);
});

test("Nest package lifecycle commands keep the gate before build/test/start consumers", () => {
  const packageJson = JSON.parse(source("backend-nest/package.json"));
  const scripts = packageJson.scripts;
  for (const command of [
    "build",
    "format",
    "lint",
    "start",
    "start:dev",
    "start:debug",
    "start:prod",
    "test",
    "test:watch",
    "test:cov",
    "test:debug",
    "test:e2e",
  ]) {
    assert.match(
      scripts[`pre${command}`],
      /run-with-toolchain\.mjs --root \.\. --profile nestjs --preflight-only/,
      `pre${command} must use the shared gate`,
    );
    assert.match(
      scripts[command],
      /run:nest-command/,
      `${command} must execute inside the retained Nest lease`,
    );
  }
});

test("Docker Nest build is self-contained without weakening local lifecycle gates", () => {
  const packageJson = JSON.parse(source("backend-nest/package.json"));
  const dockerfile = source("backend-nest/Dockerfile");

  assert.match(
    packageJson.scripts.prebuild,
    /run-with-toolchain\.mjs --root \.\. --profile nestjs --preflight-only/,
    "local npm run build must keep the shared Nest toolchain gate",
  );
  assert.match(
    packageJson.scripts["preverify:security-deps"],
    /run-with-toolchain\.mjs --root \.\. --profile nestjs --preflight-only/,
    "local npm run verify:security-deps must keep the shared Nest toolchain gate",
  );
  assert.match(
    packageJson.scripts["verify:security-deps"],
    /run:nest-command/,
    "local security verification must retain the Nest lease through execution",
  );
  assert.match(
    dockerfile,
    /npm run verify:security-deps --ignore-scripts && npx --no-install prisma generate && npm run build --ignore-scripts/,
    "the backend-only Docker context must execute Nest build without the local prebuild hook",
  );
  assert.match(
    dockerfile,
    /CMD \["npx", "--no-install", "prisma", "migrate", "deploy"\]/,
    "the API image must not let npx download Prisma at runtime",
  );
});

test("local OPS-40 PostgreSQL verifier keeps Prisma behind the Nest boundary", () => {
  const verifier = source("backend-nest/scripts/verify-ops40-postgres.ps1");
  assert.match(
    verifier,
    /run-with-toolchain\.mjs[\s\S]*--profile nestjs[\s\S]*--cwd backend-nest[\s\S]*--\s+npx --no-install prisma migrate deploy/,
    "the local PostgreSQL verifier must hydrate Nest before Prisma migration",
  );
  assert.doesNotMatch(
    verifier,
    /&\s+npx\.cmd\s+prisma migrate deploy/,
    "the verifier must not spawn a raw local npx Prisma command",
  );
  assert.match(
    verifier,
    /\$\{database\}\?schema=public/,
    "the verifier must preserve the disposable database name in the URL",
  );
  assert.match(
    verifier,
    /is_nullable::text/,
    "the verifier must cast PostgreSQL character metadata before concatenation",
  );

  const runbook = source("docs/runbooks/support-chat-operations.md");
  assert.match(
    runbook,
    /node scripts\/run-with-toolchain\.mjs --profile nestjs --cwd backend-nest -- npm run verify:ops40:postgres/,
    "the runbook must use the repository-root toolchain-gated command",
  );
  assert.doesNotMatch(
    runbook,
    /`npm run verify:ops40:postgres`/,
    "the runbook must not advertise the raw local npm command",
  );
});

test("Nest command helper supports the repository and Docker-contained boundaries", () => {
  const helper = source("backend-nest/scripts/run-nest-command.mjs");
  assert.match(helper, /existsSync\(toolchainRunner\)/);
  assert.match(helper, /localExecutable\(command\[0\]\)/);
  assert.match(helper, /stdio:\s*['"]inherit['"]/);
});

test("Docker and remote migration boundaries forbid implicit npx downloads", () => {
  const compose = source("deploy/home-server/docker-compose.home.yml");
  const stagingWorkflow = source(".github/workflows/deploy-opshub-staging.yml");
  assert.match(compose, /\["npx", "--no-install", "prisma", "migrate", "deploy"\]/);
  assert.match(
    stagingWorkflow,
    /npx --no-install prisma migrate resolve --rolled-back/,
  );
});

test("release Flutter builds use the inline boundary and disable the implicit Pub writer", () => {
  for (const relativePath of [
    ".github/workflows/build-windows-msix.yml",
    ".github/workflows/deploy-opshub-staging.yml",
    ".github/workflows/deploy-opshub.yml",
  ]) {
    const contents = source(relativePath);
    for (const match of contents.matchAll(/flutter build [^\r\n]+/g)) {
      const line = sourceLine(contents, match.index);
      assert.match(
        line,
        /run-with-toolchain\.mjs --profile flutter -- flutter build/,
      );
      assert.match(
        match[0],
        /--no-pub/,
        `${relativePath} has an implicit Flutter Pub writer`,
      );
    }
  }
});

test("Windows MSIX helpers use the inline Flutter boundary", () => {
  for (const relativePath of [
    "scripts/build-windows-msix-internal.ps1",
    "scripts/build-windows-msix-store.ps1",
  ]) {
    const contents = source(relativePath);
    assert.match(
      contents,
      /run-with-toolchain\.mjs[\s\S]*--profile flutter[\s\S]*--\s+dart\.exe\s+@msixArgs/,
      `${relativePath} must hydrate Flutter before msix:create`,
    );
    assert.doesNotMatch(
      contents,
      /&\s+dart\s+@msixArgs/,
      `${relativePath} must not invoke raw dart @msixArgs`,
    );
  }
});

test("existing worktree repair command remains documented", () => {
  const contents = source("scripts/README.md");
  assert.match(
    contents,
    /prepare-task-toolchain\.mjs --root .* --profile all --force/,
  );
  assert.match(contents, /repair\/doctor command/);
});
