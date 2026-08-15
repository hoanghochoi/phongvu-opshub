#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import {
  closeSync,
  mkdirSync,
  openSync,
  writeFileSync,
  writeSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const separator = argv.indexOf('--');
  if (separator < 0) fail('Missing command separator.');
  const options = {
    cwd: null,
    executable: null,
    stdoutFile: null,
    stderrFile: null,
    resultFile: null,
    command: argv.slice(separator + 1),
  };
  for (let index = 0; index < separator; index += 1) {
    const argument = argv[index];
    const next = argv[index + 1];
    if (
      ![
        '--cwd',
        '--executable',
        '--stdout-file',
        '--stderr-file',
        '--result-file',
      ].includes(argument)
    ) {
      fail(`Unknown argument: ${argument}`);
    }
    if (!next || next.startsWith('--')) fail(`${argument} requires a value.`);
    if (argument === '--cwd') options.cwd = next;
    if (argument === '--executable') options.executable = next;
    if (argument === '--stdout-file') options.stdoutFile = next;
    if (argument === '--stderr-file') options.stderrFile = next;
    if (argument === '--result-file') options.resultFile = next;
    index += 1;
  }
  if (
    !options.cwd ||
    !options.executable ||
    !options.stdoutFile ||
    !options.stderrFile ||
    !options.resultFile ||
    options.command.length === 0
  ) {
    fail('Incomplete command tee options.');
  }
  return options;
}

function writeAll(descriptor, chunk) {
  let offset = 0;
  while (offset < chunk.length) {
    const written = writeSync(descriptor, chunk, offset, chunk.length - offset);
    if (written <= 0) throw new Error('Command output write made no progress.');
    offset += written;
  }
}

async function forward(stream, descriptor, target) {
  if (!stream) return;
  for await (const chunk of stream) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
    writeAll(descriptor, buffer);
    if (!target.write(buffer)) await once(target, 'drain');
  }
}

async function run(options) {
  mkdirSync(path.dirname(options.stdoutFile), { recursive: true });
  const stdoutDescriptor = openSync(options.stdoutFile, 'w');
  const stderrDescriptor = openSync(options.stderrFile, 'w');
  let child;
  let commandError = null;
  let status = null;
  let signal = null;
  try {
    child = spawn(options.executable, options.command, {
      cwd: options.cwd,
      env: process.env,
      shell: process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(options.executable),
      windowsHide: true,
      stdio: ['inherit', 'pipe', 'pipe'],
    });
    const close = new Promise((resolve) => {
      child.once('error', (error) => {
        commandError = error?.message || String(error);
      });
      child.once('close', (exitCode, exitSignal) => {
        status = exitCode;
        signal = exitSignal;
        resolve();
      });
    });
    await Promise.all([
      forward(child.stdout, stdoutDescriptor, process.stdout),
      forward(child.stderr, stderrDescriptor, process.stderr),
      close,
    ]);
  } catch (error) {
    commandError = error?.message || String(error);
  } finally {
    closeSync(stdoutDescriptor);
    closeSync(stderrDescriptor);
  }

  writeFileSync(
    options.resultFile,
    `${JSON.stringify({ status, signal, error: commandError })}\n`,
    'utf8',
  );
  if (commandError) process.exitCode = 1;
  else if (Number.isInteger(status)) process.exitCode = status;
  else process.exitCode = 1;
}

async function main(argv = process.argv.slice(2)) {
  await run(parseArgs(argv));
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) {
  main().catch((error) => {
    console.error(`TOOLCHAIN COMMAND TEE FAILED: ${error.message}`);
    process.exitCode = 1;
  });
}
