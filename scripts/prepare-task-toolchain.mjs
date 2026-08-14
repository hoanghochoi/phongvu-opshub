#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const EXIT_CODES = Object.freeze({
  PASS: 0,
  CONTRACT: 2,
  ENVIRONMENT: 5,
});

// Bumped when hydration behavior/commands or readiness probes change so old
// cached readiness is never trusted after a toolchain policy update.
const SCHEMA_VERSION = 5;
const PROFILE_ID = 'nestjs';
const FLUTTER_PROFILE_ID = 'flutter';
const ALL_PROFILE_ID = 'all';
const SUPPORTED_PROFILES = Object.freeze([
  PROFILE_ID,
  FLUTTER_PROFILE_ID,
  ALL_PROFILE_ID,
]);
const STATE_PATH = 'tmp/opshub-toolchain-state.json';
const NESTJS_REQUIRED_FILES = [
  'backend-nest/package.json',
  'backend-nest/package-lock.json',
  'backend-nest/prisma/schema.prisma',
  'backend-nest/prisma.config.ts',
];
const FLUTTER_REQUIRED_FILES = [
  'pubspec.yaml',
  'pubspec.lock',
  '.metadata',
];
const COMMAND_MAX_BUFFER_BYTES = 16 * 1024 * 1024;
const PUB_CACHE_LOCK_WAIT_MS = 5 * 60 * 1000;
const PUB_CACHE_LOCK_STALE_MS = 15 * 60 * 1000;
const PUB_CACHE_LOCK_POLL_MS = 250;
const FLUTTER_PLATFORM_PACKAGE_DIRS = Object.freeze([
  'android',
  'darwin',
  'ios',
  'linux',
  'macos',
  'native_assets',
  'web',
  'windows',
]);

const FLUTTER_GENERATED_TRACKED_PATHS = Object.freeze([
  /^lib\/l10n\/.+\.dart$/,
  /^ios\/Runner\/GeneratedPluginRegistrant\.(?:h|m)$/,
  /^linux\/flutter\/generated_plugin_registrant\.(?:cc|h)$/,
  /^linux\/flutter\/generated_plugins\.cmake$/,
  /^macos\/Flutter\/GeneratedPluginRegistrant\.swift$/,
  /^windows\/flutter\/generated_plugin_registrant\.(?:cc|h)$/,
  /^windows\/flutter\/generated_plugins\.cmake$/,
]);

class PreparationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'PreparationError';
    this.code = code;
  }
}

function fail(code, message) {
  throw new PreparationError(code, message);
}

export function parseArgs(argv) {
  const options = {
    profile: ALL_PROFILE_ID,
    dryRun: false,
    force: false,
    json: null,
    root: null,
    help: false,
  };

  if (argv.includes('--help')) {
    return { ...options, help: true };
  }

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--profile') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--'))
        fail(EXIT_CODES.CONTRACT, 'Thiếu giá trị cho --profile.');
      options.profile = value;
      index += 1;
      continue;
    }
    if (argument === '--dry-run') {
      options.dryRun = true;
      continue;
    }
    if (argument === '--force') {
      options.force = true;
      continue;
    }
    if (argument === '--json') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--'))
        fail(EXIT_CODES.CONTRACT, 'Thiếu giá trị cho --json.');
      options.json = value;
      index += 1;
      continue;
    }
    if (argument === '--root') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--'))
        fail(EXIT_CODES.CONTRACT, 'Thiếu giá trị cho --root.');
      options.root = value;
      index += 1;
      continue;
    }
    fail(EXIT_CODES.CONTRACT, `Tham số không hỗ trợ: ${argument}`);
  }

  if (!SUPPORTED_PROFILES.includes(options.profile)) {
    fail(
      EXIT_CODES.CONTRACT,
      `Profile không hỗ trợ: ${options.profile}. Chọn một trong: ${SUPPORTED_PROFILES.join(', ')}.`,
    );
  }
  return options;
}

function hashFile(root, relativePath) {
  const absolutePath = path.resolve(root, relativePath);
  if (!existsSync(absolutePath)) {
    fail(EXIT_CODES.CONTRACT, `Thiếu file contract: ${relativePath}`);
  }
  return createHash('sha256').update(readFileSync(absolutePath)).digest('hex');
}

function requiredFilesForProfile(profile) {
  if (profile === PROFILE_ID) return NESTJS_REQUIRED_FILES;
  if (profile === FLUTTER_PROFILE_ID) return FLUTTER_REQUIRED_FILES;
  fail(EXIT_CODES.CONTRACT, `Không có manifest cho profile: ${profile}.`);
}

