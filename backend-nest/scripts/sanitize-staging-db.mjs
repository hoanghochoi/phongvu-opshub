import 'dotenv/config';
import bcrypt from 'bcrypt';
import { createPrismaClient } from './prisma-local.mjs';

const REQUIRED_CONFIRM = 'opshub-staging';
const KNOWN_USERS = [
  {
    email: 'staging.admin@phongvu.vn',
    firstName: 'Staging Admin',
    lastName: 'OpsHub',
    role: 'SUPER_ADMIN',
    storeScoped: false,
  },
  {
    email: 'staging.staff@phongvu.vn',
    firstName: 'Staging Staff',
    lastName: 'PhongVu',
    role: 'STAFF',
    storeScoped: true,
  },
  {
    email: 'staging.acare@acaretek.vn',
    firstName: 'Staging ACare',
    lastName: 'Admin',
    role: 'ADMIN_ACARE',
    storeScoped: true,
  },
];

const knownEmails = new Set(KNOWN_USERS.map((user) => user.email));

assertStagingTarget();

const testPassword = process.env.STAGING_TEST_PASSWORD?.trim();
if (!testPassword || testPassword.length < 10) {
  fail('STAGING_TEST_PASSWORD must be set and contain at least 10 characters.');
}

const { prisma, close } = createPrismaClient();

try {
  const passwordHash = await bcrypt.hash(testPassword, 12);
  const counts = {};

  counts.sessions = await deleteMany('userPlatformSession');
  counts.passwordResetTokens = await deleteMany('passwordResetToken');
  counts.emailVerificationCodes = await deleteMany('emailVerificationCode');
  counts.appLogs = await deleteMany('appLog');
  counts.paymentDeliveryLogs = await deleteMany('paymentNotificationDeliveryLog');

  counts.stores = await prisma.store.updateMany({
    data: {
      transferAccountNumber: null,
      transferAccountName: null,
      transferBankName: null,
      transferBankBin: null,
      mapVietinUsername: null,
      mapVietinPasswordCipher: null,
    },
  });

  counts.paymentNotifications = await prisma.paymentNotification.updateMany({
    data: {
      text: 'Staging payment notification',
      audioStatus: 'SANITIZED',
      audioPath: null,
      audioMime: null,
      audioError: null,
    },
  });

  counts.mapTransactions = await prisma.mapVietinTransaction.updateMany({
    data: {
      transactionNumber: null,
      content: 'Staging MAP transaction content',
      orders: [],
      orderSource: null,
      orderUpdatedByEmail: null,
      payerName: 'Staging payer',
      payerAccount: null,
      rawData: { sanitized: true, source: 'staging' },
    },
  });

  counts.mapTransactionAudits = await prisma.mapVietinTransactionOrderAudit.updateMany({
    data: {
      oldOrders: [],
      newOrders: [],
      changedByUserId: null,
      changedByEmail: null,
      source: 'SANITIZED',
    },
  });

  counts.unmappedMapTransactions = await prisma.mapVietinUnmappedTransaction.updateMany({
    data: {
      virtualAccount: null,
      transactionNumber: null,
      content: 'Staging unmapped MAP transaction content',
      payerName: 'Staging payer',
      payerAccount: null,
      rawData: { sanitized: true, source: 'staging' },
    },
  });

  counts.mapSyncState = await prisma.mapVietinSyncState.updateMany({
    data: {
      lastError: null,
    },
  });

  counts.vietQrIntents = await prisma.vietQrPaymentIntent.updateMany({
    data: {
      orderCode: null,
      transferContent: 'OPSHUB-STAGING',
      qrPayload: 'SANITIZED_STAGING_QR_PAYLOAD',
      matchedTransactionNumber: null,
      matchedPayerName: null,
      matchedPayerAccount: null,
      matchedTransactionContent: null,
      lastCheckResult: { sanitized: true, source: 'staging' },
    },
  });

  counts.warranties = await prisma.warranty.updateMany({
    data: {
      customerName: 'Staging customer',
      customerPhone: '0900000000',
      serialNumber: null,
      issue: 'Staging warranty issue',
      note: null,
      imageLinks: null,
    },
  });

  counts.feedbacks = await prisma.feedback.updateMany({
    data: {
      content: 'Staging feedback content',
    },
  });

  counts.fifoLogs = await prisma.fifoLog.updateMany({
    data: {
      query: 'STAGING_QUERY',
      result: 'Staging FIFO result',
      resultJson: { sanitized: true, source: 'staging' },
    },
  });

  counts.sensitiveSettings = await prisma.adminSetting.updateMany({
    where: { isSensitive: true },
    data: { value: { sanitized: true, source: 'staging' } },
  });

  const store = await ensureStore();
  await ensureRoles();
  counts.users = await sanitizeUsers(passwordHash);
  counts.knownUsers = await ensureKnownUsers(store.id, passwordHash);

  await verifySanitizer();

  console.log(JSON.stringify(normalizeCounts(counts), null, 2));
  console.log('Staging database sanitization completed.');
} finally {
  await close();
}

