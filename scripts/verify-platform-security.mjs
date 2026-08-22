import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function text(relativePath) {
  const source = await readFile(path.join(root, relativePath), 'utf8');
  return source.replace(/\r\n?/g, '\n');
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

function assertWorkflowRunExpressionLengths(source, label) {
  const lines = source.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const runMatch = lines[index].match(/^(\s*)run:\s*\|[+-]?\s*$/);
    if (!runMatch) continue;

    const runIndent = runMatch[1].length;
    const body = [];
    for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
      const line = lines[cursor];
      const indentation = line.match(/^(\s*)/)[1].length;
      if (line.trim() && indentation <= runIndent) break;
      body.push(line);
    }

    const runSource = body.join('\n');
    if (!runSource.includes('${{')) continue;
    assert.ok(
      runSource.length <= 20000,
      `${label}: interpolated run block at line ${index + 1} is ${runSource.length} characters`,
    );
  }
}

const [
  caddy,
  productionCompose,
  blueGreenCaddyTemplate,
  blueGreenCompose,
  localCompose,
  backup,
  stagingRefresh,
  manifest,
  gradle,
  updater,
  windowsSigner,
  throttlerGuard,
  stagingLoadUsers,
  stagingLoadWrapper,
  runtimeReleaseBuilder,
  productionOriginVerifier,
  productionRollbackRuntime,
  productionRollbackEnv,
  productionCloudflareTransaction,
  productionBaselineVerifier,
  productionManifestVerifier,
  productionRuntimeIdentity,
  productionBaselineReconciler,
  stagingLoadProfile,
  stagingRateLimitSemantics,
  help,
  download,
  packageJsonText,
  packageLockText,
  goMod,
  goDockerfile,
  productionWorkflow,
  stagingWorkflow,
  codeqlWorkflow,
  pubspec,
  robotoLicense,
  privateMediaHeaders,
  homeScreen,
  profileScreen,
  warrantyDetailsScreen,
  feedbackAdminScreen,
  auditPrivateMedia,
  privateMediaReferenceAudit,
  securityManualActions,
] = await Promise.all([
  text('deploy/home-server/Caddyfile'),
  text('deploy/home-server/docker-compose.home.yml'),
  text('deploy/home-server/Caddyfile.bluegreen.template'),
  text('deploy/home-server/docker-compose.blue-green.yml'),
  text('docker-compose.yml'),
  text('deploy/home-server/backup.sh'),
  text('deploy/staging/refresh-sanitized-db.sh'),
  text('android/app/src/main/AndroidManifest.xml'),
  text('android/app/build.gradle.kts'),
  text('lib/features/app_update/data/app_self_update_service.dart'),
  text('scripts/sign-windows-artifact.ps1'),
  text('backend-nest/src/common/user-aware-throttler.guard.ts'),
  text('backend-nest/scripts/manage-staging-load-users.mjs'),
  text('deploy/staging/manage-load-users.sh'),
  text('scripts/build-runtime-release.mjs'),
  text('deploy/home-server/verify-production-origin.sh'),
  text('deploy/home-server/rollback-runtime.sh'),
  text('deploy/home-server/prepare-rollback-env.sh'),
  text('deploy/home-server/cloudflare-ingress-transaction.sh'),
  text('deploy/home-server/verify-production-baseline.sh'),
  text('deploy/home-server/verify-release-manifest.sh'),
  text('deploy/home-server/production-runtime-identity.sh'),
  text('deploy/home-server/reconcile-production-baseline.sh'),
  text('scripts/load/opshub-staging-home-100qps.js'),
  text('scripts/load/opshub-staging-rate-limit-semantics.js'),
  text('deploy/home-server/help.html'),
  text('deploy/home-server/download.html'),
  text('backend-nest/package.json'),
  text('backend-nest/package-lock.json'),
  text('backend-go/go.mod'),
  text('backend-go/Dockerfile'),
  text('.github/workflows/deploy-opshub.yml'),
  text('.github/workflows/deploy-opshub-staging.yml'),
  text('.github/workflows/codeql.yml'),
  text('pubspec.yaml'),
  text('fonts/Roboto-LICENSE.txt'),
  text('lib/core/network/private_media_headers.dart'),
  text('lib/features/home/presentation/screens/home_screen.dart'),
  text('lib/features/auth/presentation/screens/profile_screen.dart'),
  text('lib/features/warranty/presentation/screens/warranty_details_screen.dart'),
  text('lib/features/admin/presentation/screens/feedback_admin_screen.dart'),
  text('backend-nest/scripts/audit-private-media.mjs'),
  text('backend-nest/scripts/private-media-reference-audit.mjs'),
  text('app-security-manual-actions-12072026.md'),
]);
const helpProductContract = await text('docs/product/help.md');
const backendPlatformContract = await text('docs/product/backend-platform.md');
const helpDeployStateProbe = await text(
  'backend-nest/src/help-content/help-content-deploy-state.ts',
);
const cloudflarePublicProbe = await text(
  'deploy/home-server/cloudflare-public-probe.sh',
);

assertWorkflowRunExpressionLengths(productionWorkflow, 'production workflow');
assertWorkflowRunExpressionLengths(stagingWorkflow, 'staging workflow');
contains(
  runtimeReleaseBuilder,
  'OPSHUB_INCLUDE_STAGING_LOAD_TOOLS',
  'runtime release staging load tool opt-in',
);
contains(
  stagingWorkflow,
  'OPSHUB_INCLUDE_STAGING_LOAD_TOOLS: "true"',
  'staging workflow opts into staging load tools',
);
excludes(
  productionWorkflow,
  'OPSHUB_INCLUDE_STAGING_LOAD_TOOLS',
  'production workflow staging load tool opt-in',
);

contains(
  throttlerGuard,
  '`${name}:${method}:${routePath}:${suffix}`',
  'principal storage key method/path isolation',
);
const throttlerBodyEmailIndex = throttlerGuard.indexOf(
  "this.valueFromRecord(this.bodyRecord(req.body), 'email')",
);
const throttlerQueryEmailIndex = throttlerGuard.indexOf(
  "this.valueFromRecord(req.query, 'email')",
);
assert.ok(
  throttlerBodyEmailIndex >= 0 &&
    throttlerQueryEmailIndex > throttlerBodyEmailIndex,
  'operation body email must take precedence over a rotatable query email',
);

