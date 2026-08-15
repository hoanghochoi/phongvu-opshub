#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  closeSync,
  existsSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  rmSync,
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
const SCHEMA_VERSION = 7;
const PROFILE_ID = 'nestjs';
const FLUTTER_PROFILE_ID = 'flutter';
const ALL_PROFILE_ID = 'all';
const SUPPORTED_PROFILES = Object.freeze([
  PROFILE_ID,
  FLUTTER_PROFILE_ID,
  ALL_PROFILE_ID,
]);
const STATE_PATH = 'tmp/opshub-toolchain-state.json';
const NODE_MODULES_RECOVERY_PREFIX = '.opshub-node_modules-recovery-';
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
const NEST_TOOLCHAIN_LOCK_RELATIVE_PATH = path.join(
  'tmp',
  '.opshub-nest-toolchain.lock',
);
const INHERITED_LEASE_ENV = 'OPSHUB_TOOLCHAIN_LEASE';
const activeLockDepth = new Map();
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

function sortJson(value) {
  if (Array.isArray(value)) return value.map((entry) => sortJson(entry));
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, sortJson(value[key])]),
    );
  }
  return value;
}

function nestDependencyManifest(root) {
  const relativePath = 'backend-nest/package.json';
  const packagePath = path.resolve(root, relativePath);
  const packageJson = readJsonFile(packagePath);
  if (!packageJson || typeof packageJson !== 'object') {
    fail(EXIT_CODES.CONTRACT, `Không đọc được JSON contract: ${relativePath}`);
  }

  // Scripts are workflow policy, not dependency state. Keeping them out of
  // the hydration fingerprint prevents adding a lifecycle preflight from
  // needlessly rerunning npm ci and touching Windows node_modules.
  return sortJson({
    dependencies: packageJson.dependencies || {},
    devDependencies: packageJson.devDependencies || {},
    optionalDependencies: packageJson.optionalDependencies || {},
    peerDependencies: packageJson.peerDependencies || {},
    bundledDependencies: packageJson.bundledDependencies || packageJson.bundleDependencies || [],
    overrides: packageJson.overrides || {},
    engines: packageJson.engines || {},
    packageManager: packageJson.packageManager || null,
  });
}

