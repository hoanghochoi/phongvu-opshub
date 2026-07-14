import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function text(relativePath) {
  return readFile(path.join(root, relativePath), 'utf8');
}

async function filesBelow(relativeDirectory) {
  const directory = path.join(root, relativeDirectory);
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const relativePath = path.join(relativeDirectory, entry.name);
      return entry.isDirectory() ? filesBelow(relativePath) : [relativePath];
    }),
  );
  return nested.flat();
}

function contains(source, expected, label) {
  assert.ok(source.includes(expected), `${label}: missing ${expected}`);
}

function excludes(source, forbidden, label) {
  assert.ok(!source.includes(forbidden), `${label}: still contains ${forbidden}`);
}

function assertVersionAtLeast(actual, minimum, label) {
  const parse = (value) => String(value).replace(/^v/, '').split('.').slice(0, 3).map(Number);
  const actualParts = parse(actual);
  const minimumParts = parse(minimum);
  assert.equal(actualParts.length, 3, `${label}: invalid version ${actual}`);
  assert.ok(actualParts.every(Number.isInteger), `${label}: invalid version ${actual}`);
  const comparison = actualParts.findIndex((part, index) => part !== minimumParts[index]);
  assert.ok(
    comparison === -1 || actualParts[comparison] > minimumParts[comparison],
    `${label}: ${actual} is below ${minimum}`,
  );
}

function goModuleVersion(goMod, moduleName) {
  const line = goMod
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find((value) => value.startsWith(`${moduleName} `));
  assert.ok(line, `Go module version missing: ${moduleName}`);
  return line.split(/\s+/)[1];
}