contains(caddy, '@insecure_edge_request header X-Forwarded-Proto http', 'Caddy HTTPS redirect');
contains(caddy, 'trusted_proxies static private_ranges', 'Caddy trusted Cloudflare Tunnel hop');
contains(caddy, 'trusted_proxies_strict', 'Caddy strict trusted proxy parsing');
contains(caddy, 'client_ip_headers CF-Connecting-IP', 'Caddy Cloudflare client IP source');
contains(caddy, 'header_up X-Forwarded-For {client_ip}', 'Caddy normalized forwarded client IP');
contains(caddy, 'header_up X-Real-IP {client_ip}', 'Caddy normalized real client IP');
assert.match(
  caddy,
  /handle \/download\/ \{[\s\S]*?rewrite \* \/download[\s\S]*?redir \* \{uri\} 308/,
  'Caddy canonical download redirect preserves query',
);
assert.match(
  caddy,
  /handle \/help\/ \{[\s\S]*?rewrite \* \/help[\s\S]*?redir \* \{uri\} 308/,
  'Caddy canonical help redirect preserves query',
);
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
  ['log {\n    output discard\n  }', 'default access logger discard sink'],
  ['log legacy_uploads {', 'legacy upload named access logger'],
  ['no_hostname', 'legacy upload route-only logger'],
  [
    'output file /data/legacy-uploads-access.log {',
    'persistent legacy upload access log',
  ],
  ['mode 0600', 'private legacy upload log permissions'],
  ['roll_size 10MiB', 'bounded legacy upload log size'],
  ['roll_keep 14', 'bounded legacy upload log file count'],
  ['roll_keep_for 336h', 'fourteen-day legacy upload observation history'],
  ['request>uri delete', 'legacy upload query redaction'],
  ['request>remote_ip delete', 'legacy upload remote IP redaction'],
  ['request>client_ip delete', 'legacy upload client IP redaction'],
  ['request>headers delete', 'legacy upload header redaction'],
  ['legacy_path hash', 'legacy upload path hashing'],
  ['log_name @legacy_upload_request legacy_uploads', 'legacy upload log routing'],
]) {
  contains(caddy, expected, label);
}
const apiCaddyMarker = '\n# The API hostname is an exact namespace.';
const legacyCaddyMarker = '\n# Legacy web host bridge.';
const apiCaddyStart = caddy.indexOf(apiCaddyMarker);
const legacyCaddyStart = caddy.indexOf(legacyCaddyMarker);
assert.ok(apiCaddyStart >= 0 && legacyCaddyStart > apiCaddyStart, 'Exact API Caddy site marker is missing');
const apiCaddy = caddy.slice(apiCaddyStart, legacyCaddyStart);
assert.equal(
  apiCaddy.split('dynamic a api 3000').length - 1,
  3,
  'API Caddy site must discover every scaled API replica for BIDV and REST routes',
);
assert.equal(
  apiCaddy.split('lb_policy round_robin').length - 1,
  3,
  'API Caddy site must distribute BIDV and REST routes across discovered replicas',
);
excludes(caddy, 'reverse_proxy api:3000', 'single logical API upstream');

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
contains(
  productionCompose,
  '/downloads/help:/app/docs/help:ro',
  'production API shared Help source',
);
excludes(
  productionCompose,
  '../../docs/help:/app/docs/help:ro',
  'immutable production release Help mount',
);

contains(
  blueGreenCompose,
  'profiles: [bluegreen-candidate]',
  'blue-green candidate profile is opt-in',
);
contains(
  blueGreenCompose,
  'opshub_bluegreen_shared:',
  'blue-green shared network declaration',
);
contains(blueGreenCompose, 'external: true', 'blue-green shared network is pre-created');
contains(blueGreenCompose, 'cap_drop: [ALL]', 'blue-green candidate capability drop');
contains(blueGreenCompose, 'read_only: true', 'blue-green candidate read-only root');
contains(
  blueGreenCompose,
  '/downloads/help:/app/docs/help:ro',
  'blue-green shared Help source',
);
excludes(
  blueGreenCompose,
  '../../docs/help:/app/docs/help:ro',
  'immutable blue-green release Help mount',
);
contains(
  blueGreenCompose,
  'no-new-privileges:true',
  'blue-green candidate no-new-privileges',
);
excludes(blueGreenCompose, "  caddy:", 'blue-green overlay does not restart Caddy');
excludes(blueGreenCompose, "    ports:", 'blue-green candidates do not publish ports');
contains(
  blueGreenCaddyTemplate,
  '{{API_UPSTREAM}}',
  'blue-green Caddy API placeholder',
);
contains(
  blueGreenCaddyTemplate,
  '{{WS_UPSTREAM}}',
  'blue-green Caddy WebSocket placeholder',
);

