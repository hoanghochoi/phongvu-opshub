import 'dotenv/config';
import pg from 'pg';
import { createPrismaClient } from './prisma-local.mjs';

const N8N_TABLE =
  process.env.N8N_WARRANTY_TABLE || 'data_table_user_hY8m0IrB9V1iDQQw';
const IMAGE_BASE_URL = stripTrailingSlash(
  process.env.IMAGE_BASE_URL || 'https://opshub.hoanghochoi.com/uploads',
);
const APPLY = process.argv.includes('--apply');

if (!process.env.N8N_DATABASE_URL) {
  console.error('N8N_DATABASE_URL is required');
  process.exit(1);
}

const n8nPool = new pg.Pool({ connectionString: process.env.N8N_DATABASE_URL });
const { prisma, close } = createPrismaClient();

try {
  const n8nRows = await loadN8nWarrantyRows();
  const uniqueRows = latestRowByReceipt(n8nRows);
  const appReceipts = new Set(
    (await prisma.warranty.findMany({ select: { receipt: true } })).map(
      (row) => row.receipt,
    ),
  );
  const appUsers = new Map(
    (
      await prisma.user.findMany({
        select: {
          id: true,
          email: true,
          password: true,
          status: true,
          storeId: true,
        },
      })
    ).map((user) => [user.email.trim().toLowerCase(), user]),
  );
  const appStores = new Map(
    (await prisma.store.findMany({ select: { id: true, storeId: true } })).map(
      (store) => [store.storeId.trim().toUpperCase(), store],
    ),
  );

  const plan = buildPlan({ rows: uniqueRows, appReceipts, appUsers, appStores });
  printSummary('dryRun', plan.summary);

  if (!APPLY) {
    console.log('Dry run only. Re-run with --apply to write changes.');
    process.exit(0);
  }

  const applied = await applyPlan(plan.items);
  printSummary('applied', applied);
} finally {
  await n8nPool.end();
  await close();
}

async function loadN8nWarrantyRows() {
  const sql = `
    select receipt, "user" as legacy_user, links, "createdAt" as created_at, "updatedAt" as updated_at
    from "${N8N_TABLE.replace(/"/g, '""')}"
    where receipt is not null and btrim(receipt) <> ''
  `;
  const result = await n8nPool.query(sql);
  return result.rows;
}

function latestRowByReceipt(rows) {
  const byReceipt = new Map();
  for (const row of rows) {
    const receipt = normalizeReceipt(row.receipt);
    if (!receipt) continue;
    const current = byReceipt.get(receipt);
    if (!current || dateMs(row.updated_at) >= dateMs(current.updated_at)) {
      byReceipt.set(receipt, { ...row, receipt });
    }
  }
  return Array.from(byReceipt.values());
}

function buildPlan({ rows, appReceipts, appUsers, appStores }) {
  const items = [];
  const summary = {
    n8nRows: rows.length,
    existingWarrantyRows: 0,
    warrantyRowsToCreate: 0,
    legacyUsersToCreate: 0,
    legacyUsersAlreadyExist: 0,
    legacyLockedUsersToPatchStore: 0,
    storesToCreate: 0,
    rowsWithoutStorePrefix: 0,
    rowsWithInvalidUser: 0,
    rowsWithInvalidLinks: 0,
    linksToMigrate: 0,
  };
  const usersToCreate = new Set();
  const storesToCreate = new Set();
  const legacyUsersToPatchStore = new Set();

  for (const row of rows) {
    if (appReceipts.has(row.receipt)) {
      summary.existingWarrantyRows += 1;
      continue;
    }

    const email = normalizeEmail(row.legacy_user);
    if (!email) {
      summary.rowsWithInvalidUser += 1;
      continue;
    }

    const storeCode = inferStoreCode(row.receipt);
    if (!storeCode) summary.rowsWithoutStorePrefix += 1;
    if (storeCode && !appStores.has(storeCode)) storesToCreate.add(storeCode);

    const imageLinks = normalizeImageLinks(row.links);
    if (imageLinks.length === 0) {
      summary.rowsWithInvalidLinks += 1;
      continue;
    }

    const existingUser = appUsers.get(email);
    if (existingUser) {
      summary.legacyUsersAlreadyExist += 1;
      if (
        storeCode &&
        !existingUser.storeId &&
        existingUser.status === 'no' &&
        !existingUser.password
      ) {
        legacyUsersToPatchStore.add(email);
      }
    } else {
      usersToCreate.add(email);
    }

    summary.warrantyRowsToCreate += 1;
    summary.linksToMigrate += imageLinks.length;
    items.push({
      receipt: row.receipt,
      email,
      storeCode,
      imageLinks,
      createdAt: safeDate(row.created_at),
    });
  }

  summary.legacyUsersToCreate = usersToCreate.size;
  summary.storesToCreate = storesToCreate.size;
  summary.legacyLockedUsersToPatchStore = legacyUsersToPatchStore.size;
  return { items, summary };
}

