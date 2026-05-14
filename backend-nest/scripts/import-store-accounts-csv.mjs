import { readCsvRows, pick } from './csv-utils.mjs';
import { createPrismaClient } from './prisma-local.mjs';

const csvPath = process.argv[2] || '../data/store_account.csv';
const rows = await readCsvRows(csvPath);
const { prisma, close } = createPrismaClient();

let count = 0;

try {
  for (const row of rows) {
    const storeId = pick(row, ['store', 'storeId', 'store_id']).trim();
    if (!storeId) continue;

    await prisma.store.upsert({
      where: { storeId },
      update: {
        transferAccountNumber: pick(row, ['account']) || null,
        transferAccountName: pick(row, ['account_name', 'accountName']) || null,
        transferBankName: pick(row, ['account_bank', 'accountBank']) || null,
      },
      create: {
        storeId,
        storeName: storeId,
        transferAccountNumber: pick(row, ['account']) || null,
        transferAccountName: pick(row, ['account_name', 'accountName']) || null,
        transferBankName: pick(row, ['account_bank', 'accountBank']) || null,
      },
    });
    count++;
  }

  console.log(`Imported ${count} store account rows from ${csvPath}`);
} finally {
  await close();
}