contains(
  privateMediaHeaders,
  'if (!isProtectedPrivateMediaUrl(url, apiBaseUrl: apiBaseUrl))',
  'private media credential scope gate',
);
contains(
  privateMediaHeaders,
  'if (target.origin != base.origin) return false;',
  'private media exact-origin credential gate',
);
contains(
  privateMediaHeaders,
  "target.path.startsWith('$basePath/media/')",
  'private media API-path credential gate',
);
contains(
  homeScreen,
  'headers: privateMediaHeaders(avatarUrl)',
  'Home avatar dual-read headers',
);
contains(
  profileScreen,
  'headers: privateMediaHeaders(avatarUrl!)',
  'profile avatar dual-read headers',
);
contains(
  warrantyDetailsScreen,
  'httpHeaders: privateMediaHeaders(imageSource)',
  'warranty image dual-read headers',
);
assert.ok(
  feedbackAdminScreen.split('httpHeaders: privateMediaHeaders(imageUrl)').length -
    1 >=
    2,
  'feedback thumbnail and preview must both use dual-read headers',
);
contains(
  auditPrivateMedia,
  'parsePrivateMediaAuditArgs',
  'private media audit fail-closed CLI parser',
);
contains(
  auditPrivateMedia,
  'legacyReferencesClear: legacyReferencesTotal === 0',
  'private media aggregate legacy reference verdict',
);
contains(
  auditPrivateMedia,
  'failOnLegacy && !report.legacyReferencesClear',
  'private media post-migration legacy fail gate',
);
contains(
  privateMediaReferenceAudit,
  "const supported = new Set(['--strict', '--fail-on-legacy'])",
  'private media audit supported argument allowlist',
);
contains(
  privateMediaReferenceAudit,
  "if (matchesRoute(target, legacyBase, legacyBase.pathname)) return 'legacy';",
  'private media exact legacy route classification',
);
assert.ok(
  securityManualActions.split(
    '--profile maintenance run --rm -T --build maintenance',
  ).length -
    1 >=
    5,
  'private media maintenance commands must rebuild the current release image',
);
contains(
  securityManualActions,
  '--profile maintenance run --rm -T --build --no-deps maintenance',
  'legacy telemetry audit rebuilds the current release image',
);
contains(
  securityManualActions,
  '/srv/opshub/caddy/data/legacy-uploads-access.log*',
  'legacy telemetry cutover reads persistent and rolled files',
);
contains(
  securityManualActions,
  'gzip -cd -- "$f"',
  'legacy telemetry cutover reads compressed rotations server-side',
);
contains(
  securityManualActions,
  'security:audit-legacy-upload-access -- --strict --fail-on-hits',
  'legacy telemetry cutover fails when any hashed hit remains',
);
excludes(
  securityManualActions,
  'docker logs --since 168h',
  'legacy telemetry cutover must not rely on ephemeral Docker logs',
);
excludes(
  securityManualActions,
  'security:audit-legacy-upload-access -- --strict --fail-on-hits < /dev/null',
  'legacy telemetry input pipe must not be replaced with empty stdin',
);
contains(
  securityManualActions,
  '< /dev/null',
  'maintenance commands close stdin for remote execution',
);

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
contains(updater, "'phongvu.work'", 'production updater host allowlist');
contains(updater, "'staging.phongvu.work'", 'staging updater host allowlist');
contains(updater, "'opshub.hoanghochoi.com'", 'production legacy updater bridge');
contains(updater, "'opshub-staging.hoanghochoi.com'", 'staging legacy updater bridge');
contains(updater, 'isTrustedPackageUriForTesting(uri, isStaging: AppBrand.isStaging)', 'build-scoped updater host policy');
contains(updater, 'request.followRedirects = false', 'updater redirect policy');
contains(updater, 'final actual = await _sha256Of(file);', 'updater SHA-256 verification');
excludes(updater, 'Get-AuthenticodeSignature', 'runtime Authenticode verification');
excludes(updater, 'WINDOWS_UPDATE_SIGNER_SHA256', 'runtime Windows signer pin');
contains(updater, '_maxPackageBytes', 'updater package hard cap');
contains(
  windowsSigner,
  "'/tr', 'http://timestamp.digicert.com'",
  "Windows RFC 3161 signing timestamp",
);
contains(
  windowsSigner,
  "WaitForExit($TimeoutSeconds * 1000)",
  "Windows signtool timeout",
);
contains(windowsSigner, '$process.Kill($true)', 'Windows signtool timeout kills process tree');
contains(windowsSigner, 'TimeStamperCertificate', 'Windows timestamp verification');
contains(windowsSigner, 'actualPin -notin $trustedPins', 'Windows CI signer pin');
contains(windowsSigner, '*\\x64\\signtool.exe', 'Windows targeted signtool lookup');
excludes(windowsSigner, '-Recurse', 'Windows recursive signtool lookup');
contains(windowsSigner, 'Install-EphemeralSigningTrust', 'Windows ephemeral public trust setup');
contains(windowsSigner, 'StoreName]::TrustedPublisher', 'Windows ephemeral publisher trust');
excludes(windowsSigner, 'certutil.exe', 'Windows signer root trust mutation');
excludes(windowsSigner, "'-addstore', 'Root'", 'Windows signer root trust mutation');
excludes(windowsSigner, 'StoreName]::Root', 'Windows signer root trust mutation');
excludes(windowsSigner, 'StoreName]::CertificateAuthority', 'Windows ephemeral CA trust');
contains(
  windowsSigner,
  '$isPinnedSelfSignedTrustError',
  'Windows pinned self-signed signer trust status handling',
);
contains(
  windowsSigner,
  "$statusName -eq 'UnknownError'",
  'Windows pinned self-signed signer UnknownError handling',
);
contains(
  windowsSigner,
  "if ($statusName -ne 'Valid' -and -not $isPinnedSelfSignedTrustError)",
  'Windows strict Authenticode status for non-pinned signers',
);
contains(
  windowsSigner,
  "'verify', '/pa', '/all', '/v'",
  "Windows timestamped signature verification",
);
excludes(windowsSigner, '$isPinnedUntrustedRoot', 'Windows untrusted pinned signer bypass');

for (const [workflow, label] of [
  [productionWorkflow, 'production workflow'],
  [stagingWorkflow, 'staging workflow'],
]) {
  excludes(
    workflow,
    '--dart-define "WINDOWS_UPDATE_SIGNER_SHA256=',
    `${label} runtime signer build define`,
  );
  contains(workflow, 'WINDOWS_SIGNING_PFX_BASE64', `${label} signing PFX gate`);
  contains(workflow, 'WINDOWS_SIGNING_PFX_PASSWORD', `${label} signing password gate`);
  contains(workflow, 'timeout-minutes: 6', `${label} Windows signing timeout`);
  contains(workflow, 'WINDOWS_UPDATE_SIGNER_SHA256', `${label} CI signer pin`);
  contains(workflow, 'scan-windows-artifact-defender.ps1', `${label} Defender gate`);
}

