import { spawnSync } from "node:child_process";
import path from "node:path";

import { runWithToolchain } from "./run-with-toolchain.mjs";

function defaultRawRun(suite) {
  const result = spawnSync(suite.command, suite.args, {
    cwd: suite.cwd,
    stdio: "inherit",
    windowsHide: true,
    shell: false,
  });
  if (result.error) throw result.error;
  return result.status;
}

function failure(name, exitCode) {
  return new Error(`${name} failed with exit ${exitCode ?? "unknown"}`);
}

/**
 * Run one affected-consumer suite while keeping dependency-owning commands
 * behind the repository toolchain boundary. Go/Node/Git suites intentionally
 * remain raw because they do not consume Flutter or Nest dependency state.
 */
export function runAffectedConsumerSuite(
  suite,
  {
    root,
    log = console.log,
    runWithToolchainFn = runWithToolchain,
    rawRunFn = defaultRawRun,
  } = {},
) {
  log(`\n${suite.name}`);

  if (suite.toolchainProfile) {
    const relativeCwd =
      path.relative(root, suite.cwd).replaceAll("\\", "/") || ".";
    const result = runWithToolchainFn({
      root,
      profile: suite.toolchainProfile,
      cwd: relativeCwd,
      command: [suite.command, ...suite.args],
    });
    if (result?.exitCode !== 0) {
      process.exitCode = result?.exitCode ?? 1;
      throw failure(suite.name, result?.exitCode);
    }
    return { kind: "toolchain", result };
  }

  const status = rawRunFn(suite);
  if (status !== 0) {
    process.exitCode = status ?? 1;
    throw failure(suite.name, status);
  }
  return { kind: "raw", status };
}
