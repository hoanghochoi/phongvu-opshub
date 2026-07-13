import 'dotenv/config';
import fs from 'fs/promises';
import path from 'path';
import { createPrismaClient } from './prisma-local.mjs';

const strict = process.argv.includes('--strict');
const baseDir = path.resolve(
  process.env.PRIVATE_MEDIA_BASE_DIR || '/data/private-media',
);
const { prisma, close } = createPrismaClient();

try {
  const rows = await prisma.mediaObject.findMany({
    select: {
      id: true,
      storageKey: true,
      ownerFeature: true,
      ownerRecordId: true,
      sizeBytes: true,
      deletedAt: true,
    },
  });
  const diskFiles = await listFiles(baseDir);
  const diskKeys = new Set(diskFiles.map((value) => toStorageKey(value)));
  const activeRows = rows.filter((row) => !row.deletedAt);
  const activeKeys = new Set(activeRows.map((row) => row.storageKey));

  let missingFiles = 0;
  let sizeMismatches = 0;
  for (const row of activeRows) {
    const target = safeStoragePath(row.storageKey);
    const stat = await fs.stat(target).catch(() => null);
    if (!stat?.isFile()) {
      missingFiles += 1;
    } else if (stat.size !== row.sizeBytes) {
      sizeMismatches += 1;
    }
  }

  const orphanDiskFiles = [...diskKeys].filter((key) => !activeKeys.has(key)).length;
  const ownerCounts = await countMissingOwners(activeRows);
  const [legacyAvatars, legacyWarranties, feedbackWithImages] = await Promise.all([
    prisma.user.count({
      where: { avatarUrl: { not: null, notIn: [''] } },
    }),
    prisma.warranty.count({
      where: { imageLinks: { not: null, notIn: [''] } },
    }),
    prisma.feedback.count({
      where: { content: { contains: 'Hình ảnh:' } },
    }),
  ]);
  const [protectedAvatars, protectedWarranties, protectedFeedback] =
    await Promise.all([
      prisma.user.count({ where: { avatarUrl: { contains: '/media/' } } }),
      prisma.warranty.count({ where: { imageLinks: { contains: '/media/' } } }),
      prisma.feedback.count({ where: { content: { contains: '/media/' } } }),
    ]);

  const report = {
    ok:
      missingFiles === 0 &&
      sizeMismatches === 0 &&
      orphanDiskFiles === 0 &&
      ownerCounts.total === 0,
    generatedAt: new Date().toISOString(),
    metadata: {
      total: rows.length,
      active: activeRows.length,
      deleted: rows.length - activeRows.length,
    },
    integrity: {
      missingFiles,
      sizeMismatches,
      orphanDiskFiles,
      missingOwners: ownerCounts,
    },
    referenceInventory: {
      avatarRecords: legacyAvatars,
      protectedAvatarRecords: protectedAvatars,
      warrantyRecords: legacyWarranties,
      protectedWarrantyRecords: protectedWarranties,
      feedbackRecordsWithImages: feedbackWithImages,
      protectedFeedbackRecords: protectedFeedback,
    },
  };
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (strict && !report.ok) process.exitCode = 2;
} finally {
  await close();
}

async function countMissingOwners(rows) {
  const result = { warranty: 0, feedback: 0, avatar: 0, unknown: 0, total: 0 };
  for (const row of rows) {
    let exists = false;
    if (row.ownerFeature === 'WARRANTY') {
      exists = Boolean(
        await prisma.warranty.findUnique({
          where: { id: row.ownerRecordId },
          select: { id: true },
        }),
      );
      if (!exists) result.warranty += 1;
    } else if (row.ownerFeature === 'FEEDBACK') {
      exists = Boolean(
        await prisma.feedback.findUnique({
          where: { id: row.ownerRecordId },
          select: { id: true },
        }),
      );
      if (!exists) result.feedback += 1;
    } else if (row.ownerFeature === 'AVATAR') {
      exists = Boolean(
        await prisma.user.findUnique({
          where: { id: row.ownerRecordId },
          select: { id: true },
        }),
      );
      if (!exists) result.avatar += 1;
    } else {
      result.unknown += 1;
    }
  }
  result.total = result.warranty + result.feedback + result.avatar + result.unknown;
  return result;
}

async function listFiles(directory) {
  const results = [];
  const entries = await fs.readdir(directory, { withFileTypes: true }).catch((error) => {
    if (error?.code === 'ENOENT') return [];
    throw error;
  });
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      throw new Error('Private media storage must not contain symbolic links');
    }
    if (entry.isDirectory()) results.push(...(await listFiles(target)));
    if (entry.isFile()) results.push(target);
  }
  return results;
}

function safeStoragePath(storageKey) {
  const target = path.resolve(baseDir, ...String(storageKey).split('/'));
  if (target !== baseDir && !target.startsWith(baseDir + path.sep)) {
    throw new Error('Private media metadata contains an unsafe storage key');
  }
  return target;
}

function toStorageKey(filePath) {
  return path.relative(baseDir, filePath).split(path.sep).join('/');
}