for (const expected of [
  "OPSHUB_STAGING).toLowerCase() !== 'true'",
  'process.env.OPSHUB_STAGING_LOAD_MAINTENANCE_ENABLED,',
  'PUBLIC_BASE_URL must equal ${REQUIRED_PUBLIC_URL}',
  "SOURCE_EMAIL = 'staging.staff@phongvu.vn'",
  "LOAD_FEATURE_CODES = [",
  "'HOME_DASHBOARD_SALES'",
  "'HOME_DASHBOARD_FINANCE'",
  "status: 'COMPLETE'",
  "dimensionType: 'GLOBAL'",
  "tokenFileMode: '0600'",
  'assertNoBusinessReferences',
  "revokedReason: 'STAGING_LOAD_COMPLETE'",
  "source.role !== 'STAFF'",
  'broadScalarScope',
  'activeOrganizationAssignments !== 0',
  'enabledUserFeatures !== 0',
  'featureRules !== 0',
  'policyRules !== 0',
  'minimal store-only Home/auth/realtime scope',
  'tx.organizationNodeFeatureAssignment.createMany',
  'const note = `staging-load:${runId}`',
  'note,',
  'Required staging Home node feature is disabled',
]) {
  contains(stagingLoadUsers, expected, 'staging synthetic-user safety gate');
}
for (const expected of [
  '--profile maintenance \\',
  'build maintenance',
  'run --rm -T maintenance',
]) {
  contains(stagingLoadWrapper, expected, 'staging load-user wrapper maintenance image freshness');
}
for (const forbidden of [
  'cloneFeatureRule(',
  'clonePolicyRule(',
  'source.organizationAssignments',
  'source.userFeatureAssignments',
  'departmentCode: source.departmentCode',
  'jobRoleCode: source.jobRoleCode',
  'workScopeType: source.workScopeType',
  'regionCode: source.regionCode',
  'areaCode: source.areaCode',
  'organizationNodeId: source.organizationNodeId',
]) {
  excludes(stagingLoadUsers, forbidden, 'staging synthetic-user scope cloning');
}
for (const copiedScalar of [
  'profileCompletedAt: source.profileCompletedAt',
  'branchLockedAt: source.branchLockedAt',
  'storeId: source.storeId',
]) {
  contains(
    stagingLoadUsers,
    copiedScalar,
    'staging synthetic-user minimal scalar clone',
  );
}
const stagingSourceScopeGateIndex = stagingLoadUsers.indexOf(
  'const broadScalarScope',
);
const stagingFirstSyntheticCreateIndex = stagingLoadUsers.indexOf(
  'await tx.user.create',
);
assert.ok(
  stagingSourceScopeGateIndex >= 0 &&
    stagingFirstSyntheticCreateIndex > stagingSourceScopeGateIndex,
  'staging source scope gate must run before the first synthetic user create',
);
for (const expected of [
  'https://api-staging.phongvu.work/v1',
  'wss://api-staging.phongvu.work/v1/ws/v2',
  'targetRps !== 100 || targetSockets !== 60',
  '__ENV.PUBLIC_WS_ENABLED',
  '__ENV.LEGACY_WS_ENABLED',
  'if (slot < 70)',
  'opshub_unexpected_429:',
  'count==0',
  'opshub_http_success:',
  'rate>=0.999',
  'p(95)<=500',
  'p(99)<=1000',
  'opshub_home_summary_duration',
  'opshub_ws_session_held',
  'const RAMP_PREALLOCATED_VUS = 300',
  'preAllocatedVUs: RAMP_PREALLOCATED_VUS',
  'const RAMP_DOWN_PREALLOCATED_VUS = 200',
  'preAllocatedVUs: RAMP_DOWN_PREALLOCATED_VUS',
]) {
  contains(stagingLoadProfile, expected, 'staging Home load-profile safety gate');
}
for (const forbidden of ['http.put(', 'http.patch(', 'http.del(']) {
  excludes(stagingLoadProfile, forbidden, 'staging capacity write request');
}
for (const expected of [
  'preAllocatedVUs: 2',
  'maxVUs: 2',
  'dropped_iterations{scenario:exceed_one_principal}',
]) {
  contains(
    stagingRateLimitSemantics,
    expected,
    'staging rate-limit semantics generator capacity',
  );
}

