import 'dotenv/config';
import bcrypt from 'bcrypt';
import { chmod, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createPrismaClient } from './prisma-local.mjs';

const REQUIRED_CONFIRMATION = 'PREPARE_OPSHUB_STAGING_LOAD_USERS';
const REQUIRED_PUBLIC_URL = 'https://opshub-staging.hoanghochoi.com';
const SOURCE_EMAIL = 'staging.staff@phongvu.vn';
const OUTPUT_ROOT = path.resolve('/output');
const USER_COUNT = 60;
const RANGE_DAYS = 90;
const LOAD_FEATURE_CODES = [
  'HOME_DASHBOARD_SALES',
  'HOME_DASHBOARD_FINANCE',
];
const ALLOWED_DELETE_REFERENCE_TABLES = new Set([
  'FeatureAccessRule',
  'UserFeatureAssignment',
  'UserOrganizationAssignment',
  'UserPlatformSession',
]);
const BLOCKING_NON_FK_REFERENCES = [
  {
    table: 'MapVietinTransaction',
    idColumns: ['orderUpdatedByUserId'],
    emailColumns: ['orderUpdatedByEmail'],
  },
  {
    table: 'MapVietinTransactionOrderAudit',
    idColumns: ['changedByUserId'],
    emailColumns: ['changedByEmail'],
  },
  {
    table: 'MapVietinStatementOrderTransferRequest',
    idColumns: ['requestedByUserId', 'reviewedByUserId'],
    emailColumns: ['requestedByEmail', 'reviewedByEmail'],
  },
  {
    table: 'OffsetAdjustment',
    idColumns: ['createdByUserId', 'reviewedByUserId'],
    emailColumns: ['createdByEmail', 'reviewedByEmail'],
  },
  {
    table: 'OffsetAdjustmentHistory',
    idColumns: ['actorUserId'],
    emailColumns: ['actorEmail'],
  },
  {
    table: 'PaymentNotificationDeliveryLog',
    idColumns: ['userId'],
    emailColumns: [],
  },
  { table: 'AppLog', idColumns: ['userId'], emailColumns: [] },
  {
    table: 'PasswordResetToken',
    idColumns: ['createdByUserId'],
    emailColumns: ['email', 'createdByEmail'],
  },
  {
    table: 'UserOrganizationAssignment',
    idColumns: ['assignedById'],
    emailColumns: [],
  },
  {
    table: 'UserFeatureAssignment',
    idColumns: ['assignedById'],
    emailColumns: [],
  },
  {
    table: 'OrganizationNodeFeatureAssignment',
    idColumns: ['assignedById'],
    emailColumns: [],
  },
  { table: 'MediaObject', idColumns: ['uploaderId'], emailColumns: [] },
  {
    table: 'SalesReport',
    idColumns: ['createdByUserId', 'submittedByUserId'],
    emailColumns: ['createdByEmail', 'submittedByEmail'],
  },
  {
    table: 'SalesReportFollowUpCase',
    idColumns: ['assigneeUserId', 'lastFollowUpByUserId'],
    emailColumns: ['assigneeEmail', 'lastFollowUpByEmail'],
  },
  {
    table: 'SalesReportFollowUpEntry',
    idColumns: ['actorUserId'],
    emailColumns: ['actorEmail'],
  },
  {
    table: 'SalesReportFollowUpEvent',
    idColumns: ['actorUserId', 'fromAssigneeUserId', 'toAssigneeUserId'],
    emailColumns: ['actorEmail'],
  },
  {
    table: 'SalesReportErpOrderCache',
    idColumns: ['sourceUserId'],
    emailColumns: ['sourceUserEmail', 'consultantEmail', 'sellerEmail'],
  },
  {
    table: 'SalesTarget',
    idColumns: ['updatedByUserId'],
    emailColumns: ['updatedByEmail'],
  },
  {
    table: 'HomeSummaryOrderFact',
    idColumns: ['sourceUserId', 'reportCreatedByUserId'],
    emailColumns: [
      'sourceUserEmail',
      'consultantEmail',
      'sellerEmail',
      'reportCreatedByEmail',
    ],
  },
  {
    table: 'HomeSummaryReportFact',
    idColumns: ['createdByUserId'],
    emailColumns: ['createdByEmail'],
  },
  {
    table: 'HelpContentPage',
    idColumns: ['updatedByUserId'],
    emailColumns: ['updatedByEmail'],
  },
];

function requiredArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  const value = index < 0 ? null : process.argv[index + 1]?.trim();
  if (!value) throw new Error(`Missing required argument: --${name}`);
  return value;
}

function assertStagingTarget() {
  if (String(process.env.OPSHUB_STAGING).toLowerCase() !== 'true') {
    throw new Error('OPSHUB_STAGING=true is required');
  }
  if (process.env.OPSHUB_STAGING_SANITIZE_CONFIRM !== 'opshub-staging') {
    throw new Error(
      'OPSHUB_STAGING_SANITIZE_CONFIRM is not the staging sentinel',
    );
  }
  if (
    String(
      process.env.OPSHUB_STAGING_LOAD_MAINTENANCE_ENABLED,
    ).toLowerCase() !== 'true'
  ) {
    throw new Error('OPSHUB_STAGING_LOAD_MAINTENANCE_ENABLED=true is required');
  }
  const publicUrl = new URL(String(process.env.PUBLIC_BASE_URL || ''));
  if (
    publicUrl.origin !== REQUIRED_PUBLIC_URL ||
    publicUrl.pathname !== '/' ||
    publicUrl.search ||
    publicUrl.hash
  ) {
    throw new Error(`PUBLIC_BASE_URL must equal ${REQUIRED_PUBLIC_URL}`);
  }
  if (process.env.OPSHUB_DOMAIN !== publicUrl.hostname) {
    throw new Error('OPSHUB_DOMAIN must match the staging public hostname');
  }
}

function normalizeRunId(value) {
  const runId = value.toLowerCase();
  if (!/^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])?$/.test(runId)) {
    throw new Error(
      '--run-id must be 3-32 lowercase letters, numbers, or hyphens',
    );
  }
  return runId;
}

function emailPrefix(runId) {
  return `staging.load.${runId}.`;
}

function emailFor(runId, index) {
  return `${emailPrefix(runId)}${String(index).padStart(3, '0')}@phongvu.vn`;
}

function expectedRunEmails(runId) {
  return Array.from({ length: USER_COUNT }, (_, index) =>
    emailFor(runId, index + 1),
  );
}

function assertExactRunUsers(users, runId) {
  if (users.length !== USER_COUNT) {
    throw new Error(
      `Expected exactly ${USER_COUNT} run accounts but found ${users.length}; operation stopped`,
    );
  }
  const expected = new Set(expectedRunEmails(runId));
  for (const user of users) {
    if (!expected.delete(user.email)) {
      throw new Error(
        'Run prefix contains an unexpected account; cleanup stopped',
      );
    }
  }
  if (expected.size !== 0) {
    throw new Error('Run account set is incomplete; operation stopped');
  }
}

function dateKey(value) {
  return new Date(value).toISOString().slice(0, 10);
}

function priorDate(value, days) {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return dateKey(date);
}

async function selectCompleteHomeWindow(prisma) {
  const [states, aggregates] = await Promise.all([
    prisma.homeSummaryProjectionState.findMany({
      where: { status: 'COMPLETE', generatedAt: { not: null } },
      orderBy: { summaryDate: 'desc' },
      take: 400,
      select: { summaryDate: true },
    }),
    prisma.homeSummaryDailyAggregate.findMany({
      where: { dimensionType: 'GLOBAL', dimensionKey: '', storeCode: '' },
      orderBy: { summaryDate: 'desc' },
      take: 400,
      select: { summaryDate: true },
    }),
  ]);
  const completeDates = new Set(states.map((row) => dateKey(row.summaryDate)));
  const aggregateDates = new Set(
    aggregates.map((row) => dateKey(row.summaryDate)),
  );
  for (const state of states) {
    const endDate = dateKey(state.summaryDate);
    let complete = true;
    for (let offset = 0; offset < RANGE_DAYS; offset += 1) {
      const candidate = priorDate(endDate, offset);
      if (!completeDates.has(candidate) || !aggregateDates.has(candidate)) {
        complete = false;
        break;
      }
    }
    if (complete) return endDate;
  }
  throw new Error(
    'No contiguous 90-day COMPLETE Home projection window with GLOBAL aggregates exists',
  );
}

