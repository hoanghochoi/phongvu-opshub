import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const PROVIDER_IDENTIFIERS_KEY = 'providerIdentifiers';

function asRecord(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  return value;
}

function text(value) {
  return value === null || value === undefined ? '' : String(value).trim();
}

function firstText(...values) {
  for (const value of values) {
    const normalized = text(value);
    if (normalized) return normalized;
  }
  return '';
}

function rawDataRecord(value) {
  if (typeof value !== 'string') return asRecord(value) || {};
  try {
    return asRecord(JSON.parse(value)) || {};
  } catch {
    return {};
  }
}

function sourceIdentifiers(row) {
  const rawData = rawDataRecord(row.rawData);
  const stored = asRecord(rawData[PROVIDER_IDENTIFIERS_KEY]) || {};
  const isEfast = text(rawData.source) === 'VIETIN_EFAST';
  const transactionNumber = firstText(
    row.transactionNumber,
    rawData.transactionNumber,
  );
  return {
    mapTransactionNumber:
      firstText(
        stored.mapTransactionNumber,
        isEfast ? '' : transactionNumber,
      ) || null,
    efastTrxId:
      firstText(stored.efastTrxId, isEfast ? rawData.trxId : '') || null,
    efastTrxRefNo:
      firstText(stored.efastTrxRefNo, isEfast ? rawData.trxRefNo : '') || null,
  };
}

function mergeIdentifiers(baseRow, evidenceRow) {
  const baseRawData = rawDataRecord(baseRow.rawData);
  const base = sourceIdentifiers(baseRow);
  const evidence = sourceIdentifiers(evidenceRow);
  const conflicts = Object.keys(base).filter(
    (key) => base[key] && evidence[key] && base[key] !== evidence[key],
  );
  if (conflicts.length > 0) return { conflicts };
  const identifiers = Object.fromEntries(
    Object.entries({
      mapTransactionNumber:
        base.mapTransactionNumber || evidence.mapTransactionNumber,
      efastTrxId: base.efastTrxId || evidence.efastTrxId,
      efastTrxRefNo: base.efastTrxRefNo || evidence.efastTrxRefNo,
    }).filter(([, value]) => Boolean(value)),
  );
  return {
    conflicts: [],
    rawData: { ...baseRawData, [PROVIDER_IDENTIFIERS_KEY]: identifiers },
    canonicalStatementNumber:
      identifiers.efastTrxId ||
      identifiers.mapTransactionNumber ||
      baseRow.transactionNumber ||
      null,
  };
}

function normalizeEvidenceLine(value) {
  const envelope = asRecord(value);
  if (!envelope) return null;
  const table = text(envelope.table || envelope.entity || envelope.kind);
  const normalizedTable = table.replace(/[^a-z0-9]/gi, '').toLowerCase();
  if (table && !normalizedTable.includes('mapvietintransaction')) {
    return null;
  }
  const row =
    asRecord(envelope.row) ||
    asRecord(envelope.data) ||
    asRecord(envelope.record) ||
    envelope;
  const rawData = rawDataRecord(row.rawData);
  if (text(rawData.source) !== 'VIETIN_EFAST' || !text(rawData.trxId)) {
    return null;
  }
  const paidAt = new Date(row.paidAt);
  const amount = Number(row.amount);
  const storeCode = text(row.storeCode);
  const content = text(row.content);
  if (
    !storeCode ||
    !Number.isSafeInteger(amount) ||
    amount <= 0 ||
    Number.isNaN(paidAt.getTime()) ||
    !content
  ) {
    return null;
  }
  return {
    id: text(row.id) || null,
    storeCode,
    transactionNumber: text(row.transactionNumber) || null,
    amount,
    content,
    paidAt: paidAt.toISOString(),
    rawData,
  };
}

export function extractEvidenceTransactions(jsonl) {
  const output = [];
  for (const [index, line] of String(jsonl).split(/\r?\n/).entries()) {
    if (!line.trim()) continue;
    let value;
    try {
      value = JSON.parse(line);
    } catch {
      throw new Error(`Invalid JSONL at line ${index + 1}`);
    }
    const row = normalizeEvidenceLine(value);
    if (row) output.push(row);
  }
  return output;
}

