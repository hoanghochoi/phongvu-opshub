import 'dotenv/config';
import pg from 'pg';
import { pathToFileURL } from 'url';
import { createPrismaClient } from './prisma-local.mjs';

const DEFAULT_N8N_TABLE = 'data_table_user_hY8m0IrB9V1iDQQw';
const DEFAULT_IMAGE_BASE_URL = 'https://opshub.hoanghochoi.com/uploads';
const TECHNICAL_DEPARTMENT = {
  code: 'TECHNICAL',
  displayName: 'Technical',
  description: 'Technical and repair staff',
};
const TECHNICIAN_JOB_ROLE = {
  code: 'TECHNICIAN',
  displayName: 'Technician',
  description: 'Warranty and repair technician',
  departmentCode: TECHNICAL_DEPARTMENT.code,
};

export async function main({
  argv = process.argv.slice(2),
  env = process.env,
} = {}) {
  const options = parseOptions(argv, env);

  if (!env.N8N_DATABASE_URL) {
    console.error('N8N_DATABASE_URL is required');
    process.exitCode = 1;
    return;
  }

  const n8nPool = new pg.Pool({ connectionString: env.N8N_DATABASE_URL });
  const { prisma, close } = createPrismaClient();

  try {
    const n8nRows = await loadN8nWarrantyRows(n8nPool, options.n8nTable);
    const uniqueRows = latestRowByReceipt(n8nRows);
    const appWarranties = new Map(
      (
        await prisma.warranty.findMany({
          select: {
            id: true,
            receipt: true,
            imageLinks: true,
            createdById: true,
            createdBy: {
              select: {
                id: true,
                email: true,
                password: true,
                status: true,
                storeId: true,
              },
            },
          },
        })
      ).map((row) => [row.receipt, row]),
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
            departmentCode: true,
            jobRoleCode: true,
            workScopeType: true,
          },
        })
      ).map((user) => [user.email.trim().toLowerCase(), user]),
    );
    const appStores = new Map(
      (
        await prisma.store.findMany({ select: { id: true, storeId: true } })
      ).map((store) => [store.storeId.trim().toUpperCase(), store]),
    );

    const plan = buildPlan({
      rows: uniqueRows,
      appWarranties,
      appUsers,
      appStores,
      imageBaseUrl: options.imageBaseUrl,
      storeFilter: options.storeFilter,
      reassignExistingCreators: options.reassignExistingCreators,
    });
    printSummary('dryRun', options, plan.summary);

    if (!options.apply) {
      console.log('Dry run only. Re-run with --apply to write changes.');
      return;
    }

    const applied = await applyPlan(plan.items, { ...options, prisma });
    printSummary('applied', options, applied);
  } finally {
    await n8nPool.end();
    await close();
  }
}

async function loadN8nWarrantyRows(pool, tableName) {
  const sql = `
    select receipt, "user" as legacy_user, links, "createdAt" as created_at, "updatedAt" as updated_at
    from "${tableName.replace(/"/g, '""')}"
    where receipt is not null and btrim(receipt) <> ''
  `;
  const result = await pool.query(sql);
  return result.rows;
}