function executableVersion(executable, argv = ['--version']) {
  const result = spawnSync(executable, argv, {
    cwd: process.cwd(),
    encoding: 'utf8',
    windowsHide: true,
    shell:
      process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(executable),
    maxBuffer: 1024 * 1024,
  });
  if (result.error || result.status !== 0) return 'unavailable';
  const output = String(result.stdout || result.stderr || '').trim();
  if (argv.includes('--machine')) {
    try {
      const parsed = JSON.parse(output);
      return JSON.stringify({
        frameworkVersion: parsed.frameworkVersion || null,
        frameworkRevision: parsed.frameworkRevision || null,
        dartSdkVersion: parsed.dartSdkVersion || null,
      });
    } catch {
      return output.slice(0, 240);
    }
  }
  return output.split(/\r?\n/).slice(0, 3).join('\n').slice(0, 240);
}

function toolchainVersions(profile) {
  const versions = {
    node: process.version,
    platform: process.platform,
    arch: process.arch,
  };
  if (profile === PROFILE_ID) {
    versions.npm = executableVersion(nestExecutable('npm'));
  }
  if (profile === FLUTTER_PROFILE_ID) {
    versions.flutter = executableVersion(flutterExecutable(), [
      '--version',
      '--machine',
    ]);
    versions.dart = executableVersion(
      process.platform === 'win32' ? 'dart.exe' : 'dart',
    );
  }
  return versions;
}

export function toolchainFingerprint(root, profile = PROFILE_ID) {
  const requiredFiles = requiredFilesForProfile(profile);
  const files = Object.fromEntries(
    requiredFiles.map((relativePath) => [
      relativePath,
      hashFile(root, relativePath),
    ]),
  );
  return createHash('sha256')
    .update(
      JSON.stringify({
        schemaVersion: SCHEMA_VERSION,
        profile,
        toolchain: toolchainVersions(profile),
        files,
      }),
    )
    .digest('hex');
}

function relativeStatePath(root) {
  return path.resolve(root, STATE_PATH);
}

function readState(root) {
  const statePath = relativeStatePath(root);
  if (!existsSync(statePath))
    return { schemaVersion: SCHEMA_VERSION, profiles: {} };
  try {
    const parsed = JSON.parse(readFileSync(statePath, 'utf8'));
    if (
      parsed?.schemaVersion !== SCHEMA_VERSION ||
      typeof parsed.profiles !== 'object'
    ) {
      return { schemaVersion: SCHEMA_VERSION, profiles: {} };
    }
    return parsed;
  } catch {
    return { schemaVersion: SCHEMA_VERSION, profiles: {} };
  }
}

function writeState(root, state) {
  const statePath = relativeStatePath(root);
  mkdirSync(path.dirname(statePath), { recursive: true });
  const temporaryPath = `${statePath}.${process.pid}.tmp`;
  try {
    writeFileSync(temporaryPath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
    renameSync(temporaryPath, statePath);
  } finally {
    if (existsSync(temporaryPath)) unlinkSync(temporaryPath);
  }
}

function nestExecutable(name) {
  return process.platform === 'win32' ? `${name}.cmd` : name;
}

function flutterExecutable() {
  return process.platform === 'win32' ? 'flutter.bat' : 'flutter';
}

function flutterPubCacheRoot() {
  return path.resolve(
    process.env.PUB_CACHE || path.join(os.homedir(), '.pub-cache'),
  );
}

function flutterPubCacheLockPath() {
  return path.join(flutterPubCacheRoot(), '.opshub-pub-cache.lock');
}

function processIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code === 'EPERM';
  }
}

function readLockMetadata(lockPath) {
  try {
    return JSON.parse(readFileSync(lockPath, 'utf8'));
  } catch {
    return null;
  }
}

function stalePubCacheLock(lockPath) {
  try {
    const ageMs = Date.now() - statSync(lockPath).mtimeMs;
    if (ageMs < PUB_CACHE_LOCK_STALE_MS) return false;
    const metadata = readLockMetadata(lockPath);
    return !processIsAlive(Number(metadata?.pid));
  } catch {
    return false;
  }
}

function sleepSync(milliseconds) {
  const signal = new Int32Array(new SharedArrayBuffer(4));
  Atomics.wait(signal, 0, 0, milliseconds);
}