function assertStagingTarget() {
  if (process.env.OPSHUB_STAGING_SANITIZE_CONFIRM !== REQUIRED_CONFIRM) {
    fail(`Refusing to run. Set OPSHUB_STAGING_SANITIZE_CONFIRM=${REQUIRED_CONFIRM}.`);
  }
  if (process.env.OPSHUB_STAGING !== 'true') {
    fail('Refusing to run. OPSHUB_STAGING must be true.');
  }
  const publicBaseUrl = process.env.PUBLIC_BASE_URL || '';
  if (!publicBaseUrl.includes('opshub-staging.hoanghochoi.com')) {
    fail('Refusing to run. PUBLIC_BASE_URL must point to opshub-staging.hoanghochoi.com.');
  }
}

async function deleteMany(modelName) {
  const result = await prisma[modelName].deleteMany();
  return result.count;
}

async function ensureStore() {
  const existing = await prisma.store.findFirst({ orderBy: { storeId: 'asc' } });
  if (existing) return existing;
  return prisma.store.create({
    data: {
      storeId: 'STG01',
      storeName: 'Staging Store',
    },
  });
}

async function ensureRoles() {
  for (const user of KNOWN_USERS) {
    await prisma.roleDefinition.upsert({
      where: { code: user.role },
      update: {},
      create: {
        code: user.role,
        displayName: user.role.replaceAll('_', ' '),
        isSystem: true,
      },
    });
  }
}

async function sanitizeUsers(passwordHash) {
  const users = await prisma.user.findMany({ orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] });
  let index = 1;
  let updated = 0;
  for (const user of users) {
    if (knownEmails.has(user.email)) continue;
    const suffix = String(index).padStart(4, '0');
    const emailDomain = user.role === 'ADMIN_ACARE' ? 'acaretek.vn' : 'phongvu.vn';
    await prisma.user.update({
      where: { id: user.id },
      data: {
        email: `staging.user${suffix}@${emailDomain}`,
        password: passwordHash,
        tokenVersion: 0,
        firstName: 'Staging',
        lastName: `User ${suffix}`,
        avatarUrl: null,
      },
    });
    index += 1;
    updated += 1;
  }
  return updated;
}

async function ensureKnownUsers(storeId, passwordHash) {
  let count = 0;
  for (const user of KNOWN_USERS) {
    await prisma.user.upsert({
      where: { email: user.email },
      update: knownUserData(user, storeId, passwordHash),
      create: {
        email: user.email,
        ...knownUserData(user, storeId, passwordHash),
      },
    });
    count += 1;
  }
  return count;
}

function knownUserData(user, storeId, passwordHash) {
  return {
    password: passwordHash,
    tokenVersion: 0,
    firstName: user.firstName,
    lastName: user.lastName,
    role: user.role,
    status: 'yes',
    avatarUrl: null,
    profileCompletedAt: new Date(),
    branchLockedAt: user.storeScoped ? new Date() : null,
    storeId: user.storeScoped ? storeId : null,
  };
}

async function verifySanitizer() {
  const activeSecrets = await prisma.store.count({
    where: {
      OR: [
        { mapVietinUsername: { not: null } },
        { mapVietinPasswordCipher: { not: null } },
        { transferAccountNumber: { not: null } },
      ],
    },
  });
  if (activeSecrets > 0) fail('Sanitizer verification failed: store secrets remain.');

  const remainingTokens =
    (await prisma.userPlatformSession.count()) +
    (await prisma.passwordResetToken.count()) +
    (await prisma.emailVerificationCode.count());
  if (remainingTokens > 0) fail('Sanitizer verification failed: auth tokens remain.');

  const knownUserCount = await prisma.user.count({
    where: { email: { in: Array.from(knownEmails) } },
  });
  if (knownUserCount !== knownEmails.size) {
    fail('Sanitizer verification failed: known staging users are missing.');
  }
}

function normalizeCounts(counts) {
  return Object.fromEntries(
    Object.entries(counts).map(([key, value]) => [key, typeof value === 'number' ? value : value.count]),
  );
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