async function createUsers(prisma, runId, passwordHash) {
  const source = await prisma.user.findUnique({
    where: { email: SOURCE_EMAIL },
    select: {
      id: true,
      status: true,
      role: true,
      storeId: true,
      profileCompletedAt: true,
      branchLockedAt: true,
      departmentCode: true,
      jobRoleCode: true,
      workScopeType: true,
      regionCode: true,
      areaCode: true,
      organizationNodeId: true,
    },
  });
  if (
    !source ||
    source.status !== 'yes' ||
    source.role !== 'STAFF' ||
    !source.storeId ||
    !source.profileCompletedAt ||
    !source.branchLockedAt
  ) {
    throw new Error('The active STAFF staging source account is unavailable');
  }
  const broadScalarScope = [
    source.departmentCode,
    source.jobRoleCode,
    source.workScopeType,
    source.regionCode,
    source.areaCode,
    source.organizationNodeId,
  ].some((value) => value !== null);
  const [
    activeOrganizationAssignments,
    enabledUserFeatures,
    featureRules,
    policyRules,
  ] = await Promise.all([
    prisma.userOrganizationAssignment.count({
      where: { userId: source.id, isActive: true },
    }),
    prisma.userFeatureAssignment.count({
      where: { userId: source.id, enabled: true },
    }),
    prisma.featureAccessRule.count({ where: { userId: source.id } }),
    prisma.adminPolicyRule.count({ where: { userId: source.id } }),
  ]);
  if (
    broadScalarScope ||
    activeOrganizationAssignments !== 0 ||
    enabledUserFeatures !== 0 ||
    featureRules !== 0 ||
    policyRules !== 0
  ) {
    throw new Error(
      'The staging source account exceeds the minimal store-only Home/auth/realtime scope; no users were created',
    );
  }
  const collisions = await prisma.user.count({
    where: { email: { startsWith: emailPrefix(runId) } },
  });
  if (collisions > 0) {
    throw new Error('Run id already has staging load accounts; cleanup first');
  }
  const features = await prisma.featureDefinition.findMany({
    where: { code: { in: LOAD_FEATURE_CODES } },
    select: { code: true },
  });
  const availableFeatures = new Set(features.map((feature) => feature.code));
  const missingFeatures = LOAD_FEATURE_CODES.filter(
    (featureCode) => !availableFeatures.has(featureCode),
  );
  if (missingFeatures.length > 0) {
    throw new Error(
      `Required Home load feature definitions are missing: ${missingFeatures.join(', ')}`,
    );
  }

  await prisma.$transaction(
    async (tx) => {
      for (let index = 1; index <= USER_COUNT; index += 1) {
        const user = await tx.user.create({
          data: {
            email: emailFor(runId, index),
            password: passwordHash,
            tokenVersion: 0,
            firstName: 'Staging Load',
            lastName: `${runId} ${String(index).padStart(3, '0')}`,
            role: 'STAFF',
            status: 'yes',
            avatarUrl: null,
            profileCompletedAt: source.profileCompletedAt,
            branchLockedAt: source.branchLockedAt,
            storeId: source.storeId,
          },
          select: { id: true },
        });
        await tx.userFeatureAssignment.createMany({
          data: LOAD_FEATURE_CODES.map((featureCode) => ({
            userId: user.id,
            featureCode,
            enabled: true,
            note: `staging-load:${runId}`,
          })),
        });
      }
    },
    { maxWait: 10_000, timeout: 120_000 },
  );
}