export function bankFingerprint(row) {
  return [
    text(row.storeCode),
    String(Number(row.amount)),
    new Date(row.paidAt).toISOString(),
    text(row.content),
  ].join('|');
}

export function decideRepair(evidenceRow, candidates) {
  const mapCandidates = candidates.filter(
    (candidate) =>
      text(rawDataRecord(candidate.rawData).source) !== 'VIETIN_EFAST',
  );
  if (mapCandidates.length === 0) return { status: 'missing' };
  if (mapCandidates.length !== 1) {
    return { status: 'ambiguous', candidateCount: mapCandidates.length };
  }
  const candidate = mapCandidates[0];
  const merged = mergeIdentifiers(candidate, evidenceRow);
  if (merged.conflicts.length > 0) {
    return { status: 'conflict', conflicts: merged.conflicts };
  }
  return {
    status: 'ready',
    candidate,
    rawData: merged.rawData,
    canonicalStatementNumber: merged.canonicalStatementNumber,
  };
}

function parseArgs(argv) {
  const args = { apply: false };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === '--apply') args.apply = true;
    else if (value === '--input') args.input = argv[++index];
    else if (value === '--checkpoint-dir') args.checkpointDir = argv[++index];
    else if (value === '--expected-input-sha256') {
      args.expectedInputSha256 = text(argv[++index]).toLowerCase();
    } else throw new Error(`Unknown argument: ${value}`);
  }
  if (!args.input) throw new Error('--input is required');
  if (args.apply && !args.checkpointDir) {
    throw new Error('--checkpoint-dir is required with --apply');
  }
  if (args.apply && !/^[a-f0-9]{64}$/.test(args.expectedInputSha256 || '')) {
    throw new Error('--expected-input-sha256 is required with --apply');
  }
  return args;
}

async function writeCheckpoint(directory, inputSha256, plans) {
  await mkdir(directory, { recursive: true });
  const timestamp = new Date().toISOString().replaceAll(/[:.]/g, '-');
  const checkpointPath = path.join(
    directory,
    `ops12-statement-identifiers-${timestamp}.jsonl`,
  );
  const body = `${plans
    .map((plan) =>
      JSON.stringify({
        table: 'MapVietinTransaction',
        row: plan.candidate,
        targetCanonicalStatementNumber: plan.canonicalStatementNumber,
      }),
    )
    .join('\n')}\n`;
  const checkpointSha256 = createHash('sha256').update(body).digest('hex');
  await writeFile(checkpointPath, body, { encoding: 'utf8', flag: 'wx' });
  await writeFile(
    `${checkpointPath}.manifest.json`,
    `${JSON.stringify(
      {
        createdAt: new Date().toISOString(),
        inputSha256,
        checkpointSha256,
        rows: plans.length,
        checkpointFile: path.basename(checkpointPath),
      },
      null,
      2,
    )}\n`,
    { encoding: 'utf8', flag: 'wx' },
  );
  return { checkpointPath, checkpointSha256 };
}

