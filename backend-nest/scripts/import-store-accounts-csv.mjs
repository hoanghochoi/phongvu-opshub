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
    const storeName = pick(row, [
      'store_name',
      'storeName',
      'branch_name',
      'branchName',
    ]);
    const updateData = {
      transferAccountNumber: pick(row, ['account']) || null,
      transferAccountName: pick(row, ['account_name', 'accountName']) || null,
      transferBankName: pick(row, ['account_bank', 'accountBank']) || null,
      transferBankBin:
        pick(row, ['account_bank_bin', 'accountBankBin', 'bank_bin']) || null,
    };
    if (storeName) {
      updateData.storeName = storeName;
    }

    await prisma.store.upsert({
      where: { storeId },
      update: updateData,
      create: {
        storeId,
        storeName: storeName || storeId,
        transferAccountNumber: pick(row, ['account']) || null,
        transferAccountName: pick(row, ['account_name', 'accountName']) || null,
        transferBankName: pick(row, ['account_bank', 'accountBank']) || null,
        transferBankBin:
          pick(row, ['account_bank_bin', 'accountBankBin', 'bank_bin']) || null,
      },
    });
    count++;
  }

  console.log(`Imported ${count} store account rows from ${csvPath}`);
} finally {
  await close();
}