contains(productionWorkflow, '--no-web-resources-cdn', 'production local Flutter web resources');
contains(productionWorkflow, 'lfs: false', 'production checkout avoids Android LFS download');
contains(productionWorkflow, 'actions/cache@caa296126883cff596d87d8935842f9db880ef25', 'production Windows payment audio cache');
contains(productionWorkflow, "hashFiles('windows/assets/payment_audio/local_preset_speaker_v1/**/manifest.json')", 'production payment audio manifest cache key');
contains(productionWorkflow, 'actions: read', 'production workflow artifact read permission');
contains(productionWorkflow, 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093', 'production staging payment audio artifact restore');
contains(productionWorkflow, 'run-id: ${{ steps.payment_audio_artifact.outputs.run_id }}', 'production staging payment audio artifact run selection');
contains(productionWorkflow, 'github-token: ${{ github.token }}', 'production staging payment audio artifact token');
contains(productionWorkflow, 'path: .ci-payment-audio-artifact', 'production staging payment audio empty extraction directory');
contains(productionWorkflow, 'Install Windows payment audio staging artifact', 'production staging payment audio artifact installation');
contains(productionWorkflow, 'New-Item -ItemType Directory -Force -Path $target', 'production staging payment audio destination directory');
contains(productionWorkflow, 'mien-bac-thanh-ha', 'production staging payment audio complete preset guard');
contains(productionWorkflow, 'opshub-payment-audio-$sha', 'production staging payment audio artifact name');
excludes(productionWorkflow, 'gh run download', 'production staging artifact restore avoids CLI download');
contains(productionWorkflow, 'git lfs pull --include="windows/assets/payment_audio/local_preset_speaker_v1/**"', 'production scoped Windows LFS pull');
contains(stagingWorkflow, 'lfs: false', 'staging checkout avoids Android LFS download');
contains(stagingWorkflow, 'actions/cache@caa296126883cff596d87d8935842f9db880ef25', 'staging Windows payment audio cache');
contains(stagingWorkflow, "hashFiles('windows/assets/payment_audio/local_preset_speaker_v1/**/manifest.json')", 'staging payment audio manifest cache key');
contains(stagingWorkflow, 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02', 'staging Windows payment audio source artifact');
contains(stagingWorkflow, 'opshub-payment-audio-${{ github.sha }}', 'staging payment audio artifact name');
contains(stagingWorkflow, 'git lfs pull --include="windows/assets/payment_audio/local_preset_speaker_v1/**"', 'staging scoped Windows LFS pull');
assert.equal(
  existsSync(path.join(root, '.github', 'workflows', 'build-windows-msix.yml')),
  false,
  'retired MSIX workflow must be absent',
);
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
  'run_compose_or_rollback up -d --force-recreate --wait --wait-timeout 120 redis',
  'production coordinated Redis authentication rollout',
);
contains(
  productionRollbackRuntime,
  'redis api realtime caddy',
  'production rollback includes Redis configuration',
);
contains(
  productionWorkflow,
  'OPSHUB_COMPOSE_PROJECT=\'home-server\'',
  'production existing Compose project identity',
);
excludes(
  productionWorkflow,
  "COMPOSE_PROJECT_NAME='opshub'",
  'retired parallel production Compose project identity',
);
contains(
  productionWorkflow,
  'deploy/home-server/prepare-rollback-env.sh',
  'production exact-release rollback env preparation',
);
contains(
  productionWorkflow,
  'deploy/home-server/rollback-runtime.sh',
  'production coherent runtime rollback helper',
);
excludes(
  productionWorkflow,
  'prepare-bidv-legacy-rollback.sh',
  'production deploy must not invoke the BIDV break-glass helper',
);
for (const directOriginContract of [
  'request_content phongvu.work /',
  'request_content phongvu.work /help',
  'request_content phongvu.work /download',
  'request_content api.phongvu.work /v1/health',
  'request_content opshub.hoanghochoi.com /api/health',
  'request_status phongvu.work /api/health 404',
  'request_status api.phongvu.work /health 404',
  'request_status unknown.phongvu.work /health 404',
  'Sec-WebSocket-Key:',
  'temporarily_unavailable',
  'invalid_client',
  'invalid_token',
  'APP_PACKAGE_SHA256',
  'Served manifest differs from candidate shared manifest.',
]) {
  contains(
    productionOriginVerifier,
    directOriginContract,
    'production direct-origin acceptance contract',
  );
}
for (const rollbackAuthorityContract of [
  'release-manifest.json',
  'sourceCommit',
  'release-local env.example differs from exact Git authority',
  'required_public_keys=',
  'optional_public_keys=',
  'remove_value',
  'PUBLIC_BASE_URL does not match OPSHUB_DOMAIN',
]) {
  contains(productionRollbackEnv, rollbackAuthorityContract, 'exact rollback authority contract');
}
for (const signalContract of [
  "trap 'on_signal INT 130' INT",
  "trap 'on_signal TERM 143' TERM",
  "trap 'on_signal HUP 129' HUP",
  "trap 'on_exit $?' EXIT",
  'recover_coherent_state()',
]) {
  contains(productionRollbackRuntime, signalContract, 'signal-safe runtime rollback contract');
}
for (const tunnelContract of [
  'flock -n 9',
  'baseline_hash',
  'rendered_hash',
  'remove_owned_rules()',
  'Owned production Tunnel rules changed; refusing surgical restore.',
  'Live Tunnel config changed during restore validation; refusing overwrite.',
  'live Tunnel config changed during finalize validation; retaining checkpoint',
  "trap 'on_signal HUP 129' HUP",
]) {
  contains(productionCloudflareTransaction, tunnelContract, 'Cloudflare CAS transaction contract');
}
contains(productionBaselineVerifier, 'mounted Caddyfile hash differs', 'production baseline Caddy hash proof');
contains(productionBaselineVerifier, 'advertised package is absent', 'production baseline package proof');
contains(productionBaselineVerifier, 'com.docker.compose.project.config_files', 'production baseline Compose label proof');
contains(productionManifestVerifier, 'sha256 mismatch', 'exact release file hash proof');
contains(productionManifestVerifier, 'critical paths missing', 'exact release critical-path proof');
contains(productionRuntimeIdentity, 'apiImageId', 'production API image identity proof');
contains(productionRuntimeIdentity, 'realtimeImageId', 'production realtime image identity proof');
contains(productionRuntimeIdentity, 'manifestSha256', 'production shared manifest identity proof');
contains(productionRuntimeIdentity, 'hash_tree()', 'production full web-tree identity proof');
contains(productionWorkflow, 'verify_previous_baseline()', 'production pre-mutation baseline reconcile');
contains(productionWorkflow, 'reconcile-production-baseline.sh', 'production baseline reconciler invocation');
contains(productionWorkflow, 'verify-static-response', 'static Help behavior sentinel');
contains(productionWorkflow, '--force-recreate --wait --wait-timeout 120 api', 'static API Help mount refresh');
contains(productionWorkflow, 'help-state-before.json', 'complete Help ownership checkpoint');
contains(
  productionWorkflow,
  'dist/src/help-content/help-content-deploy-state.js',
  'server-side Help ownership probe compiled path',
);
excludes(
  productionWorkflow,
  'node dist/help-content/help-content-deploy-state.js',
  'invalid server-side Help ownership probe path',
);
excludes(productionWorkflow, '$CURRENT_DIR/docs/help', 'mutable current-release Help path');
excludes(productionWorkflow, 'opshub_txn_restore_static_current', 'retired mutable Help rollback');
contains(helpDeployStateProbe, 'editorManagedCount', 'full Help editor ownership count');
contains(helpDeployStateProbe, 'publicProjectionSha256', 'sanitized Help public projection proof');
for (const [contract, label] of [
  [helpProductContract, 'Help product contract'],
  [backendPlatformContract, 'backend platform contract'],
]) {
  contains(contract, '/srv/opshub/downloads/help', `${label} shared Help source`);
  contains(contract, 'immutable', `${label} immutable release boundary`);
}
contains(productionBaselineReconciler, 'No exact previous-release shared checkpoint is available', 'split baseline requires historical shared checkpoint');
contains(productionBaselineReconciler, 'recover_historical_shared()', 'signal-safe historical shared recovery');
for (const outerSignal of [
  "trap 'rollback_on_error 130' INT",
  "trap 'rollback_on_error 143' TERM",
  "trap 'rollback_on_error 129' HUP",
  'trap - ERR INT TERM HUP',
]) contains(productionWorkflow, outerSignal, 'production outer SSH signal rollback');
contains(
  productionWorkflow,
  'DIRECT_ORIGIN_ACCEPTED',
  'production direct-origin acceptance marker',
);
const productionDirectOriginIndex = productionWorkflow.indexOf(
  'bash deploy/home-server/verify-production-origin.sh',
);
const productionTunnelActivateIndex = productionWorkflow.indexOf(
  'name: Activate production Cloudflare ingress after direct-origin acceptance',
);
const productionPublicVerifyIndex = productionWorkflow.indexOf(
  'name: Verify public health and version metadata',
);
const productionTunnelRestoreIndex = productionWorkflow.indexOf(
  'name: Restore production Tunnel after failed public verification',
);
assert.ok(
  productionDirectOriginIndex >= 0 &&
    productionDirectOriginIndex < productionTunnelActivateIndex &&
    productionTunnelActivateIndex < productionPublicVerifyIndex &&
    productionPublicVerifyIndex < productionTunnelRestoreIndex,
  'production Tunnel transaction ordering is unsafe',
);
const productionPublicVerification = productionWorkflow.slice(
  productionPublicVerifyIndex,
  productionTunnelRestoreIndex,
);
contains(
  productionPublicVerification,
  'Cloudflare Bot Fight Mode challenges GitHub-hosted runner egress',
  'production Bot Fight Mode verification boundary',
);
contains(
  productionPublicVerification,
  'ssh opshub-vps',
  'production public verification remote egress',
);
contains(
  productionPublicVerification,
  'verify_cloudflare_edge_headers()',
  'production public verification Cloudflare edge proof',
);
contains(
  productionPublicVerification,
  "'^cf-ray:[[:space:]]*[[:alnum:]-]+'",
  'production public verification CF-Ray proof',
);
contains(
  productionPublicVerification,
  'source "$PUBLIC_PROBE_SCRIPT"',
  'production full deploy shared Cloudflare response validator',
);
contains(
  productionPublicVerification,
  'opshub_api_node -e',
  'production public validation containerized Node boundary',
);
excludes(
  productionPublicVerification,
  '          node -e ',
  'production public validation host Node dependency',
);
excludes(
  productionPublicVerification,
  "require('fs')",
  'production containerized validation host-filesystem dependency',
);
contains(
  productionPublicVerification,
  'JSON.parse(payload).error',
  'production BIDV response argv validation',
);
contains(
  productionWorkflow,
  '< deploy/home-server/cloudflare-public-probe.sh',
  'production static deploy streams current validator over SSH',
);
excludes(
  productionWorkflow,
  '[[ "$status" == 2* ]] &&',
  'public probe conditional-chain body leak',
);
contains(cloudflarePublicProbe, '%{url_effective}', 'artifact effective URL proof');
contains(
  cloudflarePublicProbe,
  'opshub_cloudflare_final_headers()',
  'final response header isolation',
);
contains(
  cloudflarePublicProbe,
  'opshub_cloudflare_artifact_host_allowed()',
  'environment-specific artifact host allowlist',
);
contains(
  cloudflarePublicProbe,
  '^([[:alnum:].-]+)(:443)?$',
  'restricted effective URL authority parser',
);
contains(
  productionWorkflow,
  "'phongvu.work' 'opshub.hoanghochoi.com'",
  'production artifact host allowlist',
);
contains(
  productionWorkflow,
  "'phongvu.work' 'api.phongvu.work' 'opshub.hoanghochoi.com'",
  'production body host allowlist',
);
contains(
  productionWorkflow,
  'restore /etc/cloudflared/config.yml "$tunnel_snapshot"',
  'production Tunnel restoration after public failure',
);
contains(
  productionWorkflow,
  'the directly verified dual-domain candidate foundation and rollback checkpoint were retained',
  'production public failure retains accepted dual-domain foundation',
);
const productionBackendDeployIndex = productionWorkflow.indexOf(
  'name: Deploy backend and publish version metadata',
);
const productionRemoteRuntimeIndex = productionWorkflow.indexOf(
  `bash -s" <<'REMOTE'`,
  productionBackendDeployIndex,
);
const productionRuntimeTrapIndex = productionWorkflow.indexOf(
  "trap 'rollback_on_error $?' ERR",
  productionRemoteRuntimeIndex,
);
const productionRuntimeTrapEndIndex = productionWorkflow.indexOf(
  'trap - ERR',
  productionRuntimeTrapIndex,
);
assert.ok(
  productionBackendDeployIndex >= 0 &&
    productionRemoteRuntimeIndex > productionBackendDeployIndex &&
    productionRuntimeTrapIndex > productionRemoteRuntimeIndex &&
    productionRuntimeTrapEndIndex > productionRuntimeTrapIndex,
  'production runtime rollback transaction boundaries are missing',
);
const productionRuntimeTransaction = productionWorkflow.slice(
  productionRemoteRuntimeIndex,
  productionRuntimeTrapEndIndex,
);
contains(
  productionRuntimeTransaction,
  'set -Eeuo pipefail',
  'production ERR trap inheritance through shell functions',
);
contains(
  productionRuntimeTransaction,
  'run_compose_or_rollback()',
  'production explicit compose rollback wrapper',
);
for (const guardedCompose of [
  'run_compose_or_rollback up -d --force-recreate --wait --wait-timeout 120 redis',
  'run_compose_or_rollback --profile migrate run --rm -T --build migrate',
  'run_compose_or_rollback up -d --build --force-recreate --wait --wait-timeout 240 api realtime caddy',
]) {
  contains(
    productionRuntimeTransaction,
    guardedCompose,
    'production compose failure rollback coverage',
  );
}
contains(stagingWorkflow, '--no-web-resources-cdn', 'staging local Flutter web resources');
excludes(stagingWorkflow, 'secrets.CF_ACCESS_CLIENT_ID', 'retired staging Access client ID secret');
excludes(stagingWorkflow, 'secrets.CF_ACCESS_CLIENT_SECRET', 'retired staging Access client secret');
excludes(stagingWorkflow, 'CF-Access-Client-Id:', 'retired staging Access client ID header');
excludes(stagingWorkflow, 'CF-Access-Client-Secret:', 'retired staging Access client secret header');
contains(stagingWorkflow, 'rollback_on_error()', 'staging automatic rollback trap');
contains(
  stagingWorkflow,
  'redis api realtime caddy',
  'staging rollback recreates the previous runtime',
);
contains(
  stagingWorkflow,
  "trap 'rollback_on_error $?' ERR",
  'staging deploy failure trap activation',
);
contains(
  stagingWorkflow,
  'cp --preserve=mode,ownership,timestamps -- "$OPSHUB_ENV_FILE" "$env_snapshot"',
  'staging protected env rollback snapshot',
);
contains(stagingWorkflow, 'restore_env_snapshot()', 'staging env rollback restore');
contains(stagingWorkflow, 'id: deploy_runtime', 'staging runtime deploy checkpoint');
contains(
  stagingWorkflow,
  "if: ${{ (failure() || cancelled()) && steps.deploy_runtime.outcome == 'success' }}",
  'staging post-deploy verification rollback guard',
);
contains(
  stagingWorkflow,
  'Protected staging rollback env or release metadata is missing; manual recovery is required.',
  'staging fail-closed public verification rollback',
);
contains(
  stagingWorkflow,
  "if: ${{ success() && steps.deploy_runtime.outcome == 'success' }}",
  'staging rollback checkpoint success cleanup',
);
contains(
  stagingWorkflow,
  'Staging /v1/ws/v2 without a one-time ticket returned ${ws_status}; expected 401',
  'staging public realtime route smoke',
);
const stagingRuntimeCheckpointIndex = stagingWorkflow.indexOf(
  'id: deploy_runtime',
);
const stagingPublicVerificationIndex = stagingWorkflow.indexOf(
  'name: Verify staging public health and version metadata',
);
const stagingVerificationRollbackIndex = stagingWorkflow.indexOf(
  'name: Roll back staging after failed release verification',
);
const stagingCheckpointCleanupIndex = stagingWorkflow.indexOf(
  'name: Finalize successful staging rollback checkpoint',
);
const stagingRuntimeTransaction = stagingWorkflow.slice(
  stagingRuntimeCheckpointIndex,
  stagingPublicVerificationIndex,
);
const stagingPublicVerification = stagingWorkflow.slice(
  stagingPublicVerificationIndex,
  stagingVerificationRollbackIndex,
);
contains(
  stagingPublicVerification,
  'Cloudflare Bot Fight Mode challenges GitHub-hosted runner egress',
  'staging Bot Fight Mode verification boundary',
);
contains(
  stagingPublicVerification,
  'ssh opshub-staging',
  'staging public verification remote egress',
);
contains(
  stagingPublicVerification,
  'source "$PUBLIC_PROBE_SCRIPT"',
  'staging shared Cloudflare response validator',
);
contains(
  stagingPublicVerification,
  'opshub_api_node -e',
  'staging public validation containerized Node boundary',
);
excludes(
  stagingPublicVerification,
  '          node -e ',
  'staging public validation host Node dependency',
);
contains(
  stagingPublicVerification,
  "'staging.phongvu.work' 'opshub-staging.hoanghochoi.com'",
  'staging artifact host allowlist',
);
contains(
  stagingPublicVerification,
  "'staging.phongvu.work' 'api-staging.phongvu.work' 'opshub-staging.hoanghochoi.com'",
  'staging body host allowlist',
);
excludes(
  stagingPublicVerification,
  'public_curl ',
  'removed staging inline curl wrapper reference',
);
contains(
  stagingRuntimeTransaction,
  'set -Eeuo pipefail',
  'staging runtime ERR trap inheritance through shell functions',
);
assert.ok(
  stagingRuntimeCheckpointIndex >= 0 &&
    stagingRuntimeCheckpointIndex < stagingPublicVerificationIndex &&
    stagingPublicVerificationIndex < stagingVerificationRollbackIndex &&
    stagingVerificationRollbackIndex < stagingCheckpointCleanupIndex,
  'staging rollback checkpoint must span every public verification gate',
);
const stagingBeforeRuntimeCheckpoint = stagingWorkflow.slice(
  0,
  stagingRuntimeCheckpointIndex,
);
for (const forbidden of [
  'sudo install -m 0644 "$android_artifact" "$DOWNLOADS_DIR/$APK_NAME"',
  'sudo install -m 0644 "$TMP_DIR/latest.json" "$DOWNLOADS_DIR/latest.json"',
  'sudo rm -rf "$WEB_DIR"',
]) {
  excludes(
    stagingBeforeRuntimeCheckpoint,
    forbidden,
    'staging shared publication before rollback checkpoint',
  );
}
for (const expected of [
  '${GITHUB_SHA}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}',
  'snapshot_and_promote_shared_publication()',
  'snapshot_and_promote_shared_publication\n          cd "$REMOTE_RELEASE_DIR"',
  'shared_snapshot_dir="${rollback_state_dir}/deploy-${DEPLOY_RUN_ID}.shared"',
  'shared_stage_dir="${rollback_state_dir}/deploy-${DEPLOY_RUN_ID}.stage"',
  'SNAPSHOT_READY',
  'PROMOTION_STARTED',
  'PROMOTED',
  'DOWNLOADS_DIR_PRESENT',
  'restore_shared_publication()',
  'Staging release, env, web, Help, manifest and client files were rolled back',
  '[ "$dir_real" = "$previous_real" ]',
]) {
  contains(
    stagingWorkflow,
    expected,
    'staging shared publication rollback state',
  );
}
excludes(
  stagingWorkflow,
  'Refusing to remove unexpected staging directory: $CLIENT_STAGING_DIR',
  'staging explicit-exit rollback bypass',
);
const stagingPreSwitchTrapIndex = stagingWorkflow.indexOf(
  "trap 'rollback_env_before_runtime_switch $?' ERR",
);
const stagingRuntimeTrapIndex = stagingWorkflow.indexOf(
  "trap 'rollback_on_error $?' ERR",
);
const stagingRuntimeTrapEndIndex = stagingWorkflow.indexOf(
  'trap - ERR',
  stagingRuntimeTrapIndex,
);
assert.ok(
  stagingPreSwitchTrapIndex > stagingRuntimeCheckpointIndex &&
    stagingRuntimeTrapIndex > stagingPreSwitchTrapIndex &&
    stagingRuntimeTrapEndIndex > stagingRuntimeTrapIndex,
  'staging transaction traps must cover shared promotion and runtime switch',
);
excludes(
  stagingWorkflow.slice(stagingPreSwitchTrapIndex, stagingRuntimeTrapIndex),
  'exit 1',
  'staging pre-switch explicit-exit rollback bypass',
);
excludes(
  stagingWorkflow.slice(stagingRuntimeTrapIndex, stagingRuntimeTrapEndIndex),
  'exit 1',
  'staging post-switch explicit-exit rollback bypass',
);
for (const sideEffectFlag of [
  'ERP_ORDER_CACHE_SYNC_ENABLED false',
  'ERP_ORDER_STATUS_SYNC_ENABLED false',
  'VIETQR_AUTO_RECONCILE_ENABLED false',
  'MAP_VIETIN_GLOBAL_SYNC_ENABLED false',
  'HOME_SUMMARY_ERP_BACKFILL_ENABLED false',
]) {
  contains(stagingWorkflow, sideEffectFlag, 'staging side-effect isolation');
}
contains(
  stagingWorkflow,
  'OPSHUB_STAGING_LOAD_MAINTENANCE_ENABLED true',
  'staging load maintenance gate',
);
contains(
  stagingWorkflow,
  'OPSHUB_STAGING_LOAD_OUTPUT_DIR /srv/opshub-staging/load-output',
  'staging load output isolation',
);
contains(
  stagingWorkflow,
  'for smtp_key in SMTP_HOST SMTP_PORT SMTP_SECURE SMTP_USER SMTP_PASS SMTP_FROM',
  'staging SMTP isolation',
);
contains(
  stagingWorkflow,
  "verify_canonical_route '/download/' '/download'",
  'staging direct-origin download smoke',
);
contains(
  stagingWorkflow,
  "verify_canonical_route '/help/' '/help'",
  'staging direct-origin help smoke',
);
contains(
  stagingWorkflow,
  "verify_direct_origin_route '/download/' 'staging.phongvu.work' '/download'",
  'guarded staging direct-origin download smoke',
);
contains(
  stagingWorkflow,
  "verify_direct_origin_route '/help/' 'staging.phongvu.work' '/help'",
  'guarded staging direct-origin help smoke',
);
contains(
  stagingWorkflow,
  'Host: unknown.staging.phongvu.work',
  'guarded staging unknown-host isolation smoke',
);
contains(
  stagingWorkflow,
  'unknown.staging.phongvu.work/health returned ${unknown_host_status}; expected 404',
  'guarded staging unknown-host 404 contract',
);
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
]) {
  contains(workflow, `actions/checkout@${checkoutSha}`, `${label} checkout pin`);
  excludes(workflow, 'actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5', `${label} deprecated checkout pin`);
  excludes(workflow, 'actions/checkout@v', `${label} floating checkout version`);
}
contains(
  cloudflarePublicProbe,
  '[[ ! "$status" =~ ^2[0-9][0-9]$ ]]',
  'shared public exact 2xx verification gate',
);
contains(
  stagingWorkflow,
  'OPSHUB_DOWNLOAD_PUBLIC_BASE_URL: https://opshub-staging.hoanghochoi.com',
  'staging artifact host',
);
excludes(
  stagingWorkflow,
  'OPSHUB_DOWNLOAD_PUBLIC_BASE_URL: https://opshub.hoanghochoi.com/staging-download',
  'retired cross-host staging artifact base',
);
contains(stagingWorkflow, '-D "$main_headers_file" -o /dev/null', 'staging real GET header verification');
contains(stagingWorkflow, 'main.dart.js returned HTTP ${main_status}', 'staging asset status diagnostics');
contains(productionWorkflow, '-D "$main_headers_file" -o /dev/null', 'production real GET header verification');
contains(productionWorkflow, 'main.dart.js returned HTTP ${main_status}', 'production asset status diagnostics');
excludes(stagingWorkflow, 'main.dart.js?v=${GITHUB_SHA}" -fsSI', 'staging public HEAD-only asset verification');
contains(stagingWorkflow, '<title>Tải ứng dụng PhongVu OpsHub</title>', 'staging public download landing-page verification');
excludes(stagingWorkflow, 'cloudflareaccess.com/cdn-cgi/access/login/', 'retired staging Access download redirect verification');
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
  "'staging.phongvu.work'",
  'Download staging host restriction',
);

