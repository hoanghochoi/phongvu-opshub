import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const backup = readFileSync('deploy/home-server/backup.sh', 'utf8');
const restore = readFileSync(
  'deploy/home-server/verify-bidv-backup.sh',
  'utf8',
);
const bootstrap = readFileSync(
  'deploy/home-server/bootstrap-bidv-kek.sh',
  'utf8',
);
const rollbackBridge = readFileSync(
  'deploy/home-server/prepare-bidv-legacy-rollback.sh',
  'utf8',
);

assert.match(backup, /BIDV database and KEK require an age-encrypted backup/);
assert.match(backup, /node scripts\/verify-bidv-kek\.mjs/);
assert.match(backup, /bidv_kek_archive=\$BIDV_KEK_ARCHIVE/);
assert.match(backup, /sha256sum "\$\{checksum_files\[@\]\}" > SHA256SUMS/);
assert.match(restore, /sha256sum -c SHA256SUMS/);
assert.match(restore, /grep -qx 'encryption=age'/);
assert.match(restore, /gzip -t/);
assert.match(restore, /tar -tzf/);
const composeWrapper = bootstrap.match(
  /compose_cmd\(\) \{[\s\S]*?docker compose --env-file "\$ENV_FILE" -f "\$COMPOSE_FILE" "\$@" < \/dev\/null[\s\S]*?\n\}/,
);
assert.ok(
  composeWrapper,
  'BIDV bootstrap must close Compose stdin so it cannot consume the remote deploy heredoc',
);
assert.doesNotMatch(
  bootstrap.replace(composeWrapper[0], ''),
  /\bdocker compose\b/,
  'all BIDV bootstrap Compose calls must use the stdin-safe wrapper',
);
assert.match(bootstrap, /compose_cmd exec -T postgres/);
assert.match(bootstrap, /compose_cmd --profile maintenance run --rm -T --build/);
assert.match(bootstrap, /verify_candidate_against_database "\$CANDIDATE_FILE"/);
assert.ok(
  bootstrap.indexOf('verify_candidate_against_database "$CANDIDATE_FILE"') <
    bootstrap.indexOf('mv -f -- "$CANDIDATE_FILE" "$SECRET_FILE"'),
  'legacy candidate must be verified before atomic installation',
);
assert.match(rollbackBridge, /BIDV_H2H_KEK_BASE64/);
assert.match(rollbackBridge, /BIDV_H2H_INGEST_ENABLED/);
assert.match(rollbackBridge, /BIDV_H2H_PROJECTION_ENABLED/);
assert.match(rollbackBridge, /SELECT \"ingressEnabled\", \"projectionEnabled\"/);
assert.match(rollbackBridge, /if \[\[ \"\$ACTION\" == \"clear\" \]\]/);
assert.match(rollbackBridge, /\[\[ \"\$ACTION\" == \"prepare\" \]\]/);

console.log('OPS-39 backup/KEK fail-closed boundary PASS');