export function latestRowByReceipt(rows) {
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

export function buildPlan({
  rows,
  appWarranties,
  appUsers,
  appStores,
  imageBaseUrl = DEFAULT_IMAGE_BASE_URL,
  storeFilter = null,
  reassignExistingCreators = false,
}) {
  const items = [];
  const summary = {
    n8nRows: rows.length,
    rowsAfterStoreFilter: 0,
    rowsSkippedByStoreFilter: 0,
    existingWarrantyRows: 0,
    warrantyRowsToCreate: 0,
    existingWarrantyImageRowsToUpdate: 0,
    existingWarrantyCreatorsToUpdate: 0,
    legacyUsersToCreate: 0,
    legacyUsersAlreadyExist: 0,
    legacyLockedUsersToPatchStore: 0,
    storesToCreate: 0,
    rowsWithoutStorePrefix: 0,
    rowsWithInvalidUser: 0,
    rowsWithInvalidLinks: 0,
    linksToCreate: 0,
    linksToAddToExisting: 0,
  };
  const usersToCreate = new Set();
  const existingUsers = new Set();
  const storesToCreate = new Set();
  const legacyUsersToPatchStore = new Set();

  for (const row of rows) {
    const storeCode = inferStoreCode(row.receipt);
    if (storeFilter && storeCode !== storeFilter) {
      summary.rowsSkippedByStoreFilter += 1;
      continue;
    }
    summary.rowsAfterStoreFilter += 1;

    if (!storeCode) summary.rowsWithoutStorePrefix += 1;
    if (storeCode && !appStores.has(storeCode)) storesToCreate.add(storeCode);

    const email = normalizeEmail(row.legacy_user);
    if (!email) {
      summary.rowsWithInvalidUser += 1;
      continue;
    }

    const imageLinks = normalizeImageLinks(row.links, imageBaseUrl);
    if (imageLinks.length === 0) {
      summary.rowsWithInvalidLinks += 1;
      continue;
    }

    const existingUser = appUsers.get(email);
    if (existingUser) {
      existingUsers.add(email);
      if (shouldPatchLegacyUserStore(existingUser, storeCode)) {
        legacyUsersToPatchStore.add(email);
      }
    } else {
      usersToCreate.add(email);
    }

    const existingWarranty = appWarranties.get(row.receipt);
    const nextImageLinks = mergeImageLinks(
      existingWarranty?.imageLinks,
      imageLinks,
      imageBaseUrl,
    );
    const normalizedExistingLinks = normalizeImageLinks(
      existingWarranty?.imageLinks,
      imageBaseUrl,
    );
    const storedExistingLinks = splitImageLinks(existingWarranty?.imageLinks);
    const imageLinksWillUpdate =
      Boolean(existingWarranty) &&
      linksString(nextImageLinks) !== linksString(storedExistingLinks);
    const creatorWillUpdate = Boolean(
      existingWarranty &&
      shouldUpdateExistingCreator(
        existingWarranty.createdBy,
        existingUser,
        email,
        { reassignExistingCreators },
      ),
    );

    if (existingWarranty) {
      summary.existingWarrantyRows += 1;
      if (imageLinksWillUpdate) {
        summary.existingWarrantyImageRowsToUpdate += 1;
        summary.linksToAddToExisting +=
          nextImageLinks.length - normalizedExistingLinks.length;
      }
      if (creatorWillUpdate) summary.existingWarrantyCreatorsToUpdate += 1;
    } else {
      summary.warrantyRowsToCreate += 1;
      summary.linksToCreate += imageLinks.length;
    }

    items.push({
      receipt: row.receipt,
      email,
      storeCode,
      imageLinks,
      createdAt: safeDate(row.created_at),
    });
  }

  summary.legacyUsersToCreate = usersToCreate.size;
  summary.legacyUsersAlreadyExist = existingUsers.size;
  summary.storesToCreate = storesToCreate.size;
  summary.legacyLockedUsersToPatchStore = legacyUsersToPatchStore.size;
  return { items, summary };
}

async function applyPlan(items, options) {
  const summary = {
    storesCreatedOrTouched: 0,
    legacyUsersCreated: 0,
    legacyLockedUsersPatchedStore: 0,
    warrantyRowsCreated: 0,
    existingWarrantyRowsTouched: 0,
    existingWarrantyImageRowsUpdated: 0,
    existingWarrantyCreatorsUpdated: 0,
    warrantyRowsSkippedNoChange: 0,
    linksCreated: 0,
    linksAddedToExisting: 0,
  };

  await options.prisma.$transaction(async (tx) => {
    await ensureLegacyCatalog(tx);

    const storeCache = new Map();
    const userCache = new Map();

    for (const item of items) {
      const existingWarranty = await tx.warranty.findUnique({
        where: { receipt: item.receipt },
        include: {
          createdBy: {
            select: {
              id: true,
              email: true,
              password: true,
              status: true,
              storeId: true,
            },
          },
        },
      });
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

      if (existingWarranty) {
        const existingLinks = normalizeImageLinks(
          existingWarranty.imageLinks,
          options.imageBaseUrl,
        );
        const storedLinks = splitImageLinks(existingWarranty.imageLinks);
        const nextLinks = mergeImageLinks(
          existingWarranty.imageLinks,
          item.imageLinks,
          options.imageBaseUrl,
        );
        const data = {};
        if (linksString(nextLinks) !== linksString(storedLinks)) {
          data.imageLinks = linksString(nextLinks);
          summary.existingWarrantyImageRowsUpdated += 1;
          summary.linksAddedToExisting +=
            nextLinks.length - existingLinks.length;
        }
        if (
          shouldUpdateExistingCreator(
            existingWarranty.createdBy,
            user,
            item.email,
            { reassignExistingCreators: options.reassignExistingCreators },
          )
        ) {
          data.createdById = user.id;
          summary.existingWarrantyCreatorsUpdated += 1;
        }
        if (Object.keys(data).length > 0) {
          await tx.warranty.update({
            where: { id: existingWarranty.id },
            data,
          });
          summary.existingWarrantyRowsTouched += 1;
        } else {
          summary.warrantyRowsSkippedNoChange += 1;
        }
        continue;
      }

      await tx.warranty.create({
        data: {
          receipt: item.receipt,
          imageLinks: linksString(item.imageLinks),
          createdById: user.id,
          createdAt: item.createdAt,
        },
      });
      summary.warrantyRowsCreated += 1;
      summary.linksCreated += item.imageLinks.length;
    }
  });

  return summary;
}

async function ensureLegacyCatalog(tx) {
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
  await tx.departmentDefinition.upsert({
    where: { code: TECHNICAL_DEPARTMENT.code },
    update: {
      displayName: TECHNICAL_DEPARTMENT.displayName,
      description: TECHNICAL_DEPARTMENT.description,
      isSystem: true,
      isActive: true,
    },
    create: { ...TECHNICAL_DEPARTMENT, isSystem: true, isActive: true },
  });
  await tx.jobRoleDefinition.upsert({
    where: { code: TECHNICIAN_JOB_ROLE.code },
    update: {
      displayName: TECHNICIAN_JOB_ROLE.displayName,
      description: TECHNICIAN_JOB_ROLE.description,
      departmentCode: TECHNICIAN_JOB_ROLE.departmentCode,
      isSystem: true,
      isActive: true,
    },
    create: { ...TECHNICIAN_JOB_ROLE, isSystem: true, isActive: true },
  });
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
    if (shouldPatchLegacyUserStore(existing, storeId)) {
      const patched = await tx.user.update({
        where: { id: existing.id },
        data: {
          storeId,
          workScopeType: existing.workScopeType || 'STORE',
          departmentCode: existing.departmentCode || TECHNICAL_DEPARTMENT.code,
          jobRoleCode: existing.jobRoleCode || TECHNICIAN_JOB_ROLE.code,
        },
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
      departmentCode: TECHNICAL_DEPARTMENT.code,
      jobRoleCode: TECHNICIAN_JOB_ROLE.code,
    },
  });
  summary.legacyUsersCreated += 1;
  cache.set(email, created);
  return created;
}

export function parseOptions(argv = [], env = process.env) {
  const args = Array.from(argv);
  let storeFilter = env.N8N_WARRANTY_STORE_FILTER || null;
  let reassignExistingCreators = env.N8N_WARRANTY_REASSIGN_CREATORS === 'true';

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--store' || arg === '--store-filter') {
      storeFilter = args[i + 1] || storeFilter;
      i += 1;
    } else if (arg.startsWith('--store=')) {
      storeFilter = arg.slice('--store='.length);
    } else if (arg.startsWith('--store-filter=')) {
      storeFilter = arg.slice('--store-filter='.length);
    } else if (arg === '--reassign-existing-creators') {
      reassignExistingCreators = true;
    }
  }

  return {
    apply: args.includes('--apply'),
    n8nTable: env.N8N_WARRANTY_TABLE || DEFAULT_N8N_TABLE,
    imageBaseUrl: stripTrailingSlash(
      env.IMAGE_BASE_URL || DEFAULT_IMAGE_BASE_URL,
    ),
    storeFilter: storeFilter ? normalizeStoreCode(storeFilter) : null,
    reassignExistingCreators,
  };
}

