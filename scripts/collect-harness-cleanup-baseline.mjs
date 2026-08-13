#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function git(args) {
  return execFileSync("git", args, {
    cwd: root,
    encoding: "utf8",
    windowsHide: true,
  }).trim();
}

function normalize(value) {
  return value.replaceAll("\\", "/");
}

function trackedFiles() {
  return git(["ls-files", "--cached"]).split(/\r?\n/).filter(Boolean);
}

function countLines(relative) {
  const absolute = path.join(root, relative);
  if (!existsSync(absolute)) return null;
  const content = readFileSync(absolute, "utf8");
  return {
    lines: content.length === 0 ? 0 : content.split(/\r?\n/).length,
    bytes: statSync(absolute).size,
  };
}

function activePlans(files) {
  return files
    .filter((file) => file.startsWith("docs/plans/active/") && file.endsWith(".md"))
    .filter((file) => !file.endsWith("/README.md"))
    .map((file) => ({ path: file, ...countLines(file) }))
    .sort((left, right) => left.path.localeCompare(right.path));
}

function worktrees() {
  const lines = git(["worktree", "list", "--porcelain"]).split(/\r?\n/);
  const result = [];
  let current = null;
  for (const line of lines) {
    if (line.startsWith("worktree ")) {
      if (current) result.push(current);
      current = { path: normalize(line.slice("worktree ".length)) };
    } else if (current && line.startsWith("HEAD ")) {
      current.head = line.slice("HEAD ".length);
    } else if (current && line.startsWith("branch ")) {
      current.branch = line.slice("branch ".length).replace("refs/heads/", "");
    } else if (current && line === "detached") {
      current.detached = true;
    }
  }
  if (current) result.push(current);
  return result.map((entry) => ({
    ...entry,
    path:
      entry.path === normalize(root)
        ? "."
        : `<external-worktree:${path.basename(entry.path)}>`,
  }));
}

function harnessSurface(files) {
  const prefixes = [
    "scripts/schema/",
    "scripts/adapter/",
    "tests/adapter/",
    "tests/bootstrap/",
    "tests/coherence/",
    "tests/core/",
    "tests/installer/",
    "tests/maintenance/",
    "tests/protocol/",
    "tests/release/",
    "tests/snapshot/",
    "tests/workflow/",
    "docs/contracts/harness-",
  ];
  return files.filter((file) =>
    prefixes.some((prefix) => file.startsWith(prefix)) ||
    /(^|\/)harness(?:-cli)?(?:-|\.|\/)/i.test(file) ||
    file === "harness.db",
  );
}

function ignoredHarnessSurface() {
  const output = git([
    "ls-files",
    "--others",
    "--ignored",
    "--exclude-standard",
    "--",
    "harness.db",
    "harness.db-wal",
    "harness.db-shm",
    ".harness-core",
    ".harness-backup",
    "scripts/bin/harness",
    "scripts/bin/harness.exe",
    "scripts/bin/harness-cli",
    "scripts/bin/harness-cli.exe",
  ]);
  return output
    .split(/\r?\n/)
    .filter(Boolean)
    .map(normalize)
    .sort();
}

const hotspotPaths = [
  "backend-nest/src/user/user.service.ts",
  "backend-nest/src/sales-reports/sales-reports.service.ts",
  "backend-nest/src/map-vietin/map-vietin.service.ts",
  "backend-nest/src/home-summary/home-summary.service.ts",
  "lib/features/home/presentation/widgets/home_summary_page.dart",
  "lib/features/payment_monitor/presentation/providers/payment_monitor_provider.dart",
];

const files = trackedFiles();
const status = git(["status", "--porcelain=v1"])
  .split(/\r?\n/)
  .filter(Boolean)
  .map((line) => normalize(line));
const rootFromGit = normalize(git(["rev-parse", "--show-toplevel"]));

const output = {
  formatVersion: 1,
  repository: {
    root: ".",
    branch: git(["branch", "--show-current"]),
    head: git(["rev-parse", "HEAD"]),
    originStaging: (() => {
      try {
        return git(["rev-parse", "origin/staging"]);
      } catch {
        return null;
      }
    })(),
    rootFingerprint: rootFromGit === normalize(root) ? "matches-git-root" : "git-root-mismatch",
    status,
    worktrees: worktrees(),
  },
  trackedInventory: {
    fileCount: files.length,
    docsCount: files.filter((file) => file.startsWith("docs/")).length,
    activePlanCount: activePlans(files).length,
    activePlans: activePlans(files),
    harnessSurfaceCount: harnessSurface(files).length,
    harnessSurface: harnessSurface(files),
    ignoredHarnessSurface: ignoredHarnessSurface(),
  },
  legacyDatabase: {
    path: "harness.db",
    readOnlyRequired: true,
    expectedSchemaVersions: Array.from({ length: 12 }, (_, index) => index + 1),
    expectedCounts: {
      intake: 92,
      story: 37,
      decision: 7,
      backlog: 27,
      trace: 36,
    },
    sourceHash: "recorded-by-read-only-archive-command",
  },
  runtimeHotspots: hotspotPaths.map((file) => ({ path: file, ...countLines(file) })),
  repeatedFriction: [
    {
      id: "flutter-benign-plugin-exceptions",
      evidence: "MissingPluginException from path_provider/file_picker in test output",
      owner: "consumer-test-bootstrap",
      plannedIntervention: "shared Flutter test bootstrap with explicit plugin fakes",
    },
    {
      id: "cross-stack-rerun-noise",
      evidence: "full Flutter/backend suites repeatedly rerun after environment failures",
      owner: "repository-verification-runner",
      plannedIntervention: "changed-path profiles, failure classification and fingerprints",
    },
    {
      id: "sales-history-import-churn",
      evidence: "rapid follow-up fixes around CSV chunks, artifacts, schema and employee identity",
      owner: "sales-report-consumer-fixtures",
      plannedIntervention: "stable integration fixture and affected-consumer proof",
    },
    {
      id: "responsive-proof-followups",
      evidence: "repeated responsive/Figma follow-up fixes in OPS-44/OPS-53",
      owner: "docs-and-ui-release-proof",
      plannedIntervention: "canonical plan consolidation and explicit visual proof gates",
    },
  ],
  metrics: {
    medianTimeToActionableFailureSeconds: null,
    sameFingerprintReruns: null,
    benignPluginExceptionCount: null,
    note: "Populate from task logs in the Phase 0 evidence review; null is intentional until observed data is available.",
  },
};

function parseArgs(argv) {
  const args = [...argv];
  const outputIndex = args.indexOf("--output");
  if (outputIndex < 0 || !args[outputIndex + 1] || args.length !== 2) {
    throw new Error("Usage: node scripts/collect-harness-cleanup-baseline.mjs --output <path>");
  }
  return path.resolve(root, args[outputIndex + 1]);
}

const outputPath = parseArgs(process.argv.slice(2));
writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, "utf8");
console.log(`baseline written: ${normalize(path.relative(root, outputPath))}`);