function extractFunction(source, functionName) {
  const start = source.indexOf(`function ${functionName}(`);
  assert.notEqual(start, -1, `missing function ${functionName}`);
  const next = source.indexOf('\n    function ', start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

const [
  caddy,
  productionCompose,
  localCompose,
  backup,
  stagingRefresh,
  manifest,
  gradle,
  updater,
  help,
  download,
  packageJsonText,
  packageLockText,
  goMod,
  goDockerfile,
  productionWorkflow,
  stagingWorkflow,
  codeqlWorkflow,
  windowsMsixWorkflow,
  pubspec,
  robotoLicense,
] = await Promise.all([
  text('deploy/home-server/Caddyfile'),
  text('deploy/home-server/docker-compose.home.yml'),
  text('docker-compose.yml'),
  text('deploy/home-server/backup.sh'),
  text('deploy/staging/refresh-sanitized-db.sh'),
  text('android/app/src/main/AndroidManifest.xml'),
  text('android/app/build.gradle.kts'),
  text('lib/features/app_update/data/app_self_update_service.dart'),
  text('deploy/home-server/help.html'),
  text('deploy/home-server/download.html'),
  text('backend-nest/package.json'),
  text('backend-nest/package-lock.json'),
  text('backend-go/go.mod'),
  text('backend-go/Dockerfile'),
  text('.github/workflows/deploy-opshub.yml'),
  text('.github/workflows/deploy-opshub-staging.yml'),
  text('.github/workflows/codeql.yml'),
  text('.github/workflows/build-windows-msix.yml'),
  text('pubspec.yaml'),
  text('fonts/Roboto-LICENSE.txt'),
]);

contains(caddy, '@insecure_edge_request header X-Forwarded-Proto http', 'Caddy HTTPS redirect');
contains(caddy, 'Content-Security-Policy "', 'Caddy enforced CSP');
contains(caddy, "object-src 'none'", 'Caddy CSP object restriction');
contains(caddy, "frame-ancestors 'self'", 'Caddy CSP frame restriction');
excludes(caddy, 'Content-Security-Policy-Report-Only', 'Caddy report-only CSP');
contains(caddy, 'X-Content-Type-Options "nosniff"', 'Caddy static headers');
contains(
  caddy,
  'Strict-Transport-Security "max-age=31536000; includeSubDomains"',
  'Caddy HSTS',
);
for (const [expected, label] of [
  ['log legacy_uploads {', 'legacy upload named access logger'],
  ['no_hostname', 'legacy upload route-only logger'],
  ['request>uri delete', 'legacy upload query redaction'],
  ['request>remote_ip delete', 'legacy upload remote IP redaction'],
  ['request>client_ip delete', 'legacy upload client IP redaction'],
  ['request>headers delete', 'legacy upload header redaction'],
  ['legacy_path hash', 'legacy upload path hashing'],
  ['log_name @legacy_upload_request legacy_uploads', 'legacy upload log routing'],
]) {
  contains(caddy, expected, label);
}

for (const value of ['max-size:', 'max-file:', 'no-new-privileges:true', 'cap_drop:', 'read_only: true']) {
  contains(productionCompose, value, 'production Compose hardening');
}
contains(productionCompose, '@sha256:', 'production image digest pins');
contains(productionCompose, 'target: ops', 'one-shot ops image');
contains(productionCompose, 'maintenance:', 'maintenance service');
contains(productionCompose, 'REDIS_PASSWORD:', 'production Redis authentication');
contains(productionCompose, 'WS_ALLOW_LEGACY_JWT:', 'realtime legacy JWT gate');
contains(productionCompose, 'WS_MAX_CONNECTIONS_PER_USER: ${WS_MAX_CONNECTIONS_PER_USER:-12}', 'realtime per-user connection budget');
contains(productionCompose, 'REALTIME_LEGACY_JWT_SECRET', 'isolated realtime rollback secret');
contains(productionCompose, 'explicit loopback binding', 'origin loopback gate');
contains(productionCompose, '/private-media:/data/private-media', 'private media API volume');
excludes(productionCompose, '/private-media:/srv/', 'private media Caddy exposure');

contains(localCompose, '127.0.0.1:5432:5432', 'local PostgreSQL binding');
contains(localCompose, '127.0.0.1:6379:6379', 'local Redis binding');
contains(localCompose, '--requirepass', 'local Redis authentication');
contains(localCompose, '@sha256:', 'local infrastructure image digest pins');
excludes(localCompose, 'opshub_password', 'local Compose literal password');

contains(backup, 'umask 077', 'backup permissions');
contains(backup, 'BACKUP_AGE_RECIPIENT', 'backup encryption');
contains(backup, 'private-media.tar.gz', 'private media backup');
contains(backup, 'Refusing to create an unencrypted backup.', 'backup fail-closed behavior');
contains(backup, 'chmod 0600', 'backup file mode');
contains(backup, 'flock -n', 'backup overlap lock');
contains(backup, '.partial', 'backup atomic staging directory');
contains(backup, 'read_env_value()', 'backup dotenv allowlist parser');
excludes(backup, '. "$ENV_FILE"', 'backup shell-sourced dotenv');
excludes(backup, 'source "$ENV_FILE"', 'backup shell-sourced dotenv');

excludes(stagingRefresh, 'STAGING_TEST_PASSWORD=$(sq', 'staging secret command-line forwarding');
contains(stagingRefresh, 'chmod 0600 "$backup_file"', 'staging pre-refresh backup mode');

contains(manifest, 'android:allowBackup="false"', 'Android backup policy');
contains(manifest, 'android:dataExtractionRules="@xml/data_extraction_rules"', 'Android extraction policy');
contains(gradle, 'releaseTaskRequested && !hasReleaseSigning', 'Android release signing gate');
excludes(gradle, 'signingConfigs.getByName("debug")', 'Android debug-signing fallback');

contains(updater, "uri.scheme.toLowerCase() != 'https'", 'updater HTTPS policy');
contains(updater, "_trustedPackageHost = 'opshub.hoanghochoi.com'", 'updater host allowlist');
contains(updater, 'request.followRedirects = false', 'updater redirect policy');
contains(updater, 'WINDOWS_UPDATE_SIGNER_SHA256', 'Windows signer pin');
contains(updater, '_maxPackageBytes', 'updater package hard cap');

contains(productionWorkflow, '--no-web-resources-cdn', 'production local Flutter web resources');
contains(
  productionWorkflow,
  'required_runtime_env_keys=(',
  'production required runtime env gate',
);
contains(
  productionWorkflow,
  'PRIVATE_MEDIA_BASE_DIR',
  'production private media storage env gate',
);
contains(
  productionWorkflow,
  'PRIVATE_MEDIA_PUBLIC_BASE_URL',
  'production private media public URL env gate',
);
contains(
  productionWorkflow,
  'REDIS_PASSWORD must contain at least 32 characters.',
  'production Redis password strength gate',
);
contains(
  productionWorkflow,
  'sudo install -d -o "$runtime_uid" -g "$runtime_gid" -m 0770',
  'production writable volume ownership gate',
);
contains(
  productionWorkflow,
  'compose_cmd up -d --force-recreate --wait --wait-timeout 120 redis',
  'production coordinated Redis authentication rollout',
);
contains(
  productionWorkflow,
  'redis api realtime caddy',
  'production rollback includes Redis configuration',
);
contains(stagingWorkflow, '--no-web-resources-cdn', 'staging local Flutter web resources');
contains(stagingWorkflow, 'secrets.CF_ACCESS_CLIENT_ID', 'staging Access client ID secret');
contains(stagingWorkflow, 'secrets.CF_ACCESS_CLIENT_SECRET', 'staging Access client secret');
contains(stagingWorkflow, 'CF-Access-Client-Id:', 'staging Access client ID header');
contains(stagingWorkflow, 'CF-Access-Client-Secret:', 'staging Access client secret header');
for (const expected of [
  'javascript-typescript',
  '- go',
  'security-events: write',
  'queries: security-extended',
  'github/codeql-action/init@1ad29ea4a422cce9a242a9fae469541dcd08addc',
  'github/codeql-action/autobuild@1ad29ea4a422cce9a242a9fae469541dcd08addc',
  'github/codeql-action/analyze@1ad29ea4a422cce9a242a9fae469541dcd08addc',
]) {
  contains(codeqlWorkflow, expected, 'CodeQL security workflow');
}
excludes(codeqlWorkflow, 'github/codeql-action/init@v', 'unpinned CodeQL init');
excludes(codeqlWorkflow, 'github/codeql-action/analyze@v', 'unpinned CodeQL analyze');
const checkoutSha = '9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0';
for (const [workflow, label] of [
  [productionWorkflow, 'production workflow'],
  [stagingWorkflow, 'staging workflow'],
  [codeqlWorkflow, 'CodeQL workflow'],
  [windowsMsixWorkflow, 'Windows MSIX workflow'],
]) {
  contains(workflow, `actions/checkout@${checkoutSha}`, `${label} checkout pin`);
  excludes(workflow, 'actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5', `${label} deprecated checkout pin`);
  excludes(workflow, 'actions/checkout@v', `${label} floating checkout version`);
}
contains(stagingWorkflow, '[[ "$status" == 2* ]]', 'staging Access 2xx verification gate');
contains(stagingWorkflow, "^www-authenticate: Cloudflare-Access ", 'staging Access challenge verification');
contains(stagingWorkflow, 'redirect_url=%2Fdownload', 'staging Access download redirect verification');
contains(pubspec, '- family: Roboto', 'local Flutter Roboto fallback');
contains(pubspec, 'fonts/Roboto-Regular.ttf', 'local Flutter Roboto asset');
contains(robotoLicense, 'Apache License', 'Roboto license attribution');

const controllerPaths = (await filesBelow('backend-nest/src')).filter((file) =>
  file.endsWith('.controller.ts'),
);
for (const controllerPath of controllerPaths) {
  const controller = await text(controllerPath);
  if (controller.includes('@RequireFeature')) {
    contains(controller, '@UseGuards(', `${controllerPath} guard declaration`);
    contains(controller, "AuthGuard('jwt')", `${controllerPath} JWT guard`);
    contains(controller, 'FeatureGuard', `${controllerPath} feature guard`);
  }
  if (/req(?:uest)?\.user/.test(controller)) {
    assert.ok(
      controller.includes("AuthGuard('jwt')") ||
        controller.includes('OptionalJwtAuthGuard'),
      `${controllerPath}: req.user is used without a JWT guard`,
    );
  }
}

contains(help, 'isSafeHelpDocFile', 'Help document allowlist');
contains(help, "raw.startsWith('//')", 'Help protocol-relative URL rejection');
contains(download, 'sanitizeDownloadUrl', 'Download URL allowlist');
contains(download, 'allowedLocations.some', 'Download origin and path allowlist');
contains(
  download,
  "hostname === 'opshub-staging.hoanghochoi.com'",
  'Download staging host restriction',
);

const helpUrlPolicy = extractFunction(help, 'sanitizeUrl');
const helpUrlSandbox = {
  window: { location: { origin: 'https://opshub.hoanghochoi.com' } },
  helpBasePath: '/help',
  escapeAttribute: (value) => value,
};
const sanitizeHelpUrl = (input) =>
  vm.runInNewContext(`${helpUrlPolicy}; sanitizeUrl(input)`, {
    ...helpUrlSandbox,
    input,
    URL,
  });
assert.equal(sanitizeHelpUrl('//evil.test/a'), '#');
assert.equal(sanitizeHelpUrl('http://opshub.hoanghochoi.com/help'), '#');
assert.equal(sanitizeHelpUrl('https://evil.test/help'), '#');
assert.equal(sanitizeHelpUrl('/help/assets/a.png'), '/help/assets/a.png');
assert.equal(sanitizeHelpUrl('guide.md'), '/help/guide.md');

const helpDocPolicy = extractFunction(help, 'isSafeHelpDocFile');
const safeHelpDoc = (input) =>
  vm.runInNewContext(`${helpDocPolicy}; isSafeHelpDocFile(input)`, { input });
assert.equal(safeHelpDoc('getting-started.md'), true);
assert.equal(safeHelpDoc('../secret.md'), false);
assert.equal(safeHelpDoc('/absolute.md'), false);

const downloadUrlPolicy = extractFunction(download, 'sanitizeDownloadUrl');
const sanitizeDownloadUrl = (
  input,
  {
    downloadsBasePath = '/downloads',
    origin = 'https://opshub.hoanghochoi.com',
    hostname = 'opshub.hoanghochoi.com',
  } = {},
) =>
  vm.runInNewContext(`${downloadUrlPolicy}; sanitizeDownloadUrl(input)`, {
    input,
    downloadsBasePath,
    URL,
    window: { location: { origin, hostname } },
  });
assert.equal(sanitizeDownloadUrl('javascript:alert(1)'), '');
assert.equal(sanitizeDownloadUrl('https://evil.test/downloads/a.apk'), '');
assert.equal(sanitizeDownloadUrl('https://opshub.hoanghochoi.com/other/a.apk'), '');
assert.equal(
  sanitizeDownloadUrl('/downloads/a.apk'),
  'https://opshub.hoanghochoi.com/downloads/a.apk',
);
assert.equal(
  sanitizeDownloadUrl(
    '/staging-download/downloads/a.apk',
    { downloadsBasePath: '/staging-download/downloads' },
  ),
  'https://opshub.hoanghochoi.com/staging-download/downloads/a.apk',
);
assert.equal(
  sanitizeDownloadUrl(
    'https://opshub.hoanghochoi.com/staging-download/downloads/a.apk',
    {
      origin: 'https://opshub-staging.hoanghochoi.com',
      hostname: 'opshub-staging.hoanghochoi.com',
    },
  ),
  'https://opshub.hoanghochoi.com/staging-download/downloads/a.apk',
);
assert.equal(
  sanitizeDownloadUrl(
    'https://opshub.hoanghochoi.com/downloads/a.apk',
    {
      origin: 'https://opshub-staging.hoanghochoi.com',
      hostname: 'opshub-staging.hoanghochoi.com',
    },
  ),
  '',
);
assert.equal(
  sanitizeDownloadUrl(
    'https://opshub.hoanghochoi.com/staging-download/downloads/a.apk#bad',
    {
      origin: 'https://opshub-staging.hoanghochoi.com',
      hostname: 'opshub-staging.hoanghochoi.com',
    },
  ),
  '',
);

const packageJson = JSON.parse(packageJsonText);
const packageLock = JSON.parse(packageLockText);
assert.equal(
  packageJson.scripts['security:audit-legacy-upload-access'],
  'node scripts/audit-legacy-upload-access.mjs',
);
assert.equal(packageJson.dependencies['@nestjs/platform-express'], '^11.1.28');
assert.equal(packageJson.dependencies.nodemailer, '^9.0.3');
assert.equal(packageJson.overrides.hono, '4.12.29');
assert.equal(packageJson.overrides.qs, '6.15.3');
for (const [lockPath, minimum, label] of [
  ['node_modules/@babel/core', '7.29.6', '@babel/core security patch'],
  ['node_modules/form-data', '4.0.6', 'form-data security patch'],
  ['node_modules/js-yaml', '4.2.0', 'js-yaml v4 security patch'],
  ['node_modules/@istanbuljs/load-nyc-config/node_modules/js-yaml', '3.15.0', 'js-yaml v3 security patch'],
  ['node_modules/@typescript-eslint/typescript-estree/node_modules/brace-expansion', '5.0.7', 'brace-expansion TypeScript security patch'],
  ['node_modules/glob/node_modules/brace-expansion', '5.0.7', 'brace-expansion glob security patch'],
]) {
  assertVersionAtLeast(packageLock.packages[lockPath]?.version, minimum, label);
}
assertVersionAtLeast(
  goModuleVersion(goMod, 'golang.org/x/crypto'),
  '0.52.0',
  'golang.org/x/crypto security patch',
);
assertVersionAtLeast(
  goModuleVersion(goMod, 'golang.org/x/net'),
  '0.55.0',
  'golang.org/x/net security patch',
);
contains(goDockerfile, 'FROM golang:1.25.12-alpine3.24@sha256:', 'patched pinned Go build toolchain');
assert.equal(
  packageJson.dependencies.xlsx,
  'https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz',
  'xlsx must stay pinned to the patched official SheetJS CE tarball',
);

console.log('Platform security contract checks passed.');