function shouldPatchLegacyUserStore(user, storeId) {
  return Boolean(
    storeId && !user.storeId && user.status === 'no' && !user.password,
  );
}

export function shouldUpdateExistingCreator(
  currentCreator,
  targetUser,
  targetEmail,
  { reassignExistingCreators = false } = {},
) {
  if (!currentCreator) return true;
  const currentEmail = normalizeEmail(currentCreator.email);
  if (currentEmail && currentEmail === targetEmail) return false;
  if (reassignExistingCreators) return true;
  if (isLockedLegacyUser(currentCreator)) return true;
  if (!currentCreator.storeId && targetUser?.storeId) return true;
  return false;
}

function isLockedLegacyUser(user) {
  return user?.status === 'no' && !user?.password;
}

export function mergeImageLinks(existingValue, incomingLinks, imageBaseUrl) {
  const links = [
    ...normalizeImageLinks(existingValue, imageBaseUrl),
    ...incomingLinks,
  ];
  const seen = new Set();
  const merged = [];
  for (const link of links) {
    const key = link.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    merged.push(link);
  }
  return merged;
}

function normalizeReceipt(value) {
  const receipt = String(value || '')
    .trim()
    .toUpperCase();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(receipt)) return '';
  return receipt;
}

function normalizeEmail(value) {
  const email = String(value || '')
    .trim()
    .toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return '';
  return email;
}

