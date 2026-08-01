import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  appendFileSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  collectChangedPaths,
  parseArgs,
} from "./validate-ops40-affected-consumers.mjs";

function git(cwd, args) {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    windowsHide: true,
  }).trim();
}

function write(root, relative, content) {
  const target = path.join(root, relative);
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, content, "utf8");
}

function removeVerifiedTempRepo(root) {
  const resolvedTemp = realpathSync(os.tmpdir());
  const resolvedRoot = realpathSync(root);
  const expectedPrefix = path.join(resolvedTemp, "ops40-affected-consumers-");
  const comparableRoot = resolvedRoot.toLowerCase();
  const comparablePrefix = expectedPrefix.toLowerCase();
  if (!comparableRoot.startsWith(comparablePrefix)) {
    throw new Error(
      `Refusing to remove unexpected test directory: ${resolvedRoot}`,
    );
  }
  rmSync(resolvedRoot, { recursive: true, force: true });
}

function createRepository(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), "ops40-affected-consumers-"));
  t.after(() => removeVerifiedTempRepo(root));
  git(root, ["init", "--quiet"]);
  git(root, ["config", "user.name", "OPS-40 Test"]);
  git(root, ["config", "user.email", "ops40-test@example.invalid"]);
  return root;
}

test("base-aware discovery preserves committed renames and deduplicates current paths", (t) => {
  const root = createRepository(t);
  write(root, "backend-go/old.go", "package main\n");
  write(
    root,
    "backend-nest/src/auth/auth-context.service.ts",
    "export const baseline = true;\n",
  );
  git(root, ["add", "--all"]);
  git(root, ["commit", "--quiet", "-m", "baseline"]);
  const base = git(root, ["rev-parse", "HEAD"]);

  renameSync(
    path.join(root, "backend-go/old.go"),
    path.join(root, "backend-go/new.go"),
  );
  appendFileSync(path.join(root, "backend-go/new.go"), "// committed\n");
  write(root, "lib/app/app.dart", "const committed = true;\n");
  git(root, ["add", "--all"]);
  git(root, ["commit", "--quiet", "-m", "committed diff"]);

  appendFileSync(path.join(root, "backend-go/new.go"), "// dirty\n");
  appendFileSync(
    path.join(root, "backend-nest/src/auth/auth-context.service.ts"),
    "export const dirty = true;\n",
  );
  write(root, "test/support_chat_provider_test.dart", "void main() {}\n");

  const paths = collectChangedPaths({ cwd: root, base });
  assert.deepEqual(paths, [
    "backend-go/new.go",
    "backend-go/old.go",
    "backend-nest/src/auth/auth-context.service.ts",
    "lib/app/app.dart",
    "test/support_chat_provider_test.dart",
  ]);
  assert.equal(new Set(paths).size, paths.length);

  assert.deepEqual(collectChangedPaths({ cwd: root }), [
    "backend-go/new.go",
    "backend-nest/src/auth/auth-context.service.ts",
    "test/support_chat_provider_test.dart",
  ]);
  assert.throws(
    () => collectChangedPaths({ cwd: root, base: "refs/heads/missing" }),
    /failed with 128/,
  );
});

test("CLI parsing fails closed for missing, duplicate, or unknown base arguments", () => {
  assert.deepEqual(parseArgs([]), { base: null });
  assert.deepEqual(parseArgs(["--base", "origin/staging"]), {
    base: "origin/staging",
  });
  assert.throws(() => parseArgs(["--base"]), /Usage:/);
  assert.throws(
    () => parseArgs(["--base", "HEAD", "--base", "HEAD~1"]),
    /Usage:/,
  );
  assert.throws(() => parseArgs(["--unknown", "HEAD"]), /Usage:/);
});