function hashDependencyManifest(root) {
  return createHash('sha256')
    .update(JSON.stringify(nestDependencyManifest(root)))
    .digest('hex');
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
  const materializedFingerprint =
    profile === FLUTTER_PROFILE_ID
      ? flutterMaterializedFingerprint(
          path.resolve(root, '.dart_tool', 'package_config.json'),
        )
      : null;
  const files = Object.fromEntries(
    requiredFiles.map((relativePath) => [
      relativePath,
      relativePath === 'backend-nest/package.json'
        ? hashDependencyManifest(root)
        : hashFile(root, relativePath),
    ]),
  );
  return createHash('sha256')
    .update(
      JSON.stringify({
        schemaVersion: SCHEMA_VERSION,
        profile,
        toolchain: toolchainVersions(profile),
        files,
        materializedFingerprint,
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

function nestToolchainLockPath(root) {
  return path.resolve(root, NEST_TOOLCHAIN_LOCK_RELATIVE_PATH);
}

function toolchainLeasePath(root, profile) {
  if (profile === FLUTTER_PROFILE_ID) return flutterPubCacheLockPath();
  if (profile === PROFILE_ID) return nestToolchainLockPath(root);
  return null;
}

function lockKey(lockPath) {
  const normalized = path.normalize(lockPath);
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
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

function staleCoordinatedLock(lockPath) {
  try {
    const ageMs = Date.now() - statSync(lockPath).mtimeMs;
    const metadata = readLockMetadata(lockPath);
    const pid = Number(metadata?.pid);
    if (Number.isInteger(pid) && pid > 0) return !processIsAlive(pid);
    return ageMs >= PUB_CACHE_LOCK_STALE_MS;
  } catch {
    return false;
  }
}

function sleepSync(milliseconds) {
  const signal = new Int32Array(new SharedArrayBuffer(4));
  Atomics.wait(signal, 0, 0, milliseconds);
}

function releaseCoordinatedLock(lockPath) {
  const key = lockKey(lockPath);
  const current = activeLockDepth.get(key);
  if (!current) return;
  if (current.depth > 1) {
    current.depth -= 1;
    return;
  }
  activeLockDepth.delete(key);
  try {
    if (existsSync(lockPath)) unlinkSync(lockPath);
  } catch {
    // The lock is a best-effort coordination file; the next stale check can recover it.
  }
}

function inheritedLeaseMetadata(root, profile) {
  const raw = process.env[INHERITED_LEASE_ENV];
  if (!raw) return null;
  let metadata;
  try {
    metadata = JSON.parse(raw);
  } catch {
    return null;
  }
  const parentPid = Number(metadata?.pid);
  if (
    !Number.isInteger(parentPid) ||
    parentPid <= 0 ||
    metadata?.profile !== profile ||
    path.resolve(String(metadata?.root || '')) !== path.resolve(root) ||
    !processIsAlive(parentPid)
  ) {
    return null;
  }
  const lockPath = toolchainLeasePath(root, profile);
  const lockMetadata = lockPath ? readLockMetadata(lockPath) : null;
  return Number(lockMetadata?.pid) === parentPid ? metadata : null;
}

function inheritedLeaseMatches(root, profile) {
  return inheritedLeaseMetadata(root, profile) !== null;
}

function acquireCoordinatedLock(lockPath, root, label) {
  const key = lockKey(lockPath);
  const current = activeLockDepth.get(key);
  if (current) {
    current.depth += 1;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      releaseCoordinatedLock(lockPath);
    };
  }

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
      activeLockDepth.set(key, { depth: 1 });
      let released = false;
      return () => {
        if (released) return;
        released = true;
        releaseCoordinatedLock(lockPath);
      };
    } catch (error) {
      if (error?.code !== 'EEXIST') {
        fail(
          EXIT_CODES.ENVIRONMENT,
          `Không tạo được ${label}: ${sanitizeDiagnostic(
            error?.message || error,
            root,
          )}`,
        );
      }
      if (staleCoordinatedLock(lockPath)) {
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
    `${label} đang được giữ bởi một tiến trình khác quá lâu; ` +
      'xóa lock stale sau khi xác minh tiến trình rồi chạy lại preflight.',
  );
}

function acquireFlutterPubCacheLock(root) {
  return acquireCoordinatedLock(
    flutterPubCacheLockPath(),
    root,
    'Flutter Pub cache lock',
  );
}

export function acquireToolchainLease({ root = process.cwd(), profile } = {}) {
  const resolvedRoot = path.resolve(root);
  if (inheritedLeaseMatches(resolvedRoot, profile)) return () => {};
  if (profile === FLUTTER_PROFILE_ID)
    return acquireFlutterPubCacheLock(resolvedRoot);
  if (profile === PROFILE_ID) {
    return acquireCoordinatedLock(
      nestToolchainLockPath(resolvedRoot),
      resolvedRoot,
      'NestJS toolchain lock',
    );
  }
  fail(
    EXIT_CODES.CONTRACT,
    `Không có toolchain lease cho profile: ${profile}.`,
  );
}

export function toolchainLeaseEnvironment({
  root = process.cwd(),
  profile,
} = {}) {
  const inherited = inheritedLeaseMetadata(path.resolve(root), profile);
  return {
    ...process.env,
    [INHERITED_LEASE_ENV]: JSON.stringify(
      inherited || {
        pid: process.pid,
        profile,
        root: path.resolve(root),
      },
    ),
  };
}

function runHydrationStep(root, step, runStepFn, recoveryPaths = []) {
  if (step.id === 'flutter-pub-get') {
    const releaseLock = acquireFlutterPubCacheLock(root);
    try {
      return runStepFn(root, step);
    } finally {
      releaseLock();
    }
  }

  const firstResult = runStepFn(root, step);
  if (!isNodeModulesDirectoryConflict(firstResult)) return firstResult;

  const recovery = quarantineNestNodeModules(root);
  if (recovery.status !== 'quarantined') {
    return { ...firstResult, recovery };
  }
  recoveryPaths.push(recovery.path);
  const retryResult = runStepFn(root, step);
  return { ...retryResult, recovery };
}

function isNodeModulesDirectoryConflict(stepResult) {
  return (
    stepResult?.id === 'nestjs-npm-ci' &&
    /(?:ENOTEMPTY|directory not empty|rmdir|rename .*node_modules)/i.test(
      String(stepResult.error || ''),
    )
  );
}

function quarantineNestNodeModules(root) {
  const nodeModules = path.resolve(root, 'backend-nest/node_modules');
  if (!existsSync(nodeModules)) {
    return { status: 'not-present' };
  }

  let metadata;
  try {
    metadata = lstatSync(nodeModules);
  } catch (error) {
    return {
      status: 'failed',
      error: sanitizeDiagnostic(error?.message || error, root),
    };
  }
  if (!metadata.isDirectory() || metadata.isSymbolicLink()) {
    return {
      status: 'failed',
      error:
        'backend-nest/node_modules không phải thư mục vật lý; không quarantine tự động.',
    };
  }

  const recoveryName = `${NODE_MODULES_RECOVERY_PREFIX}${process.pid}-${Date.now()}`;
  const recoveryPath = path.resolve(root, 'backend-nest', recoveryName);
  try {
    renameSync(nodeModules, recoveryPath);
    return {
      status: 'quarantined',
      path: path.relative(root, recoveryPath).replaceAll('\\', '/'),
    };
  } catch (error) {
    return {
      status: 'failed',
      error: sanitizeDiagnostic(
        `Không thể quarantine backend-nest/node_modules: ${error?.message || error}`,
        root,
      ),
    };
  }
}

function cleanupNodeModulesRecovery(root, recoveryPaths) {
  const failures = [];
  for (const relativePath of recoveryPaths) {
    const recoveryPath = path.resolve(root, relativePath);
    const relative = path.relative(root, recoveryPath);
    if (
      relative === '..' ||
      relative.startsWith(`..${path.sep}`) ||
      path.isAbsolute(relative) ||
      !relative.startsWith(`backend-nest${path.sep}${NODE_MODULES_RECOVERY_PREFIX}`)
    ) {
      failures.push(`${relativePath}: đường dẫn recovery không hợp lệ`);
      continue;
    }
    try {
      rmSync(recoveryPath, { recursive: true, force: true });
    } catch (error) {
      failures.push(
        `${relativePath}: ${sanitizeDiagnostic(error?.message || error, root)}`,
      );
    }
  }
  return failures;
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

function isPhysicalDirectory(value) {
  try {
    return statSync(value).isDirectory();
  } catch {
    return false;
  }
}

function flutterMaterializedFingerprint(packageConfigPath) {
  const packageConfig = readJsonFile(packageConfigPath);
  const packages = Array.isArray(packageConfig?.packages)
    ? packageConfig.packages
    : null;
  if (!packages) return null;

  const descriptors = packages.map((entry) => {
    const name = typeof entry?.name === 'string' ? entry.name : '<unnamed>';
    const packageRoot = resolvePackageRoot(packageConfigPath, entry?.rootUri);
    const pubspecPath = packageRoot
      ? path.join(packageRoot, 'pubspec.yaml')
      : null;
    let pubspecSha256 = null;
    if (pubspecPath) {
      try {
        pubspecSha256 = createHash('sha256')
          .update(readFileSync(pubspecPath))
          .digest('hex');
      } catch {
        pubspecSha256 = null;
      }
    }
    const packageUri = packageRoot
      ? resolvePackageUri(packageRoot, entry?.packageUri)
      : null;
    return {
      name,
      rootReady: Boolean(packageRoot && isPhysicalDirectory(packageRoot)),
      pubspecSha256,
      packageUriReady: Boolean(packageUri && isPhysicalDirectory(packageUri)),
      platformMaterialized: Boolean(
        packageRoot && isMaterializedPlatformPackage(packageRoot),
      ),
    };
  });

  descriptors.sort((left, right) => left.name.localeCompare(right.name));
  return createHash('sha256')
    .update(JSON.stringify(descriptors))
    .digest('hex');
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
    if (!packageRoot || !isPhysicalDirectory(packageRoot)) {
      missingPackages.push(`${name}:root`);
      continue;
    }
    if (!existsSync(path.join(packageRoot, 'pubspec.yaml'))) {
      missingPackages.push(`${name}:pubspec`);
    }
    const packageUri = resolvePackageUri(packageRoot, entry?.packageUri);
    if (
      (!packageUri || !isPhysicalDirectory(packageUri)) &&
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

function flutterPluginReadiness(root, pluginMetadataPath, packageNames) {
  const metadata = readJsonFile(pluginMetadataPath);
  const platforms = metadata?.plugins;
  const dependencyGraph = metadata?.dependencyGraph;
  const missingPlugins = [];
  let pluginEntries = 0;
  let pluginRoots = true;
  let pluginDependencies = true;

  if (!metadata || typeof platforms !== 'object' || platforms === null) {
    return {
      pluginMetadataReadable: false,
      pluginEntries: 0,
      pluginRoots: false,
      pluginDependencies: false,
      missingPlugins: ['metadata:plugins'],
    };
  }

  for (const [platform, entries] of Object.entries(platforms)) {
    if (!Array.isArray(entries)) {
      pluginRoots = false;
      missingPlugins.push(`${platform}:entries`);
      continue;
    }
    const platformPluginNames = new Set();
    for (const entry of entries) {
      const name = typeof entry?.name === 'string' ? entry.name : '<unnamed>';
      pluginEntries += 1;
      if (platformPluginNames.has(name)) {
        missingPlugins.push(`${name}:duplicate`);
      }
      platformPluginNames.add(name);
      const pluginPath =
        typeof entry?.path === 'string' && entry.path.length > 0
          ? path.isAbsolute(entry.path)
            ? path.resolve(entry.path)
            : path.resolve(root, entry.path)
          : null;
      if (!pluginPath || !isPhysicalDirectory(pluginPath)) {
        pluginRoots = false;
        missingPlugins.push(`${name}:path`);
        continue;
      }
      if (!existsSync(path.join(pluginPath, 'pubspec.yaml'))) {
        pluginRoots = false;
        missingPlugins.push(`${name}:pubspec`);
      }
    }
  }

  if (!Array.isArray(dependencyGraph)) {
    pluginDependencies = false;
    missingPlugins.push('metadata:dependencyGraph');
  } else {
    for (const entry of dependencyGraph) {
      const name = typeof entry?.name === 'string' ? entry.name : '<unnamed>';
      const dependencies = Array.isArray(entry?.dependencies)
        ? entry.dependencies
        : [];
      if (name !== '<unnamed>' && !packageNames.has(name)) {
        pluginDependencies = false;
        missingPlugins.push(`${name}:package-config`);
      }
      for (const dependency of dependencies) {
        if (typeof dependency !== 'string' || !packageNames.has(dependency)) {
          pluginDependencies = false;
          missingPlugins.push(`${name}:${String(dependency)}:package-config`);
        }
      }
    }
  }

  return {
    pluginMetadataReadable: true,
    pluginEntries,
    pluginRoots,
    pluginDependencies,
    missingPlugins: missingPlugins.slice(0, 20),
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

function packageEntrypointExists(packageRoot, entrypoint) {
  if (typeof entrypoint !== 'string' || entrypoint.length === 0) return true;
  const resolved = path.resolve(packageRoot, entrypoint);
  const relative = path.relative(packageRoot, resolved);
  if (
    relative === '..' ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    return false;
  }
  const candidates = [
    resolved,
    `${resolved}.js`,
    `${resolved}.cjs`,
    `${resolved}.mjs`,
    `${resolved}.json`,
    path.join(resolved, 'package.json'),
    path.join(resolved, 'index.js'),
    path.join(resolved, 'index.cjs'),
    path.join(resolved, 'index.mjs'),
  ];
  return candidates.some((candidate) => existsSync(candidate));
}

function packageEntrypoints(packageJson) {
  const values = [];
  for (const key of ['main', 'module', 'browser']) {
    if (typeof packageJson?.[key] === 'string') values.push(packageJson[key]);
  }
  if (typeof packageJson?.bin === 'string') values.push(packageJson.bin);
  if (packageJson?.bin && typeof packageJson.bin === 'object') {
    values.push(...Object.values(packageJson.bin));
  }
  return [...new Set(values.filter((value) => typeof value === 'string'))];
}

function installedPackageEntrypointReadiness(nodeModules, directDependencies) {
  const missingPackageEntrypoints = [];
  let packageEntrypointsChecked = 0;
  for (const name of directDependencies) {
    const packageJsonPath = path.join(
      nodeModules,
      ...name.split('/'),
      'package.json',
    );
    const installedPackageJson = readJsonFile(packageJsonPath);
    if (!installedPackageJson) continue;
    const packageRoot = path.dirname(packageJsonPath);
    for (const entrypoint of packageEntrypoints(installedPackageJson)) {
      packageEntrypointsChecked += 1;
      if (!packageEntrypointExists(packageRoot, entrypoint)) {
        missingPackageEntrypoints.push(`${name}:${entrypoint}`);
      }
    }
  }
  return {
    packageEntrypointsChecked,
    missingPackageEntrypoints: missingPackageEntrypoints.slice(0, 20),
  };
}

function installedPackageReadiness(root) {
  const backendRoot = path.resolve(root, 'backend-nest');
  const packageJsonPath = path.join(backendRoot, 'package.json');
  const packageLockPath = path.join(backendRoot, 'node_modules', '.package-lock.json');
  const packageJson = readJsonFile(packageJsonPath);
  const installedLock = readJsonFile(packageLockPath);
  const trackedLock = readJsonFile(
    path.join(backendRoot, 'package-lock.json'),
  );
  const nodeModules = path.dirname(packageLockPath);
  const directDependencies = Object.keys({
    ...(packageJson?.dependencies || {}),
    ...(packageJson?.devDependencies || {}),
  });
  const missingDirectDependencies = directDependencies.filter(
    (name) => !existsSync(path.join(nodeModules, ...name.split('/'), 'package.json')),
  );
  const missingLockPackages = [];
  const lockMetadataMismatches = [];
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

  for (const [packagePath, metadata] of Object.entries(
    trackedLock?.packages || {},
  )) {
    if (!packagePath.startsWith('node_modules/') || metadata?.link) continue;
    // npm intentionally omits optional packages that do not match the current
    // OS/CPU. Required packages must still match the tracked lock metadata.
    if (metadata?.optional) continue;
    const installed = installedLock?.packages?.[packagePath];
    if (!installed) {
      lockMetadataMismatches.push(`${packagePath}:missing`);
      continue;
    }
    if (metadata.version !== installed.version) {
      lockMetadataMismatches.push(
        `${packagePath}:version:${metadata.version}:${installed.version}`,
      );
      continue;
    }
    if (metadata.integrity && metadata.integrity !== installed.integrity) {
      lockMetadataMismatches.push(`${packagePath}:integrity`);
    }
  }

  const prismaClientPackage = path.join(
    nodeModules,
    '@prisma',
    'client',
    'package.json',
  );
  const prismaGeneratedRoot = path.join(nodeModules, '.prisma', 'client');
  const entrypoints = installedPackageEntrypointReadiness(
    nodeModules,
    directDependencies,
  );
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
    lockMetadataMismatches: lockMetadataMismatches.slice(0, 20),
    lockMetadataMatches: lockMetadataMismatches.length === 0,
    packageEntrypointsChecked: entrypoints.packageEntrypointsChecked,
    missingPackageEntrypoints: entrypoints.missingPackageEntrypoints,
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
    const packageNames = new Set();
    const parsedPackageConfig = readJsonFile(packageConfigPath);
    for (const entry of parsedPackageConfig?.packages || []) {
      if (typeof entry?.name === 'string') packageNames.add(entry.name);
    }
    const pluginMetadataPath = path.resolve(
      root,
      '.flutter-plugins-dependencies',
    );
    const plugins = flutterPluginReadiness(
      root,
      pluginMetadataPath,
      packageNames,
    );
    const materializedFingerprint = flutterMaterializedFingerprint(
      packageConfigPath,
    );
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
      pluginMetadata: existsSync(pluginMetadataPath),
      pluginMetadataReadable: plugins.pluginMetadataReadable,
      pluginEntries: plugins.pluginEntries,
      pluginRoots: plugins.pluginRoots,
      pluginDependencies: plugins.pluginDependencies,
      missingPlugins: plugins.missingPlugins,
      materializedFingerprint,
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
    lockMetadataMismatches: installed.lockMetadataMismatches,
    lockMetadataMatches: installed.lockMetadataMatches,
    packageEntrypointsChecked: installed.packageEntrypointsChecked,
    missingPackageEntrypoints: installed.missingPackageEntrypoints,
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
      value.rootPackage &&
      value.pluginMetadata &&
      value.pluginMetadataReadable &&
      value.pluginRoots &&
      value.pluginDependencies &&
      typeof value.materializedFingerprint === 'string' &&
      value.materializedFingerprint.length > 0
    );
  }
  return (
    value.nestBinary &&
    value.packageLockReadable &&
    value.packageLockVersion >= 1 &&
    value.missingDirectDependencies.length === 0 &&
    value.missingLockPackages.length === 0 &&
    value.lockMetadataMatches &&
    value.missingPackageEntrypoints.length === 0 &&
    value.nestCliEntry &&
    value.prismaPackage &&
    value.prismaClientEntry &&
    value.prismaGenerated &&
    value.prismaDefault &&
    value.installLockfile
  );
}

/**
 * Inspect dependency readiness without hydrating or mutating the worktree.
 *
 * This is intentionally separate from the cached state file: a command may
 * start after a successful preflight while another process removes or
 * partially materializes a shared dependency cache. Command gates use this
 * read-only probe to decide whether one bounded environment repair is safe.
 */
export function inspectToolchainReadiness({
  root = process.cwd(),
  profile = ALL_PROFILE_ID,
} = {}) {
  const resolvedRoot = path.resolve(root);
  if (!SUPPORTED_PROFILES.includes(profile)) {
    fail(
      EXIT_CODES.CONTRACT,
      `Profile không hỗ trợ: ${profile}. Chọn một trong: ${SUPPORTED_PROFILES.join(', ')}.`,
    );
  }

  if (profile === ALL_PROFILE_ID) {
    const profiles = [PROFILE_ID, FLUTTER_PROFILE_ID].map((profileId) => {
      const readiness = readinessForProfile(resolvedRoot, profileId);
      return {
        profile: profileId,
        ready: isReadyForProfile(readiness, profileId),
        readiness,
      };
    });
    return {
      profile: ALL_PROFILE_ID,
      ready: profiles.every((entry) => entry.ready),
      profiles,
    };
  }

  const readiness = readinessForProfile(resolvedRoot, profile);
  return {
    profile,
    ready: isReadyForProfile(readiness, profile),
    readiness,
  };
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
    recoveries: [],
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
  if (stepResult?.recovery?.status === 'failed') return false;
  if (
    stepResult?.recovery?.status === 'quarantined' &&
    isNodeModulesDirectoryConflict(stepResult)
  ) {
    return false;
  }
  if (isRetryablePrismaFailure(stepResult)) return true;
  if (!['nestjs-npm-ci', 'flutter-pub-get'].includes(stepResult?.id)) {
    return false;
  }
  return /(?:EINTEGRITY|ECONNRESET|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|ENOENT|ENOTEMPTY|EPERM|EBUSY|MODULE_NOT_FOUND|cannot find module|directory not empty|package .* not found|failed to materialize|failed to load)/i.test(
    String(stepResult.error || ''),
  );
}

function retryReason(stepResult) {
  if (isRetryablePrismaFailure(stepResult)) return 'transient-prisma-module-load';
  return 'transient-dependency-materialization';
}

function prepareSingleProfileUnlocked({
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
  const recoveryPaths = [];
  let attempt = 0;
  while (attempt < 2) {
    attempt += 1;
    let retry = false;
    for (const step of steps) {
      const rawStepResult = runHydrationStep(
        resolvedRoot,
        step,
        runStepFn,
        recoveryPaths,
      );
      if (rawStepResult?.recovery) {
        result.recoveries.push({
          step: step.id,
          attempt,
          ...rawStepResult.recovery,
        });
      }
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
        result.error =
          stepResult.error ||
          `${step.id} không hoàn tất với exit code ${stepResult.exitCode ?? 'unknown'}.`;
        result.readiness = readinessForProfile(resolvedRoot, profile);
        return { exitCode: EXIT_CODES.ENVIRONMENT, result };
      }
    }
    if (!retry) break;
  }

  result.readiness = readinessForProfile(resolvedRoot, profile);
  if (!isReadyForProfile(result.readiness, profile)) {
    result.status = 'environment-failure';
    result.error = `Profile ${profile} chưa đạt readiness sau khi hydrate.`;
    return { exitCode: EXIT_CODES.ENVIRONMENT, result };
  }
  const recoveryCleanupFailures = cleanupNodeModulesRecovery(
    resolvedRoot,
    recoveryPaths,
  );
  if (recoveryCleanupFailures.length > 0) {
    result.status = 'environment-failure';
    result.error =
      'Đã hydrate dependency nhưng không dọn được quarantine node_modules; ' +
      'đóng process đang giữ file rồi chạy lại preflight:\n' +
      recoveryCleanupFailures.join('\n');
    return { exitCode: EXIT_CODES.ENVIRONMENT, result };
  }
  // Flutter materialization is part of the readiness fingerprint. The first
  // fingerprint is captured before pub get, so persist a post-hydration value
  // or the next cached preflight would always rerun once after a cold start.
  const readyFingerprint = toolchainFingerprint(resolvedRoot, profile);
  result.fingerprint = readyFingerprint;
  state.schemaVersion = SCHEMA_VERSION;
  state.profiles = {
    ...(state.profiles || {}),
    [profile]: {
      fingerprint: readyFingerprint,
      ready: true,
      preparedAtUtc: new Date().toISOString(),
    },
  };
  writeState(resolvedRoot, state);
  result.status = 'prepared';
  return { exitCode: EXIT_CODES.PASS, result };
}

function prepareSingleProfile(options = {}) {
  const { resolvedRoot, profile } = options;
  const releaseLease =
    profile === PROFILE_ID || profile === FLUTTER_PROFILE_ID
      ? acquireToolchainLease({ root: resolvedRoot, profile })
      : null;
  try {
    return prepareSingleProfileUnlocked(options);
  } finally {
    releaseLease?.();
  }
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
    let prepared;
    try {
      prepared = prepareSingleProfile({
        resolvedRoot,
        profile: profileId,
        dryRun,
        force,
        runStepFn,
      });
    } catch (error) {
      const code =
        error instanceof PreparationError ? error.code : EXIT_CODES.ENVIRONMENT;
      prepared = {
        exitCode: code,
        result: {
          schemaVersion: SCHEMA_VERSION,
          profile: profileId,
          statePath: STATE_PATH,
          dryRun,
          forced: force,
          status: 'environment-failure',
          error: sanitizeDiagnostic(error?.message || error, resolvedRoot),
          readiness: null,
          steps: [],
          retries: [],
          recoveries: [],
        },
      };
    }
    profiles.push(prepared);
  }
  const failed = profiles.find((entry) => entry.exitCode !== EXIT_CODES.PASS);
  const failures = profiles
    .filter((entry) => entry.exitCode !== EXIT_CODES.PASS)
    .map((entry) => ({
      profile: entry.result.profile,
      code: entry.exitCode,
      error:
        entry.result.error ||
        `Profile ${entry.result.profile} không đạt readiness.`,
    }));
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
      ...(failures.length > 0
        ? {
            error: failures
              .map((failure) => `${failure.profile}: ${failure.error}`)
              .join('\n'),
            failures,
          }
        : {}),
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
