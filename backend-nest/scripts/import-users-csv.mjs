import { readCsvRows, pick } from './csv-utils.mjs';
import { createPrismaClient } from './prisma-local.mjs';

const csvPath = process.argv[2];

if (!csvPath) {
  console.error('Usage: npm run import:users -- ./users.csv');
  console.error(
    'Headers: email, first_name, last_name, role, status, branch_id, branch_name',
  );
  process.exit(1);
}

const rows = await readCsvRows(csvPath);
const { prisma, close } = createPrismaClient();

let userCount = 0;
let storeCount = 0;

try {
  for (const row of rows) {
    const email = pick(row, ['email', 'Email']).trim().toLowerCase();
    if (!email) {
      continue;
    }

    const branchId = pick(row, ['branch_id', 'storeId', 'store_id']).trim();
    const branchName = pick(row, [
      'branch_name',
      'storeName',
      'store_name',
    ]).trim();

    let storeUuid = null;
    if (branchId) {
      const store = await prisma.store.upsert({
        where: { storeId: branchId },
        update: { storeName: branchName || branchId },
        create: { storeId: branchId, storeName: branchName || branchId },
      });
      storeUuid = store.id;
      storeCount++;
    }

    await prisma.user.upsert({
      where: { email },
      update: {
        firstName: pick(row, ['first_name', 'firstName']) || undefined,
        lastName: pick(row, ['last_name', 'lastName']) || undefined,
        role: parseRole(pick(row, ['role', 'Role']).toUpperCase()),
        status: pick(row, ['status'], 'yes').toLowerCase(),
        storeId: storeUuid,
      },
      create: {
        email,
        password: '',
        firstName: pick(row, ['first_name', 'firstName']) || email.split('@')[0],
        lastName: pick(row, ['last_name', 'lastName']) || null,
        role: parseRole(pick(row, ['role', 'Role']).toUpperCase()),
        status: pick(row, ['status'], 'yes').toLowerCase(),
        storeId: storeUuid,
      },
    });
    userCount++;
  }

  console.log(`Imported ${userCount} users and touched ${storeCount} stores`);
} finally {
  await close();
}

function parseRole(role) {
  return ['SUPER_ADMIN', 'ADMIN', 'MANAGER', 'STAFF'].includes(role)
    ? role
    : 'STAFF';
}