function acquireFlutterPubCacheLock(root) {
  const lockPath = flutterPubCacheLockPath();
  mkdirSync(path.dirname(lockPath), { recursive: true });
  const startedAt = Date.now();
  while (Date.now() - startedAt < PUB_CACHE_LOCK_WAIT_MS) {
    try {
      const descriptor = openSync(lockPath, 'wx', 0o600);
      try {
        writeFileSync(
          lockPath,
          `${JSON.stringify({ pid: process.pid, worktree: '<worktree>' })}\n`,
          'utf8',
        );
      } finally {
        closeSync(descriptor);
      }
      return lockPath;
    } catch (error) {
      if (error?.code !== 'EEXIST') {
        fail(
          EXIT_CODES.ENVIRONMENT,
          `Không tạo được Flutter Pub cache lock: ${sanitizeDiagnostic(
            error?.message || error,
            root,
          )}`,
        );
      }
      if (stalePubCacheLock(lockPath)) {
        try {
          unlinkSync(lockPath);
        } catch {
          // Another hydrator may have acquired/replaced the lock; retry safely.
        }
        continue;
      }
      sleepSync(PUB_CACHE_LOCK_POLL_MS);
    }
  }
  fail(
    EXIT_CODES.ENVIRONMENT,
    'Flutter Pub cache đang được hydrate bởi một tiến trình khác quá lâu; ' +
      'xóa lock stale sau khi xác minh tiến trình rồi chạy lại preflight.',
  );
}

function releaseFlutterPubCacheLock(lockPath) {
  try {
    if (existsSync(lockPath)) unlinkSync(lockPath);
  } catch {
    // The lock is a best-effort coordination file; the next stale check can recover it.
  }
}

function runHydrationStep(root, step, runStepFn) {
  if (step.id !== 'flutter-pub-get') return runStepFn(root, step);
  const lockPath = acquireFlutterPubCacheLock(root);
  try {
    return runStepFn(root, step);
  } finally {
    releaseFlutterPubCacheLock(lockPath);
  }
}

