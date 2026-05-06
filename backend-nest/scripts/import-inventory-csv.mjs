import { readCsvRows, pick } from './csv-utils.mjs';
import { createPrismaClient } from './prisma-local.mjs';

const csvPath = process.argv[2];
const replace = process.argv.includes('--replace');

if (!csvPath || !replace) {
  console.error('Usage: npm run import:inventory -- ./inventory.csv --replace');
  console.error(
    'Headers: sku, sku_name, serial_number, bin, zone, import_date, count',
  );
  process.exit(1);
}

const rows = await readCsvRows(csvPath);
const data = rows
  .filter((row) => pick(row, ['sku', 'SKU']))
  .map((row) => ({
    sku: pick(row, ['sku', 'SKU']).trim(),
    skuName: pick(row, ['sku_name', 'skuName', 'SKU_NAME']).trim(),
    serialNumber: pick(row, [
      'serial_number',
      'serialNumber',
      'SERIAL_NUMBER',
    ]) || null,
    bin: pick(row, ['bin', 'bin_id', 'BIN']) || null,
    zone: pick(row, ['zone', 'ZONE']) || null,
    importDate: parseDate(
      pick(row, [
        'import_date',
        'importDate',
        'import_date_company',
        'IMPORT_DATE',
      ]),
    ),
    count: parseCount(pick(row, ['count', 'qty', 'COUNT', 'QTY'])),
  }));

const { prisma, close } = createPrismaClient();

try {
  await prisma.$transaction(async (tx) => {
    await tx.inventory.deleteMany();
    for (let i = 0; i < data.length; i += 1000) {
      await tx.inventory.createMany({ data: data.slice(i, i + 1000) });
    }
  });
  console.log(`Imported ${data.length} inventory rows from ${csvPath}`);
} finally {
  await close();
}

function parseCount(value) {
  const parsed = Number.parseInt(value || '1', 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
}

function parseDate(value) {
  if (!value) {
    return null;
  }

  const normalized = value.trim();
  const ddmmyyyy = normalized.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  const date = ddmmyyyy
    ? new Date(
        Number(ddmmyyyy[3]),
        Number(ddmmyyyy[2]) - 1,
        Number(ddmmyyyy[1]),
      )
    : new Date(normalized);

  return Number.isNaN(date.getTime()) ? null : date;
}