const helpUrlPolicy = extractFunction(help, 'sanitizeUrl');
const helpUrlSandbox = {
  window: { location: { origin: 'https://phongvu.work' } },
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
assert.equal(sanitizeHelpUrl('http://phongvu.work/help'), '#');
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
    origin = 'https://phongvu.work',
    hostname = 'phongvu.work',
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
assert.equal(sanitizeDownloadUrl('https://phongvu.work/other/a.apk'), '');
assert.equal(
  sanitizeDownloadUrl('/downloads/a.apk'),
  'https://phongvu.work/downloads/a.apk',
);
assert.equal(
  sanitizeDownloadUrl('https://opshub.hoanghochoi.com/downloads/a.apk'),
  'https://opshub.hoanghochoi.com/downloads/a.apk',
);
assert.equal(
  sanitizeDownloadUrl(
    'https://opshub-staging.hoanghochoi.com/downloads/a.apk',
    {
      origin: 'https://staging.phongvu.work',
      hostname: 'staging.phongvu.work',
    },
  ),
  'https://opshub-staging.hoanghochoi.com/downloads/a.apk',
);
assert.equal(
  sanitizeDownloadUrl(
    'https://opshub.hoanghochoi.com/downloads/a.apk',
    {
      origin: 'https://staging.phongvu.work',
      hostname: 'staging.phongvu.work',
    },
  ),
  '',
);
assert.equal(
  sanitizeDownloadUrl(
    'https://opshub-staging.hoanghochoi.com/downloads/a.apk#bad',
    {
      origin: 'https://staging.phongvu.work',
      hostname: 'staging.phongvu.work',
    },
  ),
  '',
);

const packageJson = JSON.parse(packageJsonText);
const packageLock = JSON.parse(packageLockText);
assert.equal(
  packageJson.scripts['security:audit-legacy-upload-access'],
  'npm run run:nest-command -- node scripts/audit-legacy-upload-access.mjs',
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