async function applyPlan(items) {
  const summary = {
    storesCreatedOrTouched: 0,
    legacyUsersCreated: 0,
    legacyLockedUsersPatchedStore: 0,
    warrantyRowsCreated: 0,
    warrantyRowsSkippedExisting: 0,
    linksMigrated: 0,
  };

  await prisma.$transaction(async (tx) => {
    await tx.roleDefinition.upsert({
      where: { code: 'STAFF' },
      update: {},
      create: {
        code: 'STAFF',
        displayName: 'Staff',
        description: null,
        isSystem: true,
      },
    });

    const storeCache = new Map();
    const userCache = new Map();

    for (const item of items) {
      const existingWarranty = await tx.warranty.findUnique({
        where: { receipt: item.receipt },
        select: { id: true },
      });
      if (existingWarranty) {
        summary.warrantyRowsSkippedExisting += 1;
        continue;
      }

      const store = item.storeCode
        ? await resolveStore(tx, item.storeCode, storeCache, summary)
        : null;
      const user = await resolveLegacyUser(
        tx,
        item.email,
        store?.id ?? null,
        userCache,
        summary,
      );

      await tx.warranty.create({
        data: {
          receipt: item.receipt,
          imageLinks: item.imageLinks.join(';'),
          createdById: user.id,
          createdAt: item.createdAt,
        },
      });
      summary.warrantyRowsCreated += 1;
      summary.linksMigrated += item.imageLinks.length;
    }
  });

  return summary;
}

async function resolveStore(tx, storeCode, cache, summary) {
  if (cache.has(storeCode)) return cache.get(storeCode);
  const existing = await tx.store.findUnique({ where: { storeId: storeCode } });
  if (existing) {
    cache.set(storeCode, existing);
    return existing;
  }
  const created = await tx.store.create({
    data: { storeId: storeCode, storeName: storeCode },
  });
  summary.storesCreatedOrTouched += 1;
  cache.set(storeCode, created);
  return created;
}

async function resolveLegacyUser(tx, email, storeId, cache, summary) {
  if (cache.has(email)) return cache.get(email);

  const existing = await tx.user.findUnique({ where: { email } });
  if (existing) {
    if (storeId && !existing.storeId && existing.status === 'no' && !existing.password) {
      const patched = await tx.user.update({
        where: { id: existing.id },
        data: { storeId, workScopeType: existing.workScopeType || 'STORE' },
      });
      summary.legacyLockedUsersPatchedStore += 1;
      cache.set(email, patched);
      return patched;
    }
    cache.set(email, existing);
    return existing;
  }

  const created = await tx.user.create({
    data: {
      email,
      password: '',
      firstName: legacyFirstName(email),
      lastName: null,
      role: 'STAFF',
      status: 'no',
      storeId,
      workScopeType: storeId ? 'STORE' : null,
    },
  });
  summary.legacyUsersCreated += 1;
  cache.set(email, created);
  return created;
}

function normalizeReceipt(value) {
  const receipt = String(value || '').trim().toUpperCase();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(receipt)) return '';
  return receipt;
}

function normalizeEmail(value) {
  const email = String(value || '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return '';
  return email;
}

function inferStoreCode(receipt) {
  const match = String(receipt || '')
    .trim()
    .toUpperCase()
    .match(/^([A-Z]{2}\d{2})-/);
  return match ? match[1] : null;
}

function normalizeImageLinks(value) {
  return String(value || '')
    .split(';')
    .map((link) => link.trim())
    .filter(Boolean)
    .map((link) => normalizeImageLink(link))
    .filter(Boolean);
}

function normalizeImageLink(link) {
  let pathname = link;
  try {
    if (/^https?:\/\//i.test(link)) {
      pathname = new URL(link).pathname;
    }
  } catch (_) {
    return null;
  }

  let relative = null;
  if (pathname.startsWith('/app_images/')) {
    relative = pathname.slice('/app_images/'.length);
  } else if (pathname.startsWith('/uploads/')) {
    relative = pathname.slice('/uploads/'.length);
  } else {
    relative = pathname.replace(/^\/+/, '');
  }

  const parts = relative.split('/').filter(Boolean);
  if (parts.length < 2) return null;
  if (parts.some((part) => part === '.' || part === '..')) return null;
  if (!parts.every((part) => /^[A-Za-z0-9._-]{1,160}$/.test(part))) return null;
  return `${IMAGE_BASE_URL}/${parts.join('/')}`;
}

function legacyFirstName(email) {
  return email.split('@')[0].slice(0, 80) || 'legacy';
}

function safeDate(value) {
  const date = value ? new Date(value) : new Date();
  return Number.isNaN(date.getTime()) ? new Date() : date;
}

function dateMs(value) {
  return safeDate(value).getTime();
}

function stripTrailingSlash(value) {
  return String(value || '').replace(/\/+$/, '');
}

function printSummary(label, summary) {
  console.log(JSON.stringify({ label, apply: APPLY, ...summary }, null, 2));
}