function readJsonFile(filePath) {
  try {
    return JSON.parse(readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function resolvePackageRoot(packageConfigPath, rootUri) {
  if (typeof rootUri !== 'string' || rootUri.length === 0) return null;
  try {
    return fileURLToPath(new URL(rootUri, pathToFileURL(packageConfigPath)));
  } catch {
    return null;
  }
}

function resolvePackageUri(packageRoot, packageUri) {
  if (typeof packageUri !== 'string' || packageUri.length === 0) return null;
  try {
    const packageRootUri = pathToFileURL(
      path.join(packageRoot, path.sep),
    ).href;
    return fileURLToPath(new URL(packageUri, packageRootUri));
  } catch {
    return null;
  }
}

function isMaterializedPlatformPackage(packageRoot) {
  let pubspec;
  try {
    pubspec = readFileSync(path.join(packageRoot, 'pubspec.yaml'), 'utf8');
  } catch {
    return false;
  }
  if (!/\bplugin\s*:/i.test(pubspec)) return false;
  return FLUTTER_PLATFORM_PACKAGE_DIRS.some((directory) =>
    existsSync(path.join(packageRoot, directory)),
  );
}

function flutterPackageReadiness(root, packageConfigPath) {
  const packageConfig = readJsonFile(packageConfigPath);
  const packages = Array.isArray(packageConfig?.packages)
    ? packageConfig.packages
    : [];
  const packageNames = new Set();
  const missingPackages = [];
  let rootPackage = false;
  let packageUriRoots = packages.length > 0;

  for (const entry of packages) {
    const name = typeof entry?.name === 'string' ? entry.name : '<unnamed>';
    if (packageNames.has(name)) {
      missingPackages.push(`${name}:duplicate`);
      continue;
    }
    packageNames.add(name);
    const packageRoot = resolvePackageRoot(packageConfigPath, entry?.rootUri);
    if (!packageRoot || !existsSync(packageRoot)) {
      missingPackages.push(`${name}:root`);
      continue;
    }
    if (!existsSync(path.join(packageRoot, 'pubspec.yaml'))) {
      missingPackages.push(`${name}:pubspec`);
    }
    const packageUri = resolvePackageUri(packageRoot, entry?.packageUri);
    if (
      (!packageUri || !existsSync(packageUri)) &&
      !isMaterializedPlatformPackage(packageRoot)
    ) {
      packageUriRoots = false;
      missingPackages.push(`${name}:packageUri-or-platform`);
    }
    if (path.resolve(packageRoot) === path.resolve(root)) rootPackage = true;
  }

  return {
    packageConfigVersion:
      Number.isInteger(packageConfig?.configVersion) ? packageConfig.configVersion : null,
    packageCount: packages.length,
    packageConfigStructure:
      packageConfig !== null && Array.isArray(packageConfig?.packages),
    packageRoots: missingPackages.length === 0 && packages.length > 0,
    packageUriRoots,
    rootPackage,
    missingPackages: missingPackages.slice(0, 20),
  };
}

function sanitizeDiagnostic(value, root = process.cwd()) {
  let text = String(value || '');
  const normalizedRoot = path.resolve(root);
  text = text.replaceAll(normalizedRoot, '<worktree>');
  text = text.replaceAll(normalizedRoot.replaceAll('\\', '/'), '<worktree>');
  text = text.replace(/\b[A-Za-z]:[\\/][^\s'"<>]+/g, '<path>');
  text = text.replace(/(^|[\s(])\/(?:Users|home|tmp|workspace|app)\/[^\s'"<>]+/g, '$1<path>');
  return text.slice(-800);
}

function installedPackageReadiness(root) {
  const backendRoot = path.resolve(root, 'backend-nest');
  const packageJsonPath = path.join(backendRoot, 'package.json');
  const packageLockPath = path.join(backendRoot, 'node_modules', '.package-lock.json');
  const packageJson = readJsonFile(packageJsonPath);
  const installedLock = readJsonFile(packageLockPath);
  const nodeModules = path.dirname(packageLockPath);
  const directDependencies = Object.keys({
    ...(packageJson?.dependencies || {}),
    ...(packageJson?.devDependencies || {}),
  });
  const missingDirectDependencies = directDependencies.filter(
    (name) => !existsSync(path.join(nodeModules, ...name.split('/'), 'package.json')),
  );
  const missingLockPackages = [];
  for (const [packagePath, metadata] of Object.entries(installedLock?.packages || {})) {
    if (!packagePath.startsWith('node_modules/') || metadata?.link) continue;
    const relativePackagePath = packagePath.slice('node_modules/'.length);
    const packageJsonFile = path.join(
      nodeModules,
      ...relativePackagePath.split('/'),
      'package.json',
    );
    if (!existsSync(packageJsonFile)) missingLockPackages.push(relativePackagePath);
  }

  const prismaClientPackage = path.join(
    nodeModules,
    '@prisma',
    'client',
    'package.json',
  );
  const prismaGeneratedRoot = path.join(nodeModules, '.prisma', 'client');
  return {
    packageLockReadable: installedLock !== null,
    packageLockVersion:
      Number.isInteger(installedLock?.lockfileVersion)
        ? installedLock.lockfileVersion
        : null,
    installedPackageCount: Object.keys(installedLock?.packages || {}).length,
    directDependencies: directDependencies.length,
    missingDirectDependencies: missingDirectDependencies.slice(0, 20),
    missingLockPackages: missingLockPackages.slice(0, 20),
    nestCliEntry: existsSync(path.join(nodeModules, '@nestjs', 'cli', 'bin', 'nest.js')),
    prismaPackage: existsSync(prismaClientPackage),
    prismaClientEntry: existsSync(path.join(nodeModules, '@prisma', 'client', 'default.js')),
    prismaGenerated: existsSync(path.join(prismaGeneratedRoot, 'index.js')),
    prismaDefault: existsSync(path.join(prismaGeneratedRoot, 'default.js')),
  };
}

function readinessForProfile(root, profile) {
  if (profile === FLUTTER_PROFILE_ID) {
    const packageConfigPath = path.resolve(
      root,
      '.dart_tool',
      'package_config.json',
    );
    const packageConfig = flutterPackageReadiness(root, packageConfigPath);
    return {
      pubspec: existsSync(path.resolve(root, 'pubspec.yaml')),
      lockfile: existsSync(path.resolve(root, 'pubspec.lock')),
      packageConfig: existsSync(packageConfigPath),
      packageConfigReadable: packageConfig.packageConfigStructure,
      packageConfigVersion: packageConfig.packageConfigVersion,
      packageCount: packageConfig.packageCount,
      packageRoots: packageConfig.packageRoots,
      packageUriRoots: packageConfig.packageUriRoots,
      rootPackage: packageConfig.rootPackage,
      missingPackages: packageConfig.missingPackages,
    };
  }
  const nodeModules = path.resolve(root, 'backend-nest/node_modules');
  const nestBinary = path.join(nodeModules, '.bin', nestExecutable('nest'));
  const installed = installedPackageReadiness(root);
  return {
    nestBinary: existsSync(nestBinary),
    packageLockReadable: installed.packageLockReadable,
    packageLockVersion: installed.packageLockVersion,
    installedPackageCount: installed.installedPackageCount,
    directDependencies: installed.directDependencies,
    missingDirectDependencies: installed.missingDirectDependencies,
    missingLockPackages: installed.missingLockPackages,
    nestCliEntry: installed.nestCliEntry,
    prismaPackage: installed.prismaPackage,
    prismaClientEntry: installed.prismaClientEntry,
    prismaGenerated: installed.prismaGenerated,
    prismaDefault: installed.prismaDefault,
    installLockfile: existsSync(path.join(nodeModules, '.package-lock.json')),
  };
}

function isReadyForProfile(value, profile) {
  if (profile === FLUTTER_PROFILE_ID) {
    return (
      value.pubspec &&
      value.lockfile &&
      value.packageConfig &&
      value.packageConfigReadable &&
      value.packageConfigVersion >= 2 &&
      value.packageCount > 0 &&
      value.packageRoots &&
      value.packageUriRoots &&
      value.rootPackage
    );
  }
  return (
    value.nestBinary &&
    value.packageLockReadable &&
    value.packageLockVersion >= 1 &&
    value.missingDirectDependencies.length === 0 &&
    value.missingLockPackages.length === 0 &&
    value.nestCliEntry &&
    value.prismaPackage &&
    value.prismaClientEntry &&
    value.prismaGenerated &&
    value.prismaDefault &&
    value.installLockfile
  );
}

function normalizedStatusPath(value) {
  return String(value).replaceAll('\\', '/');
}

function statusEntries(root) {
  const result = spawnSync(
    'git',
    ['status', '--porcelain=v1', '--untracked-files=all'],
    {
      cwd: root,
      encoding: 'utf8',
      windowsHide: true,
      maxBuffer: COMMAND_MAX_BUFFER_BYTES,
    },
  );
  if (result.error || result.status !== 0) {
    fail(
      EXIT_CODES.ENVIRONMENT,
      `Không đọc được trạng thái worktree trước/sau Flutter preflight: ${
        result.error?.message || String(result.stderr || '').trim() || `exit ${result.status}`
      }`,
    );
  }
  return String(result.stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .map((line) => ({
      raw: line,
      path: normalizedStatusPath(line.slice(3)),
      untracked: line.startsWith('?? '),
    }));
}

function snapshotGeneratedFiles(root, entries) {
  const snapshots = new Map();
  for (const entry of entries) {
    if (entry.untracked || !isFlutterGeneratedTrackedPath(entry.path)) continue;
    const absolutePath = path.resolve(root, entry.path);
    if (existsSync(absolutePath)) snapshots.set(entry.path, readFileSync(absolutePath));
  }
  return snapshots;
}

function isFlutterGeneratedTrackedPath(relativePath) {
  return FLUTTER_GENERATED_TRACKED_PATHS.some((pattern) => pattern.test(relativePath));
}

function restoreGeneratedPath(root, relativePath) {
  const result = spawnSync(
    'git',
    ['restore', '--worktree', '--', relativePath],
    {
      cwd: root,
      encoding: 'utf8',
      windowsHide: true,
      maxBuffer: COMMAND_MAX_BUFFER_BYTES,
    },
  );
  if (result.error || result.status !== 0) {
    fail(
      EXIT_CODES.ENVIRONMENT,
      `Không thể dọn generated Flutter path ${relativePath}: ${
        result.error?.message || String(result.stderr || '').trim() || `exit ${result.status}`
      }`,
    );
  }
}

function restoreGeneratedBytes(root, relativePath, bytes) {
  try {
    writeFileSync(path.resolve(root, relativePath), bytes);
  } catch (error) {
    fail(
      EXIT_CODES.ENVIRONMENT,
      `Không thể khôi phục generated Flutter path ${relativePath}: ${sanitizeDiagnostic(
        error?.message || error,
        root,
      )}`,
    );
  }
}

function reconcileFlutterGeneratedChanges(root, beforeEntries, beforeGeneratedFiles) {
  const beforeByPath = new Map(beforeEntries.map((entry) => [entry.path, entry]));
  const afterEntries = statusEntries(root);
  const introduced = [];

  for (const entry of afterEntries) {
    const before = beforeByPath.get(entry.path);
    if (!before || before.raw !== entry.raw) introduced.push({ before, after: entry });
  }

  const unsafe = [];
  for (const change of introduced) {
    const { before, after } = change;
    if (after.untracked) {
      unsafe.push(`${after.path} (new non-ignored file)`);
      continue;
    }
    if (!isFlutterGeneratedTrackedPath(after.path)) {
      unsafe.push(`${after.path} (tracked file outside generated allowlist)`);
      continue;
    }
    if (before) {
      const beforeBytes = beforeGeneratedFiles.get(after.path);
      const afterBytes = existsSync(path.resolve(root, after.path))
        ? readFileSync(path.resolve(root, after.path))
        : null;
      if (beforeBytes && (!afterBytes || !beforeBytes.equals(afterBytes))) {
        restoreGeneratedBytes(root, after.path, beforeBytes);
        unsafe.push(`${after.path} (pre-existing user change was modified)`);
      }
      continue;
    }
    restoreGeneratedPath(root, after.path);
  }

  for (const [relativePath, beforeBytes] of beforeGeneratedFiles) {
    const absolutePath = path.resolve(root, relativePath);
    const afterBytes = existsSync(absolutePath) ? readFileSync(absolutePath) : null;
    if (afterBytes && beforeBytes.equals(afterBytes)) continue;
    restoreGeneratedBytes(root, relativePath, beforeBytes);
    unsafe.push(`${relativePath} (pre-existing user change was modified)`);
  }

  const remaining = statusEntries(root).filter((entry) => {
    const before = beforeByPath.get(entry.path);
    return !before || before.raw !== entry.raw;
  });
  if (remaining.length > 0) {
    unsafe.push(...remaining.map((entry) => `${entry.path} (cleanup incomplete)`));
  }
  if (unsafe.length > 0) {
    fail(
      EXIT_CODES.ENVIRONMENT,
      `Flutter pub get làm thay đổi worktree ngoài generated allowlist; review trước khi chạy tiếp:\n${[
        ...new Set(unsafe),
      ].join('\n')}`,
    );
  }
  return {
    introducedPaths: introduced.map(({ after }) => after.path),
    restoredPaths: introduced
      .filter(({ after }) => isFlutterGeneratedTrackedPath(after.path) && !after.untracked)
      .map(({ after }) => after.path),
    status: 'clean',
  };
}

function sanitizedExecutable(executable) {
  return path.basename(executable).replaceAll('\\', '/');
}

function runStep(root, step) {
  const result = spawnSync(step.executable, step.argv, {
    cwd: step.cwd,
    encoding: 'utf8',
    windowsHide: true,
    shell:
      process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(step.executable),
    stdio: ['inherit', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
  const stdout = String(result.stdout || '');
  const stderr = String(result.stderr || '');
  if (stdout) process.stdout.write(stdout);
  if (stderr) process.stderr.write(stderr);
  if (result.error) {
    return {
      id: step.id,
      executable: sanitizedExecutable(step.executable),
      argv: step.argv,
      status: 'environment-failure',
      exitCode: null,
      error: sanitizeDiagnostic(result.error.message, root).slice(0, 240),
    };
  }
  return {
    id: step.id,
    executable: sanitizedExecutable(step.executable),
    argv: step.argv,
    status: result.status === 0 ? 'passed' : 'environment-failure',
    exitCode: result.status,
    ...(result.status === 0
      ? {}
      : { error: sanitizeDiagnostic(`${stdout}\n${stderr}`, root).slice(-240) }),
  };
}

function stepsFor(root, profile) {
  if (profile === FLUTTER_PROFILE_ID) {
    return [
      {
        id: 'flutter-pub-get',
        executable: flutterExecutable(),
        argv: ['pub', 'get', '--enforce-lockfile'],
        cwd: path.resolve(root),
      },
    ];
  }
  const backendRoot = path.resolve(root, 'backend-nest');
  return [
      {
        id: 'nestjs-npm-ci',
        executable: nestExecutable('npm'),
        argv: ['ci', '--include=dev', '--ignore-scripts'],
      cwd: backendRoot,
    },
    {
      id: 'nestjs-prisma-generate',
      executable: nestExecutable('npx'),
      argv: ['--no-install', 'prisma', 'generate'],
      cwd: backendRoot,
    },
  ];
}

function resultBase(root, profile, fingerprint, options) {
  return {
    schemaVersion: SCHEMA_VERSION,
    profile,
    fingerprint,
    statePath: STATE_PATH,
    dryRun: options.dryRun,
    forced: options.force,
    toolchain: toolchainVersions(profile),
    retries: [],
    readiness: readinessForProfile(root, profile),
    steps: [],
  };
}

function isRetryablePrismaFailure(stepResult) {
  return (
    stepResult?.id === 'nestjs-prisma-generate' &&
    /(?:MODULE_NOT_FOUND|cannot find module|failed to load)/i.test(
      String(stepResult.error || ''),
    )
  );
}

function isRetryableToolchainFailure(stepResult) {
  if (isRetryablePrismaFailure(stepResult)) return true;
  if (!['nestjs-npm-ci', 'flutter-pub-get'].includes(stepResult?.id)) {
    return false;
  }
  return /(?:EINTEGRITY|ECONNRESET|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|ENOENT|EPERM|EBUSY|MODULE_NOT_FOUND|cannot find module|package .* not found|failed to materialize|failed to load)/i.test(
    String(stepResult.error || ''),
  );
}

function retryReason(stepResult) {
  if (isRetryablePrismaFailure(stepResult)) return 'transient-prisma-module-load';
  return 'transient-dependency-materialization';
}

function prepareSingleProfile({
  resolvedRoot,
  profile,
  dryRun,
  force,
  runStepFn,
} = {}) {
  const fingerprint = toolchainFingerprint(resolvedRoot, profile);
  const options = { dryRun, force };
  const result = resultBase(resolvedRoot, profile, fingerprint, options);
  const state = readState(resolvedRoot);
  const previous = state.profiles?.[profile];
  const readyBefore = isReadyForProfile(result.readiness, profile);
  if (!force && readyBefore && previous?.fingerprint === fingerprint) {
    result.status = 'cached';
    return { exitCode: EXIT_CODES.PASS, result };
  }

  result.status = dryRun ? 'planned' : 'preparing';
  const steps = stepsFor(resolvedRoot, profile);
  result.steps = steps.map((step) => ({
    id: step.id,
    executable: sanitizedExecutable(step.executable),
    argv: step.argv,
  }));
  if (dryRun) return { exitCode: EXIT_CODES.PASS, result };

  const beforeEntries = profile === FLUTTER_PROFILE_ID ? statusEntries(resolvedRoot) : null;
  const beforeGeneratedFiles =
    profile === FLUTTER_PROFILE_ID
      ? snapshotGeneratedFiles(resolvedRoot, beforeEntries)
      : null;
  result.steps = [];
  let attempt = 0;
  while (attempt < 2) {
    attempt += 1;
    let retry = false;
    for (const step of steps) {
      const rawStepResult = runHydrationStep(resolvedRoot, step, runStepFn);
      const stepResult = {
        ...rawStepResult,
        ...(rawStepResult?.error
          ? { error: sanitizeDiagnostic(rawStepResult.error, resolvedRoot) }
          : {}),
      };
      result.steps.push({ ...stepResult, attempt });
      if (profile === FLUTTER_PROFILE_ID) {
        try {
          result.worktree = reconcileFlutterGeneratedChanges(
            resolvedRoot,
            beforeEntries,
            beforeGeneratedFiles,
          );
        } catch (error) {
          result.status = 'environment-failure';
          result.error = sanitizeDiagnostic(error?.message || error, resolvedRoot);
          result.readiness = readinessForProfile(resolvedRoot, profile);
          return { exitCode: EXIT_CODES.ENVIRONMENT, result };
        }
      }
      if (stepResult.status !== 'passed') {
        if (attempt === 1 && isRetryableToolchainFailure(stepResult)) {
          const fingerprintAfterFailure = toolchainFingerprint(
            resolvedRoot,
            profile,
          );
          if (fingerprintAfterFailure !== fingerprint) {
            result.status = 'environment-failure';
            result.error =
              'Toolchain manifest changed during Prisma retry; proof is stale.';
            result.readiness = readinessForProfile(resolvedRoot, profile);
            return { exitCode: EXIT_CODES.ENVIRONMENT, result };
          }
          result.retries.push({
            step: step.id,
            fromAttempt: attempt,
            toAttempt: attempt + 1,
            reason: retryReason(stepResult),
          });
          retry = true;
          break;
        }
        result.status = 'environment-failure';
        result.readiness = readinessForProfile(resolvedRoot, profile);
        return { exitCode: EXIT_CODES.ENVIRONMENT, result };
      }
    }
    if (!retry) break;
  }

  result.readiness = readinessForProfile(resolvedRoot, profile);
  if (!isReadyForProfile(result.readiness, profile)) {
    result.status = 'environment-failure';
    return { exitCode: EXIT_CODES.ENVIRONMENT, result };
  }
  state.schemaVersion = SCHEMA_VERSION;
  state.profiles = {
    ...(state.profiles || {}),
    [profile]: {
      fingerprint,
      ready: true,
      preparedAtUtc: new Date().toISOString(),
    },
  };
  writeState(resolvedRoot, state);
  result.status = 'prepared';
  return { exitCode: EXIT_CODES.PASS, result };
}

export function prepareTaskToolchain({
  root = process.cwd(),
  profile = ALL_PROFILE_ID,
  dryRun = false,
  force = false,
  runStepFn = runStep,
} = {}) {
  const resolvedRoot = path.resolve(root);
  if (!SUPPORTED_PROFILES.includes(profile)) {
    fail(
      EXIT_CODES.CONTRACT,
      `Profile không hỗ trợ: ${profile}. Chọn một trong: ${SUPPORTED_PROFILES.join(', ')}.`,
    );
  }
  if (profile !== ALL_PROFILE_ID) {
    return prepareSingleProfile({
      resolvedRoot,
      profile,
      dryRun,
      force,
      runStepFn,
    });
  }

  const profiles = [];
  for (const profileId of [PROFILE_ID, FLUTTER_PROFILE_ID]) {
    const prepared = prepareSingleProfile({
      resolvedRoot,
      profile: profileId,
      dryRun,
      force,
      runStepFn,
    });
    profiles.push(prepared);
    if (prepared.exitCode !== EXIT_CODES.PASS) break;
  }
  const failed = profiles.find((entry) => entry.exitCode !== EXIT_CODES.PASS);
  return {
    exitCode: failed?.exitCode ?? EXIT_CODES.PASS,
    result: {
      schemaVersion: SCHEMA_VERSION,
      profile: ALL_PROFILE_ID,
      statePath: STATE_PATH,
      dryRun,
      forced: force,
      status: failed
        ? 'environment-failure'
        : profiles.every((entry) => entry.result.status === 'cached')
          ? 'cached'
          : dryRun
            ? 'planned'
            : 'prepared',
      profiles: profiles.map((entry) => entry.result),
    },
  };
}

function help() {
  return (
    `Usage: node scripts/prepare-task-toolchain.mjs [options]\n\n` +
    `  --profile nestjs|flutter|all  Prepare the selected local toolchain (default: all)\n` +
    `  --dry-run                    Report required steps without executing them\n` +
    `  --force                      Re-run hydration even when the fingerprint is cached\n` +
    `  --root <path>                Repair/inspect an existing worktree from another cwd\n` +
    `  --json <path>          Write schema-v1 result JSON\n`
  );
}

export function main(
  argv = process.argv.slice(2),
  { root = process.cwd() } = {},
) {
  let options;
  try {
    options = parseArgs(argv);
    if (options.help) {
      console.log(help());
      return EXIT_CODES.PASS;
    }
    const selectedRoot = options.root ? path.resolve(root, options.root) : root;
    if (!existsSync(selectedRoot)) {
      fail(EXIT_CODES.CONTRACT, `Worktree không tồn tại: ${options.root}`);
    }
    const { exitCode, result } = prepareTaskToolchain({
      root: selectedRoot,
      profile: options.profile,
      dryRun: options.dryRun,
      force: options.force,
    });
    if (options.json) {
      const outputPath = path.resolve(selectedRoot, options.json);
      mkdirSync(path.dirname(outputPath), { recursive: true });
      writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    }
    console.log(JSON.stringify(result, null, 2));
    return exitCode;
  } catch (error) {
    const code =
      error instanceof PreparationError ? error.code : EXIT_CODES.ENVIRONMENT;
    const result = {
      schemaVersion: SCHEMA_VERSION,
      status: 'failed',
      code,
      error: sanitizeDiagnostic(error?.message || error, root),
    };
    if (options?.json) {
      const outputPath = path.resolve(
        options.root ? path.resolve(root, options.root) : root,
        options.json,
      );
      mkdirSync(path.dirname(outputPath), { recursive: true });
      writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
    }
    console.error(`TOOLCHAIN PREPARE FAILED (${code}): ${result.error}`);
    return code;
  }
}

const invoked =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invoked) process.exitCode = main();