function internalApiUrl() {
  const url = new URL(
    String(process.env.OPSHUB_STAGING_INTERNAL_API_URL || 'http://api:3000'),
  );
  if (
    url.protocol !== 'http:' ||
    url.hostname !== 'api' ||
    url.port !== '3000' ||
    url.pathname !== '/'
  ) {
    throw new Error(
      'OPSHUB_STAGING_INTERNAL_API_URL must equal http://api:3000',
    );
  }
  return url.origin;
}

async function issueTokens(runId, password) {
  const records = [];
  const baseUrl = internalApiUrl();
  for (let index = 1; index <= USER_COUNT; index += 1) {
    const response = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: emailFor(runId, index),
        password,
        platform: 'windows',
        deviceId: `opshub-load-${runId}-${String(index).padStart(3, '0')}`,
        deviceLabel: 'Staging load proof',
        appVersion: 'staging-load',
        buildNumber: runId,
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      throw new Error(`Token issue failed at user index ${index}`);
    }
    const body = await response.json();
    const token = String(body?.access_token || '');
    if (!token)
      throw new Error(`Token response missing at user index ${index}`);
    records.push({ index, token, storeCode: body?.storeId ?? null });
  }
  return records;
}

function assertOutputPath(outputArg, runId) {
  const output = path.resolve(outputArg);
  if (
    path.dirname(output) !== OUTPUT_ROOT ||
    path.basename(output) !== `${runId}.tokens.json`
  ) {
    throw new Error(`--output must equal /output/${runId}.tokens.json`);
  }
  return output;
}

async function writeTokenFile(output, payload) {
  const temporary = `${output}.tmp`;
  await rm(temporary, { force: true });
  await writeFile(temporary, `${JSON.stringify(payload)}\n`, {
    encoding: 'utf8',
    flag: 'wx',
    mode: 0o600,
  });
  await chmod(temporary, 0o600);
  await rename(temporary, output);
  await chmod(output, 0o600);
}

async function revokeRun(prisma, runId) {
  const users = await prisma.user.findMany({
    where: { email: { startsWith: emailPrefix(runId) } },
    select: { id: true, email: true },
  });
  assertExactRunUsers(users, runId);
  const ids = users.map((user) => user.id);
  const now = new Date();
  return prisma.$transaction(async (tx) => {
    const updated = await tx.user.updateMany({
      where: { id: { in: ids } },
      data: { status: 'no', tokenVersion: { increment: 1 } },
    });
    const sessions = await tx.userPlatformSession.updateMany({
      where: { userId: { in: ids }, revokedAt: null },
      data: { revokedAt: now, revokedReason: 'STAGING_LOAD_COMPLETE' },
    });
    const revoked = await tx.user.count({
      where: { id: { in: ids }, status: 'no' },
    });
    if (updated.count !== USER_COUNT || revoked !== USER_COUNT) {
      throw new Error(
        `Revoke verification failed: updated=${updated.count} revoked=${revoked}`,
      );
    }
    return { revoked, sessions: sessions.count };
  });
}