function normalizeStoreCode(value) {
  const code = String(value || '')
    .trim()
    .toUpperCase();
  if (!/^[A-Z0-9][A-Z0-9_-]{1,39}$/.test(code)) {
    throw new Error(`Invalid store filter: ${value}`);
  }
  return code;
}

function inferStoreCode(receipt) {
  const match = String(receipt || '')
    .trim()
    .toUpperCase()
    .match(/^([A-Z]{2}\d{2})-/);
  return match ? match[1] : null;
}

function splitImageLinks(value) {
  return String(value || '')
    .split(';')
    .map((link) => link.trim())
    .filter(Boolean);
}

export function normalizeImageLinks(
  value,
  imageBaseUrl = DEFAULT_IMAGE_BASE_URL,
) {
  return splitImageLinks(value)
    .map((link) => normalizeImageLink(link, imageBaseUrl))
    .filter(Boolean);
}

function normalizeImageLink(link, imageBaseUrl) {
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
  return `${stripTrailingSlash(imageBaseUrl)}/${parts.join('/')}`;
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

function linksString(links) {
  return links.join(';');
}

function stripTrailingSlash(value) {
  return String(value || '').replace(/\/+$/, '');
}

function printSummary(label, options, summary) {
  console.log(
    JSON.stringify(
      {
        label,
        apply: options.apply,
        storeFilter: options.storeFilter,
        reassignExistingCreators: options.reassignExistingCreators,
        imageBaseUrl: options.imageBaseUrl,
        ...summary,
      },
      null,
      2,
    ),
  );
}

function isCliEntryPoint() {
  return (
    process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
  );
}

if (isCliEntryPoint()) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
