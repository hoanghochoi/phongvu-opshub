import path from 'node:path';
import { runAffectedConsumerSuite } from './run-affected-consumer-suite.mjs';

const root = process.cwd();
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const flutter = process.platform === 'win32' ? 'flutter.bat' : 'flutter';

const suites = [
  {
    name: 'Nest OPS-39 plus auth/MAP/payment/Home/BigQuery consumers',
    cwd: path.join(root, 'backend-nest'),
    command: npm,
    toolchainProfile: 'nestjs',
    args: [
      'test',
      '--',
      '--runInBand',
      'src/bidv-h2h/bidv-h2h.controller.spec.ts',
      'src/bidv-h2h/bidv-h2h-admin.service.spec.ts',
      'src/bidv-h2h/bidv-h2h-operating-mode.spec.ts',
      'src/bidv-h2h/bidv-h2h-operating-policy.spec.ts',
      'src/bidv-h2h/bidv-h2h-parser.spec.ts',
      'src/bidv-h2h/bidv-h2h-crypto.service.spec.ts',
      'src/bidv-h2h/bidv-h2h-oauth.service.spec.ts',
      'src/bidv-h2h/bidv-h2h-ingress.service.spec.ts',
      'src/bidv-h2h/bidv-h2h-projection.worker.spec.ts',
      'src/config/env.spec.ts',
      'src/common/user-aware-throttler.guard.spec.ts',
      'src/map-vietin/map-vietin.service.spec.ts',
      'src/payment-notifications/payment-notifications.service.spec.ts',
      'src/home-summary/home-summary-projection.service.spec.ts',
      'src/map-vietin-bigquery/map-vietin-bigquery-row.mapper.spec.ts',
    ],
  },
  {
    name: 'BigQuery additive schema contract',
    cwd: path.join(root, 'backend-nest'),
    command: process.execPath,
    args: ['--test', 'scripts/map-vietin-bigquery-schema.test.mjs'],
  },
  {
    name: 'OPS-39 migration and non-destructive rollback contract',
    cwd: path.join(root, 'backend-nest'),
    command: npm,
    toolchainProfile: 'nestjs',
    args: ['run', 'verify:ops39:migration'],
  },
  {
    name: 'Flutter Admin/router plus Tiền vào/Sao kê/VietQR/Home consumers',
    cwd: root,
    command: flutter,
    toolchainProfile: 'flutter',
    args: [
      'test',
      '--no-pub',
      '--concurrency=1',
      'test/api_connection_admin_screen_test.dart',
      'test/admin_menu_screen_test.dart',
      'test/app_router_test.dart',
      'test/app_platform_capabilities_test.dart',
      'test/design_system_migration_guard_test.dart',
      'test/payment_monitor_repository_test.dart',
      'test/bank_statement_repository_test.dart',
      'test/vietqr_screen_test.dart',
      'test/home_summary_repository_cache_test.dart',
    ],
  },
  {
    name: 'Go realtime v2 and legacy payment audience',
    cwd: path.join(root, 'backend-go'),
    command: 'go',
    args: ['test', './...'],
  },
  {
    name: 'Dedicated BIDV host isolation and fail-closed env',
    cwd: root,
    command: process.execPath,
    args: ['scripts/validate-ops39-caddy.mjs'],
  },
  {
    name: 'BIDV local-only promotion boundary',
    cwd: root,
    command: process.execPath,
    args: ['scripts/validate-ops39-local-boundary.mjs'],
  },
  {
    name: 'BIDV backup and KEK fail-closed boundary',
    cwd: root,
    command: process.execPath,
    args: ['scripts/validate-ops39-backup-boundary.mjs'],
  },
  {
    name: 'Final patch whitespace',
    cwd: root,
    command: 'git',
    args: ['diff', '--check'],
  },
];

if (process.env.OPS39_POSTGRES_URL) {
  suites.splice(suites.length - 1, 0, {
    name: 'OPS-39 disposable PostgreSQL operating-mode trigger',
    cwd: path.join(root, 'backend-nest'),
    command: process.execPath,
    args: ['scripts/verify-ops39-postgres-mode.mjs'],
  });
}

for (const suite of suites) {
  runAffectedConsumerSuite(suite, {
    root,
    log: (message) => console.log(`[OPS-39] ${message}`),
  });
}

console.log('\nOPS-39 AFFECTED CONSUMERS PASS');