function quoteIdentifier(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

async function countKnownNonFkReferences(prisma, userIds, emails) {
  const found = [];
  for (const reference of BLOCKING_NON_FK_REFERENCES) {
    const conditions = [];
    const values = [];
    if (userIds.length > 0 && reference.idColumns.length > 0) {
      values.push(userIds);
      conditions.push(
        ...reference.idColumns.map(
          (column) =>
            `${quoteIdentifier(column)} = ANY($${values.length}::text[])`,
        ),
      );
    }
    if (emails.length > 0 && reference.emailColumns.length > 0) {
      values.push(emails);
      conditions.push(
        ...reference.emailColumns.map(
          (column) =>
            `${quoteIdentifier(column)} = ANY($${values.length}::text[])`,
        ),
      );
    }
    if (conditions.length === 0) continue;
    const query = `SELECT COUNT(*)::int AS count FROM ${quoteIdentifier(reference.table)} WHERE ${conditions.join(' OR ')}`;
    const rows = await prisma.$queryRawUnsafe(query, ...values);
    const count = Number(rows[0]?.count || 0);
    if (count > 0) found.push({ table: reference.table, count });
  }
  return found;
}

async function assertNoBusinessReferences(prisma, userIds, emails) {
  const references = await prisma.$queryRaw`
    SELECT tc.table_name AS "tableName", kcu.column_name AS "columnName"
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name
     AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public'
      AND ccu.table_name = 'User'
      AND ccu.column_name = 'id'
  `;
  for (const reference of references) {
    if (ALLOWED_DELETE_REFERENCE_TABLES.has(reference.tableName)) continue;
    const query = `SELECT COUNT(*)::int AS count FROM ${quoteIdentifier(reference.tableName)} WHERE ${quoteIdentifier(reference.columnName)} = ANY($1::text[])`;
    const rows = await prisma.$queryRawUnsafe(query, userIds);
    if (Number(rows[0]?.count || 0) > 0) {
      throw new Error(
        `Cleanup stopped: synthetic users have rows in ${reference.tableName}`,
      );
    }
  }
  const nonFkReferences = await countKnownNonFkReferences(
    prisma,
    userIds,
    emails,
  );
  if (nonFkReferences.length > 0) {
    const summary = nonFkReferences
      .map((reference) => `${reference.table}:${reference.count}`)
      .join(',');
    throw new Error(
      `Cleanup stopped: synthetic users have audit or non-FK references (${summary})`,
    );
  }
}

async function deleteRun(prisma, runId) {
  const users = await prisma.user.findMany({
    where: { email: { startsWith: emailPrefix(runId) } },
    select: { id: true, email: true, status: true },
  });
  assertExactRunUsers(users, runId);
  if (users.some((user) => user.status !== 'no')) {
    throw new Error('Cleanup stopped: revoke the run before delete');
  }
  const ids = users.map((user) => user.id);
  const emails = users.map((user) => user.email);
  const activeSessions = await prisma.userPlatformSession.count({
    where: { userId: { in: ids }, revokedAt: null },
  });
  if (activeSessions > 0) {
    throw new Error('Cleanup stopped: active synthetic sessions remain');
  }
  await assertNoBusinessReferences(prisma, ids, emails);
  const deleted = await prisma.$transaction(async (tx) => {
    await tx.adminPolicyRule.deleteMany({ where: { userId: { in: ids } } });
    await tx.featureAccessRule.deleteMany({ where: { userId: { in: ids } } });
    await tx.userFeatureAssignment.deleteMany({
      where: { userId: { in: ids } },
    });
    await tx.userOrganizationAssignment.deleteMany({
      where: { userId: { in: ids } },
    });
    await tx.userPlatformSession.deleteMany({ where: { userId: { in: ids } } });
    await tx.passwordResetToken.deleteMany({ where: { userId: { in: ids } } });
    await tx.emailVerificationCode.deleteMany({
      where: { email: { in: emails } },
    });
    return tx.user.deleteMany({ where: { id: { in: ids } } });
  });
  const remaining = await prisma.user.count({
    where: { email: { startsWith: emailPrefix(runId) } },
  });
  const remainingRelated =
    (await prisma.adminPolicyRule.count({ where: { userId: { in: ids } } })) +
    (await prisma.featureAccessRule.count({ where: { userId: { in: ids } } })) +
    (await prisma.userFeatureAssignment.count({
      where: { userId: { in: ids } },
    })) +
    (await prisma.userOrganizationAssignment.count({
      where: { userId: { in: ids } },
    })) +
    (await prisma.userPlatformSession.count({
      where: { userId: { in: ids } },
    }));
  if (
    remaining !== 0 ||
    remainingRelated !== 0 ||
    deleted.count !== USER_COUNT
  ) {
    throw new Error(
      `Cleanup verification failed: deleted=${deleted.count} remaining=${remaining} related=${remainingRelated}`,
    );
  }
  const empty = await verifyEmpty(prisma, runId);
  return { deleted: deleted.count, ...empty };
}

async function verifyEmpty(prisma, runId) {
  const emails = expectedRunEmails(runId);
  const note = `staging-load:${runId}`;
  const [
    remaining,
    taggedPolicy,
    taggedFeature,
    taggedUserFeature,
    taggedOrg,
    codes,
  ] = await Promise.all([
    prisma.user.count({
      where: { email: { startsWith: emailPrefix(runId) } },
    }),
    prisma.adminPolicyRule.count({ where: { note } }),
    prisma.featureAccessRule.count({ where: { note } }),
    prisma.userFeatureAssignment.count({ where: { note } }),
    prisma.userOrganizationAssignment.count({ where: { note } }),
    prisma.emailVerificationCode.count({ where: { email: { in: emails } } }),
  ]);
  const tagged = taggedPolicy + taggedFeature + taggedUserFeature + taggedOrg;
  const knownReferences = await countKnownNonFkReferences(prisma, [], emails);
  if (
    remaining !== 0 ||
    tagged !== 0 ||
    codes !== 0 ||
    knownReferences.length !== 0
  ) {
    throw new Error(
      `Empty-state verification failed: users=${remaining} tagged=${tagged} emailCodes=${codes} knownReferences=${knownReferences.length}`,
    );
  }
  return {
    remaining,
    remainingTagged: tagged,
    remainingEmailCodes: codes,
    remainingKnownReferences: 0,
  };
}

async function prepare(prisma, runId, output) {
  const password = String(process.env.STAGING_TEST_PASSWORD || '').trim();
  if (
    password.length < 10 ||
    !/[A-Z]/.test(password) ||
    !/[0-9]/.test(password) ||
    !/[!@#$%^&*(),.?":{}|<>]/.test(password)
  ) {
    throw new Error('STAGING_TEST_PASSWORD does not satisfy the login policy');
  }
  const homeEndDate = await selectCompleteHomeWindow(prisma);
  const passwordHash = await bcrypt.hash(password, 12);
  await createUsers(prisma, runId, passwordHash);
  try {
    const users = await issueTokens(runId, password);
    await writeTokenFile(output, {
      schemaVersion: 1,
      runId,
      generatedAt: new Date().toISOString(),
      homeEndDate,
      users,
    });
    return { users: users.length, homeEndDate, tokenFileMode: '0600' };
  } catch (error) {
    try {
      await revokeRun(prisma, runId);
      await deleteRun(prisma, runId);
    } finally {
      await rm(output, { force: true });
      await rm(`${output}.tmp`, { force: true });
    }
    throw error;
  }
}

async function main() {
  assertStagingTarget();
  const action = requiredArg('action').toLowerCase();
  if (!['prepare', 'revoke', 'delete', 'verify-empty'].includes(action)) {
    throw new Error(
      '--action must be prepare, revoke, delete, or verify-empty',
    );
  }
  const runId = normalizeRunId(requiredArg('run-id'));
  if (requiredArg('confirm') !== REQUIRED_CONFIRMATION) {
    throw new Error(`--confirm must equal ${REQUIRED_CONFIRMATION}`);
  }
  const output =
    action === 'prepare'
      ? assertOutputPath(requiredArg('output'), runId)
      : null;
  const { prisma, close } = createPrismaClient();
  try {
    const result =
      action === 'prepare'
        ? await prepare(prisma, runId, output)
        : action === 'revoke'
          ? await revokeRun(prisma, runId)
          : action === 'delete'
            ? await deleteRun(prisma, runId)
            : await verifyEmpty(prisma, runId);
    process.stdout.write(
      `${JSON.stringify({ ok: true, action, runId, ...result })}\n`,
    );
  } finally {
    await close();
  }
}

main().catch((error) => {
  const safeMessage = String(error?.message ?? error)
    .replace(/postgres(?:ql)?:\/\/[^@\s]+@/gi, 'postgresql://[redacted]@')
    .replace(/redis(?:s)?:\/\/[^@\s]+@/gi, 'redis://[redacted]@')
    .replace(/Bearer\s+\S+/gi, 'Bearer [redacted]');
  process.stderr.write(`Staging load-user operation failed: ${safeMessage}\n`);
  process.exitCode = 1;
});
