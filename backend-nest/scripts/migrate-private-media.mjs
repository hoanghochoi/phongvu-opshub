import 'dotenv/config';
import { createHash, randomUUID } from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import sharp from 'sharp';
import {
  PRIVATE_MEDIA_BATCH_STRATEGY,
  parsePrivateMediaBatchArgs,
  privateMediaBatchQuery,
  resolvePrivateMediaBatchPage,
} from './private-media-batch-window.mjs';
import { createPrismaClient } from './prisma-local.mjs';

const APPLY_CONFIRMATION = 'MIGRATE_PRIVATE_MEDIA_V1';
const apply = process.argv.includes('--apply');
const strict = process.argv.includes('--strict');
const batch = parsePrivateMediaBatchArgs(process.argv.slice(2), {
  apply,
  strategy: PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset,
});
const ticket = stringArg('ticket');
const approvedBy = stringArg('approved-by');

if (apply) {
  if (stringArg('confirm') !== APPLY_CONFIRMATION) {
    throw new Error(`--confirm must equal ${APPLY_CONFIRMATION}`);
  }
  if (!ticket || !approvedBy) {
    throw new Error('--ticket and --approved-by are required with --apply');
  }
  if (ticket.length > 120 || approvedBy.length > 120) {
    throw new Error('--ticket and --approved-by must not exceed 120 characters');
  }
}

const uploadBaseDir = path.resolve(requiredEnv('UPLOAD_BASE_DIR'));
const privateBaseDir = path.resolve(requiredEnv('PRIVATE_MEDIA_BASE_DIR'));
const legacyBaseUrl = normalizedUrl(requiredEnv('IMAGE_BASE_URL'));
const privatePublicBaseUrl = normalizedUrl(
  requiredEnv('PRIVATE_MEDIA_PUBLIC_BASE_URL'),
);
const maxBytes = positiveEnv('PRIVATE_MEDIA_MIGRATION_MAX_BYTES', 50 * 1024 * 1024);
const maxPixels = positiveEnv('PRIVATE_MEDIA_MIGRATION_MAX_PIXELS', 100_000_000);

if (isInside(uploadBaseDir, privateBaseDir) || isInside(privateBaseDir, uploadBaseDir)) {
  throw new Error('Public and private media directories must be separate');
}

const report = {
  mode: apply ? 'apply' : 'dry-run',
  generatedAt: new Date().toISOString(),
  batch: {
    strategy: batch.strategy,
    limit: batch.limit,
    offset: batch.offset,
    maxApplyBatchSize: batch.maxApplyBatchSize,
    hasMore: false,
    nextOffset: null,
    categories: {},
  },
  recordsScanned: { avatar: 0, warranty: 0, feedback: 0 },
  recordsChanged: { avatar: 0, warranty: 0, feedback: 0 },
  references: {
    scanned: 0,
    candidates: 0,
    migrated: 0,
    alreadyPrivate: 0,
    reused: 0,
    externalOrUnsupported: 0,
    missing: 0,
    rejected: 0,
  },
  errors: 0,
};

