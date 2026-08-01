import { spawnSync } from 'node:child_process';
import path from 'node:path';

const root = process.cwd();
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const flutter = process.platform === 'win32' ? 'flutter.bat' : 'flutter';

const suites = [
  {
    name: 'Nest OPS-39 plus auth/MAP/payment/Home/BigQuery consumers',
    cwd: path.join(root, 'backend-nest'),
    command: npm,
    args: [
      'test',
      '--',
      '--runInBand',
      'src/bidv-h2h/bidv-h2h.controller.spec.ts',
      'src/bidv-h2h/bidv-h2h-admin.service.spec.ts',
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
    args: ['run', 'verify:ops39:migration'],
  },
  {
    name: 'Flutter Admin/router plus Tiền vào/Sao kê/VietQR/Home consumers',
    cwd: root,
    command: flutter,
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
    name: 'Final patch whitespace',
    cwd: root,
    command: 'git',
    args: ['diff', '--check'],
  },
];

for (const suite of suites) {
  console.log(`\n[OPS-39] ${suite.name}`);
  const needsShell =
    process.platform === 'win32' && /\.(cmd|bat)$/i.test(suite.command);
  const result = spawnSync(suite.command, suite.args, {
    cwd: suite.cwd,
    stdio: 'inherit',
    windowsHide: true,
    // Windows distributes npm/flutter as command shims. Only those shims need
    // cmd.exe; direct executables (Node, Go and Git) must keep their full path.
    shell: needsShell,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    process.exitCode = result.status ?? 1;
    throw new Error(`${suite.name} failed with exit ${result.status}`);
  }
}

console.log('\nOPS-39 AFFECTED CONSUMERS PASS');
