import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { prepareTaskToolchain } from "./prepare-task-toolchain.mjs";

const root = process.cwd();
const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const flutter = process.platform === "win32" ? "flutter.bat" : "flutter";

export const pathContracts = [
  /^backend-nest\/prisma\//,
  /^backend-nest\/src\/support-chat\//,
  /^backend-nest\/src\/auth\//,
  /^backend-nest\/src\/notification-feed\//,
  /^backend-nest\/src\/upload\//,
  /^backend-nest\/src\/common\//,
  /^backend-nest\/src\/app\.module\.ts$/,
  /^backend-nest\/src\/config\/env\.ts$/,
  /^backend-nest\/(?:\.env\.example|package\.json)$/,
  /^backend-nest\/scripts\/verify-ops40-/,
  /^backend-go\//,
  /^lib\/app\//,
  /^lib\/features\/support_chat\//,
  /^lib\/features\/auth\//,
  /^lib\/features\/admin\//,
  /^lib\/features\/notifications\//,
  /^test\/(?:support_chat|auth_|app_router|app_shell|app_notifications|app_toast|design_system|private_media|quick_actions|realtime|warranty|feedback|home_avatar)/,
  /^deploy\/(?:staging|home-server)\//,
  /^docs\/(?:product|stories|plans|runbooks)\//,
  /^docs\/TEST_MATRIX\.md$/,
  /^scripts\/opshub-web-visual-smoke\.mjs$/,
  /^scripts\/validate-ops40-affected-consumers\.mjs$/,
  /^scripts\/validate-ops40-affected-consumers\.test\.mjs$/,
];