const { prisma, close } = createPrismaClient();
try {
  await fs.mkdir(privateBaseDir, { recursive: true, mode: 0o750 });
  await migrateAvatars();
  await migrateWarranties();
  await migrateFeedback();
  finalizeBatchReport();
  if (apply) {
    await prisma.appLog.create({
      data: {
        level: report.errors > 0 ? 'warn' : 'info',
        source: 'SecurityPrivateMediaMigration',
        message: 'Private media reference migration completed',
        context: {
          ticket,
          approvedBy,
          report,
        },
      },
    });
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if ((strict || apply) && report.errors > 0) process.exitCode = 2;
} finally {
  await close();
}

async function migrateAvatars() {
  const page = resolvePrivateMediaBatchPage(await prisma.user.findMany({
    where: { avatarUrl: { not: null, notIn: [''] } },
    select: { id: true, avatarUrl: true },
    orderBy: { id: 'asc' },
    ...privateMediaBatchQuery(batch),
  }), batch);
  recordBatchCategory('avatar', page);
  for (const user of page.rows) {
    report.recordsScanned.avatar += 1;
    const next = await migrateReference(user.avatarUrl, {
      ownerFeature: 'AVATAR',
      ownerRecordId: user.id,
      uploaderId: user.id,
    });
    if (next === user.avatarUrl) continue;
    report.recordsChanged.avatar += 1;
    if (apply) {
      await prisma.user.update({ where: { id: user.id }, data: { avatarUrl: next } });
    }
  }
}

async function migrateWarranties() {
  const page = resolvePrivateMediaBatchPage(await prisma.warranty.findMany({
    where: { imageLinks: { not: null, notIn: [''] } },
    select: { id: true, imageLinks: true, createdById: true },
    orderBy: { id: 'asc' },
    ...privateMediaBatchQuery(batch),
  }), batch);
  recordBatchCategory('warranty', page);
  for (const warranty of page.rows) {
    report.recordsScanned.warranty += 1;
    const current = splitLinks(warranty.imageLinks);
    const next = [];
    for (const value of current) {
      next.push(
        await migrateReference(value, {
          ownerFeature: 'WARRANTY',
          ownerRecordId: warranty.id,
          uploaderId: warranty.createdById,
        }),
      );
    }
    const nextValue = next.join(';');
    if (nextValue === warranty.imageLinks) continue;
    report.recordsChanged.warranty += 1;
    if (apply) {
      await prisma.warranty.update({
        where: { id: warranty.id },
        data: { imageLinks: nextValue },
      });
    }
  }
}

async function migrateFeedback() {
  const page = resolvePrivateMediaBatchPage(await prisma.feedback.findMany({
    where: { content: { contains: 'Hình ảnh:' } },
    select: { id: true, userId: true, content: true },
    orderBy: { id: 'asc' },
    ...privateMediaBatchQuery(batch),
  }), batch);
  recordBatchCategory('feedback', page);
  for (const item of page.rows) {
    report.recordsScanned.feedback += 1;
    const marker = 'Hình ảnh:';
    const markerIndex = item.content.lastIndexOf(marker);
    if (markerIndex < 0) continue;
    const lineStart = markerIndex + marker.length;
    const lineEndCandidate = item.content.indexOf('\n', lineStart);
    const lineEnd = lineEndCandidate < 0 ? item.content.length : lineEndCandidate;
    const currentLine = item.content.slice(lineStart, lineEnd).trim();
    const current = splitLinks(currentLine);
    const next = [];
    for (const value of current) {
      next.push(
        await migrateReference(value, {
          ownerFeature: 'FEEDBACK',
          ownerRecordId: item.id,
          uploaderId: item.userId,
        }),
      );
    }
    const nextContent =
      item.content.slice(0, lineStart) +
      ` ${next.join(';')}` +
      item.content.slice(lineEnd);
    if (nextContent === item.content) continue;
    report.recordsChanged.feedback += 1;
    if (apply) {
      await prisma.feedback.update({
        where: { id: item.id },
        data: { content: nextContent },
      });
    }
  }
}

function recordBatchCategory(category, page) {
  report.batch.categories[category] = {
    recordsInBatch: page.rows.length,
    hasMore: page.hasMore,
    nextOffset: page.nextOffset,
  };
}

function finalizeBatchReport() {
  const categories = Object.values(report.batch.categories);
  report.batch.hasMore = categories.some((category) => category.hasMore);
  report.batch.nextOffset = report.batch.hasMore
    ? batch.offset + batch.limit
    : null;
}

async function migrateReference(value, owner) {
  report.references.scanned += 1;
  if (isPrivateUrl(value)) {
    report.references.alreadyPrivate += 1;
    return value;
  }
  const sourcePath = await legacyFilePath(value);
  if (!sourcePath) {
    report.references.externalOrUnsupported += 1;
    return value;
  }
  report.references.candidates += 1;
  if (!apply) return value;

  const existing = await prisma.mediaObject.findFirst({
    where: {
      legacyUrl: value,
      ownerFeature: owner.ownerFeature,
      ownerRecordId: owner.ownerRecordId,
      deletedAt: null,
    },
  });
  if (existing) {
    const target = privatePath(existing.storageKey);
    const stat = await fs.stat(target).catch(() => null);
    if (stat?.isFile() && stat.size === existing.sizeBytes) {
      report.references.reused += 1;
      return privateUrl(existing.id);
    }
    report.references.missing += 1;
    report.errors += 1;
    return value;
  }

  try {
    const normalized = await normalizeLegacyImage(sourcePath);
    const id = randomUUID();
    const storageKey = path.posix.join(
      owner.ownerFeature.toLowerCase(),
      id.slice(0, 2),
      `${id}.${normalized.extension}`,
    );
    const target = privatePath(storageKey);
    await fs.mkdir(path.dirname(target), { recursive: true, mode: 0o750 });
    await atomicWrite(target, normalized.buffer);
    try {
      await prisma.mediaObject.create({
        data: {
          id,
          storageKey,
          ...owner,
          originalName: path.basename(sourcePath).slice(0, 255),
          contentTypeVerified: normalized.contentType,
          sizeBytes: normalized.buffer.length,
          checksumSha256: createHash('sha256')
            .update(normalized.buffer)
            .digest('hex'),
          visibility: 'PRIVATE',
          legacyUrl: value,
        },
      });
    } catch (error) {
      await fs.unlink(target).catch(() => undefined);
      throw error;
    }
    report.references.migrated += 1;
    return privateUrl(id);
  } catch {
    report.references.rejected += 1;
    report.errors += 1;
    return value;
  }
}

async function legacyFilePath(value) {
  let target;
  try {
    target = new URL(String(value));
  } catch {
    return null;
  }
  if (
    target.origin !== legacyBaseUrl.origin ||
    target.username ||
    target.password ||
    target.search ||
    target.hash
  ) {
    return null;
  }
  const basePath = legacyBaseUrl.pathname.replace(/\/+$/, '');
  if (!target.pathname.startsWith(`${basePath}/`)) return null;
  const relative = target.pathname.slice(basePath.length + 1);
  let segments;
  try {
    segments = relative.split('/').map((segment) => decodeURIComponent(segment));
  } catch {
    return null;
  }
  if (
    segments.length === 0 ||
    segments.some(
      (segment) => !segment || segment === '.' || segment === '..' || segment.includes('\0'),
    )
  ) {
    return null;
  }
  const candidate = path.resolve(uploadBaseDir, ...segments);
  if (!isInside(uploadBaseDir, candidate)) return null;
  const [baseReal, candidateReal] = await Promise.all([
    fs.realpath(uploadBaseDir).catch(() => null),
    fs.realpath(candidate).catch(() => null),
  ]);
  if (!baseReal || !candidateReal || !isInside(baseReal, candidateReal)) {
    report.references.missing += 1;
    report.errors += 1;
    return null;
  }
  const stat = await fs.stat(candidateReal).catch(() => null);
  if (!stat?.isFile() || stat.size < 1 || stat.size > maxBytes) {
    report.references.missing += 1;
    report.errors += 1;
    return null;
  }
  return candidateReal;
}

async function normalizeLegacyImage(sourcePath) {
  const pipeline = sharp(sourcePath, {
    failOn: 'warning',
    limitInputPixels: maxPixels,
    sequentialRead: true,
  });
  const metadata = await pipeline.metadata();
  if (
    !metadata.format ||
    !['jpeg', 'png', 'webp', 'heif'].includes(metadata.format) ||
    !metadata.width ||
    !metadata.height ||
    metadata.width * metadata.height > maxPixels ||
    (metadata.pages ?? 1) !== 1
  ) {
    throw new Error('unsupported image');
  }
  let output = pipeline.rotate();
  let contentType;
  let extension;
  if (metadata.format === 'png') {
    output = output.png({ compressionLevel: 9, adaptiveFiltering: true });
    contentType = 'image/png';
    extension = 'png';
  } else if (metadata.format === 'webp') {
    output = output.webp({ quality: 88 });
    contentType = 'image/webp';
    extension = 'webp';
  } else {
    output = output.jpeg({ quality: 88, mozjpeg: true });
    contentType = 'image/jpeg';
    extension = 'jpg';
  }
  const buffer = await output.toBuffer();
  if (buffer.length < 1 || buffer.length > maxBytes) {
    throw new Error('normalized image size is invalid');
  }
  return { buffer, contentType, extension };
}

async function atomicWrite(target, buffer) {
  const temporary = `${target}.tmp-${randomUUID()}`;
  try {
    await fs.writeFile(temporary, buffer, { flag: 'wx', mode: 0o600 });
    await fs.rename(temporary, target);
    await fs.chmod(target, 0o600).catch(() => undefined);
  } catch (error) {
    await fs.unlink(temporary).catch(() => undefined);
    throw error;
  }
}

function privatePath(storageKey) {
  const target = path.resolve(privateBaseDir, ...String(storageKey).split('/'));
  if (!isInside(privateBaseDir, target)) throw new Error('unsafe storage key');
  return target;
}

function privateUrl(id) {
  return `${privatePublicBaseUrl.href.replace(/\/+$/, '')}/media/${id}`;
}

function isPrivateUrl(value) {
  try {
    const target = new URL(String(value));
    const base = privatePublicBaseUrl.href.replace(/\/+$/, '');
    return target.href.startsWith(`${base}/media/`) && !target.search && !target.hash;
  } catch {
    return false;
  }
}

function splitLinks(value) {
  return String(value || '')
    .split(';')
    .map((item) => item.trim())
    .filter(Boolean);
}

function isInside(base, target) {
  const resolvedBase = path.resolve(base);
  const resolvedTarget = path.resolve(target);
  return (
    resolvedTarget === resolvedBase ||
    resolvedTarget.startsWith(resolvedBase + path.sep)
  );
}

function normalizedUrl(value) {
  const parsed = new URL(value);
  if (!['http:', 'https:'].includes(parsed.protocol) || parsed.username || parsed.password) {
    throw new Error('Media base URL is invalid');
  }
  parsed.search = '';
  parsed.hash = '';
  return parsed;
}

function requiredEnv(key) {
  const value = process.env[key]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${key}`);
  return value;
}

function positiveEnv(key, fallback) {
  const value = Number(process.env[key] || fallback);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${key} must be a positive integer`);
  }
  return value;
}

function stringArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1]?.trim() || null : null;
}
