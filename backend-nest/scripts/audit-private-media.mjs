import 'dotenv/config';
import fs from 'fs/promises';
import path from 'path';
import {
  parsePrivateMediaAuditArgs,
  summarizePrivateMediaReferences,
} from './private-media-reference-audit.mjs';
import { createPrismaClient } from './prisma-local.mjs';

const { strict, failOnLegacy } = parsePrivateMediaAuditArgs(
  process.argv.slice(2),
);
const baseDir = path.resolve(
  process.env.PRIVATE_MEDIA_BASE_DIR || '/data/private-media',
);
const legacyBaseUrl = requiredEnv('IMAGE_BASE_URL');
const privatePublicBaseUrl = requiredEnv('PRIVATE_MEDIA_PUBLIC_BASE_URL');
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

  const orphanDiskFiles = [...diskKeys].filter(
    (key) => !activeKeys.has(key),
  ).length;
  const ownerCounts = await countMissingOwners(activeRows);
  const [avatarRows, warrantyRows, feedbackRows] = await Promise.all([
    prisma.user.findMany({
      where: { avatarUrl: { not: null, notIn: [''] } },
      select: { avatarUrl: true },
    }),
    prisma.warranty.findMany({
      where: { imageLinks: { not: null, notIn: [''] } },
      select: { imageLinks: true },
    }),
    prisma.feedback.findMany({
      where: { content: { contains: 'Hình ảnh:' } },
      select: { content: true },
    }),
  ]);
  const referenceSummary = summarizePrivateMediaReferences({
    avatars: avatarRows.map((row) => row.avatarUrl),
    warranties: warrantyRows.map((row) => row.imageLinks),
    feedbackItems: feedbackRows.map((row) => row.content),
    legacyBaseUrl,
    privatePublicBaseUrl,
  });
  const legacyReferencesTotal = referenceSummary.references.legacy.total;

  const report = {
    ok:
      missingFiles === 0 &&
      sizeMismatches === 0 &&
      orphanDiskFiles === 0 &&
      ownerCounts.total === 0,
    legacyReferencesClear: legacyReferencesTotal === 0,
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
      avatarRecords: referenceSummary.records.avatar.scanned,
      protectedAvatarRecords: referenceSummary.records.avatar.withProtected,
      legacyAvatarRecords: referenceSummary.records.avatar.withLegacy,
      warrantyRecords: referenceSummary.records.warranty.scanned,
      protectedWarrantyRecords: referenceSummary.records.warranty.withProtected,
      legacyWarrantyRecords: referenceSummary.records.warranty.withLegacy,
      feedbackRecordsWithImages: referenceSummary.records.feedback.scanned,
      protectedFeedbackRecords: referenceSummary.records.feedback.withProtected,
      legacyFeedbackRecords: referenceSummary.records.feedback.withLegacy,
      legacyReferencesTotal,
      references: referenceSummary.references,
    },
  };
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (strict && !report.ok) {
    process.exitCode = 2;
  } else if (failOnLegacy && !report.legacyReferencesClear) {
    process.exitCode = 3;
  }
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
  result.total =
    result.warranty + result.feedback + result.avatar + result.unknown;
  return result;
}

async function listFiles(directory) {
  const results = [];
  const entries = await fs
    .readdir(directory, { withFileTypes: true })
    .catch((error) => {
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

function requiredEnv(key) {
  const value = process.env[key]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${key}`);
  return value;
}