function run(command, args, cwd = root, capture = false) {
  const needsShell =
    process.platform === "win32" && /\.(?:cmd|bat)$/i.test(command);
  const result = spawnSync(command, args, {
    cwd,
    encoding: capture ? "utf8" : undefined,
    stdio: capture ? "pipe" : "inherit",
    windowsHide: true,
    shell: needsShell,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (capture) process.stderr.write(result.stderr || result.stdout || "");
    throw new Error(
      `${command} ${args.join(" ")} failed with ${result.status}`,
    );
  }
  return capture ? String(result.stdout || "") : "";
}

export function parseArgs(argv) {
  if (argv.length === 0) return { base: null };
  if (argv.length !== 2 || argv[0] !== "--base") {
    throw new Error(
      "Usage: node scripts/validate-ops40-affected-consumers.mjs [--base <ref>]",
    );
  }
  const base = argv[1]?.trim();
  if (!base || base.length > 1024 || /[\0\r\n]/.test(base)) {
    throw new Error("OPS-40 affected-consumer base ref is invalid");
  }
  return { base };
}

function normalizedPaths(output) {
  return output
    .split(/\r?\n/)
    .map((value) => value.trim().replaceAll("\\", "/"))
    .filter(Boolean);
}

export function resolveBaseCommit(base, cwd = root) {
  const revision = run(
    "git",
    ["rev-parse", "--verify", "--end-of-options", `${base}^{commit}`],
    cwd,
    true,
  ).trim();
  if (!/^[0-9a-f]{40}$/i.test(revision)) {
    throw new Error(
      `OPS-40 affected-consumer base did not resolve to a commit: ${base}`,
    );
  }
  const mergeBase = run(
    "git",
    ["merge-base", revision, "HEAD"],
    cwd,
    true,
  ).trim();
  if (!/^[0-9a-f]{40}$/i.test(mergeBase)) {
    throw new Error(
      `OPS-40 affected-consumer base has no merge base with HEAD: ${base}`,
    );
  }
  return revision;
}

export function collectChangedPaths({ cwd = root, base = null } = {}) {
  const outputs = [];
  if (base !== null) {
    const revision = resolveBaseCommit(base, cwd);
    outputs.push(
      run(
        "git",
        ["diff", "--no-renames", "--name-only", `${revision}...HEAD`, "--"],
        cwd,
        true,
      ),
    );
  }
  outputs.push(
    run("git", ["diff", "--no-renames", "--name-only", "--"], cwd, true),
    run(
      "git",
      ["diff", "--cached", "--no-renames", "--name-only", "--"],
      cwd,
      true,
    ),
    run("git", ["ls-files", "--others", "--exclude-standard"], cwd, true),
  );
  return [...new Set(outputs.flatMap(normalizedPaths))].sort();
}

export function assertPathContracts(changedPaths) {
  const unmatched = changedPaths.filter(
    (value) => !pathContracts.some((contract) => contract.test(value)),
  );
  if (unmatched.length > 0) {
    throw new Error(`OPS-40 path contract missing:\n${unmatched.join("\n")}`);
  }
}

export function ensureToolchain(rootPath = root) {
  const result = prepareTaskToolchain({ root: rootPath, profile: "all" });
  if (result.exitCode !== 0) {
    throw new Error(
      `OPS-40 toolchain preflight failed with exit ${result.exitCode}`,
    );
  }
  return result;
}

const suites = [
  {
    name: "Nest Support Chat plus auth/feed/media/throttler/user consumers",
    cwd: path.join(root, "backend-nest"),
    command: npm,
    args: [
      "test",
      "--",
      "--runInBand",
      "src/support-chat/support-chat.service.spec.ts",
      "src/support-chat/support-chat-outbox.worker.spec.ts",
      "src/support-chat/support-chat-retention.worker.spec.ts",
      "src/support-chat/support-chat-upload.guard.spec.ts",
      "src/auth/auth-bootstrap.service.spec.ts",
      "src/auth/auth-session.service.spec.ts",
      "src/auth/access-change.service.spec.ts",
      "src/auth/realtime-ticket.service.spec.ts",
      "src/notification-feed/notification-feed.controller.spec.ts",
      "src/notification-feed/notification-feed.service.spec.ts",
      "src/upload/private-media.service.spec.ts",
      "src/common/user-aware-throttler.guard.spec.ts",
      "src/common/realtime-event.spec.ts",
      "src/user/user.service.spec.ts",
    ],
  },
  {
    name: "OPS-40 migration and nullable-retention contract",
    cwd: path.join(root, "backend-nest"),
    command: npm,
    args: ["run", "verify:ops40:migration"],
  },
  {
    name: "Go all realtime v2 and legacy websocket consumers",
    cwd: path.join(root, "backend-go"),
    command: "go",
    args: ["test", "./..."],
  },
  {
    name: "Flutter Support Chat plus protected shell/auth/feed/media consumers",
    cwd: root,
    command: flutter,
    args: [
      "test",
      "--no-pub",
      "--concurrency=1",
      "test/support_chat_wire_contract_test.dart",
      "test/support_chat_provider_test.dart",
      "test/support_chat_surface_test.dart",
      "test/auth_provider_session_test.dart",
      "test/auth_pre_shell_redesign_test.dart",
      "test/app_router_test.dart",
      "test/app_notifications_feed_repository_test.dart",
      "test/app_notifications_provider_test.dart",
      "test/private_media_headers_test.dart",
      "test/private_media_dual_read_contract_test.dart",
      "test/quick_actions_launcher_test.dart",
      "test/app_shell_route_viewport_test.dart",
      "test/realtime_connection_manager_test.dart",
      "test/warranty_upload_contract_test.dart",
      "test/feedback_upload_contract_test.dart",
      "test/auth_avatar_upload_test.dart",
    ],
  },
  {
    name: "Final tracked patch whitespace",
    cwd: root,
    command: "git",
    args: ["diff", "--check"],
  },
];

export function main(argv = process.argv.slice(2)) {
  const { base } = parseArgs(argv);
  const changedPaths = collectChangedPaths({ base });
  assertPathContracts(changedPaths);
  console.log(
    `[OPS-40] Path contracts PASS mode=${base === null ? "working-tree" : "base-aware"} base=${base ?? "none"} changedPaths=${changedPaths.length}`,
  );

  for (const relative of [
    "backend-nest/.env.example",
    "deploy/staging/env.example",
    "deploy/home-server/env.example",
  ]) {
    const content = readFileSync(path.join(root, relative), "utf8");
    if (!/^SUPPORT_CHAT_ENABLED=false$/m.test(content)) {
      throw new Error(`${relative} must keep SUPPORT_CHAT_ENABLED=false`);
    }
  }

  console.log("\n[OPS-40] Preparing all runtime toolchains");
  ensureToolchain();

  for (const suite of suites) {
    console.log(`\n[OPS-40] ${suite.name}`);
    run(suite.command, suite.args, suite.cwd);
  }

  console.log("\nOPS-40 AFFECTED CONSUMERS PASS");
}

const invokedPath = process.argv[1]
  ? pathToFileURL(path.resolve(process.argv[1])).href
  : null;
if (invokedPath === import.meta.url) {
  main();
}