async function run() {
  const startedAt = Date.now();
  const args = parseArgs(process.argv.slice(2));
  const inputBuffer = await readFile(path.resolve(args.input));
  const inputSha256 = createHash('sha256').update(inputBuffer).digest('hex');
  if (args.expectedInputSha256 && args.expectedInputSha256 !== inputSha256) {
    throw new Error('Input SHA-256 does not match --expected-input-sha256');
  }
  const evidenceRows = extractEvidenceTransactions(
    inputBuffer.toString('utf8'),
  );
  if (evidenceRows.length === 0) {
    throw new Error('No valid eFAST transaction evidence rows were found');
  }
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
  const { default: pg } = await import('pg');
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  const plans = [];
  let missing = 0;
  let ambiguous = 0;
  let conflict = 0;
  const seen = new Map();
  try {
    console.log(
      JSON.stringify({
        event: 'ops12_repair_started',
        mode: args.apply ? 'apply' : 'dry-run',
        evidenceRows: evidenceRows.length,
        inputSha256,
      }),
    );
    for (const evidence of evidenceRows) {
      const fingerprint = bankFingerprint(evidence);
      const priorTrxId = seen.get(fingerprint);
      const currentTrxId = sourceIdentifiers(evidence).efastTrxId;
      if (priorTrxId && priorTrxId !== currentTrxId) {
        conflict += 1;
        continue;
      }
      seen.set(fingerprint, currentTrxId);
      const result = await client.query(
        `SELECT id, "storeCode", "transactionNumber", amount, content,
                "paidAt", "rawData"
           FROM "MapVietinTransaction"
          WHERE "storeCode" = $1
            AND amount = $2
            AND "paidAt" = $3
            AND content = $4
            AND ($5::text IS NULL OR id <> $5::text)
          ORDER BY id
          LIMIT 3`,
        [
          evidence.storeCode,
          evidence.amount,
          evidence.paidAt,
          evidence.content,
          evidence.id,
        ],
      );
      const decision = decideRepair(evidence, result.rows);
      if (decision.status === 'missing') missing += 1;
      else if (decision.status === 'ambiguous') ambiguous += 1;
      else if (decision.status === 'conflict') conflict += 1;
      else plans.push({ ...decision, evidence });
    }

    if (ambiguous > 0 || conflict > 0) {
      throw new Error(
        `Repair stopped before mutation: ambiguous=${ambiguous} conflict=${conflict}`,
      );
    }

    let checkpoint = null;
    let updated = 0;
    let vietQrUpdated = 0;
    if (args.apply) {
      checkpoint = await writeCheckpoint(
        path.resolve(args.checkpointDir),
        inputSha256,
        plans,
      );
      await client.query('BEGIN');
      try {
        for (const plan of plans) {
          const update = await client.query(
            `UPDATE "MapVietinTransaction"
                SET "rawData" = $2::jsonb
              WHERE id = $1
                AND "rawData" IS DISTINCT FROM $2::jsonb`,
            [plan.candidate.id, JSON.stringify(plan.rawData)],
          );
          updated += update.rowCount;
          const vietQr = await client.query(
            `UPDATE "VietQrPaymentIntent"
                SET "matchedTransactionNumber" = $2
              WHERE "matchedTransactionId" = $1
                AND "matchedTransactionNumber" IS DISTINCT FROM $2`,
            [plan.candidate.id, plan.canonicalStatementNumber],
          );
          vietQrUpdated += vietQr.rowCount;
        }
        for (const plan of plans) {
          const transactionVerification = await client.query(
            `SELECT "rawData" #>> '{providerIdentifiers,efastTrxId}' AS "efastTrxId"
               FROM "MapVietinTransaction"
              WHERE id = $1`,
            [plan.candidate.id],
          );
          if (
            transactionVerification.rows.length !== 1 ||
            transactionVerification.rows[0].efastTrxId !==
              plan.canonicalStatementNumber
          ) {
            throw new Error(
              `Post-update transaction verification failed for ${plan.candidate.id}`,
            );
          }
          const vietQrVerification = await client.query(
            `SELECT COUNT(*)::int AS count
               FROM "VietQrPaymentIntent"
              WHERE "matchedTransactionId" = $1
                AND "matchedTransactionNumber" IS DISTINCT FROM $2`,
            [plan.candidate.id, plan.canonicalStatementNumber],
          );
          if (vietQrVerification.rows[0]?.count !== 0) {
            throw new Error(
              `Post-update VietQR verification failed for ${plan.candidate.id}`,
            );
          }
        }
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      }
    }

    console.log(
      JSON.stringify({
        event: 'ops12_repair_succeeded',
        mode: args.apply ? 'apply' : 'dry-run',
        evidenceRows: evidenceRows.length,
        ready: plans.length,
        missing,
        ambiguous,
        conflict,
        updated,
        vietQrUpdated,
        brokenReferences: 0,
        verificationFailures: 0,
        inputSha256,
        checkpoint,
        durationMs: Date.now() - startedAt,
      }),
    );
  } finally {
    await client.end();
  }
}

const isEntrypoint =
  process.argv[1] &&
  path.resolve(process.argv[1]) ===
    path.resolve(fileURLToPath(import.meta.url));
if (isEntrypoint) {
  run().catch((error) => {
    console.error(
      JSON.stringify({
        event: 'ops12_repair_failed',
        error: text(error?.message || error).slice(0, 500),
      }),
    );
    process.exitCode = 1;
  });
}
