import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { runAffectedConsumerSuite } from "../../scripts/run-affected-consumer-suite.mjs";

const root = path.resolve(import.meta.dirname, "..", "..");

test("dependency-owning suite uses the selected toolchain profile and structured argv", () => {
  const calls = [];
  let rawCalls = 0;
  const result = runAffectedConsumerSuite(
    {
      name: "Flutter cold suite",
      cwd: root,
      command: "flutter.bat",
      args: ["test", "--no-pub", "--concurrency=1"],
      toolchainProfile: "flutter",
    },
    {
      root,
      log: () => {},
      runWithToolchainFn: (options) => {
        calls.push(options);
        return { exitCode: 0, result: { status: "passed" } };
      },
      rawRunFn: () => {
        rawCalls += 1;
        return 0;
      },
    },
  );

  assert.equal(result.kind, "toolchain");
  assert.equal(rawCalls, 0);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].profile, "flutter");
  assert.equal(calls[0].cwd, ".");
  assert.deepEqual(calls[0].command, [
    "flutter.bat",
    "test",
    "--no-pub",
    "--concurrency=1",
  ]);
});

test("Nest dependency failure blocks the suite and preserves environment exit code", () => {
  const previousExitCode = process.exitCode;
  process.exitCode = undefined;
  try {
    assert.throws(
      () =>
        runAffectedConsumerSuite(
          {
            name: "Nest migration suite",
            cwd: path.join(root, "backend-nest"),
            command: "npm.cmd",
            args: ["run", "verify:ops39:migration"],
            toolchainProfile: "nestjs",
          },
          {
            root,
            log: () => {},
            runWithToolchainFn: () => ({
              exitCode: 5,
              result: { status: "environment-failure" },
            }),
            rawRunFn: () => {
              throw new Error("raw command must not run");
            },
          },
        ),
      /Nest migration suite failed with exit 5/,
    );
    assert.equal(process.exitCode, 5);
  } finally {
    process.exitCode = previousExitCode;
  }
});

test("Go/Node/Git suite remains raw and does not invoke the dependency boundary", () => {
  const calls = [];
  const result = runAffectedConsumerSuite(
    {
      name: "Go suite",
      cwd: path.join(root, "backend-go"),
      command: "go",
      args: ["test", "./..."],
    },
    {
      root,
      log: () => {},
      runWithToolchainFn: () => {
        throw new Error("dependency boundary must not run for Go");
      },
      rawRunFn: (suite) => {
        calls.push(suite);
        return 0;
      },
    },
  );

  assert.equal(result.kind, "raw");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, "go");
});
