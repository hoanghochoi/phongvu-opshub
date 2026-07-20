import 'dotenv/config';
import {
  PRIVATE_MEDIA_BATCH_STRATEGY,
  parsePrivateMediaBatchArgs,
  privateMediaBatchQuery,
  resolvePrivateMediaBatchPage,
} from './private-media-batch-window.mjs';
import { createPrismaClient } from './prisma-local.mjs';

const CONFIRMATION = 'ROLLBACK_PRIVATE_MEDIA_REFERENCES_V1';
const apply = process.argv.includes('--apply');
const batch = parsePrivateMediaBatchArgs(process.argv.slice(2), {
  apply,
  strategy: PRIVATE_MEDIA_BATCH_STRATEGY.shrinkingHead,
});
const ticket = arg('ticket');
const approvedBy = arg('approved-by');
if (apply) {
  if (arg('confirm') !== CONFIRMATION) {
    throw new Error(`--confirm must equal ${CONFIRMATION}`);
  }
  if (!ticket || !approvedBy) {
    throw new Error('--ticket and --approved-by are required with --apply');
  }
}

const publicBase = new URL(requiredEnv('PRIVATE_MEDIA_PUBLIC_BASE_URL'));
const basePath = publicBase.pathname.replace(/\/+$/, '');
const report = {
  mode: apply ? 'apply' : 'dry-run',
  generatedAt: new Date().toISOString(),
  batch: {
    strategy: batch.strategy,
    limit: batch.limit,
    offset: 0,
    maxApplyBatchSize: batch.maxApplyBatchSize,
    hasMore: false,
    nextOffset: null,
    categories: {},
  },
  referencesScanned: 0,
  referencesRestored: 0,
  recordsChanged: { avatar: 0, warranty: 0, feedback: 0 },
  unresolved: 0,
};
const { prisma, close } = createPrismaClient();

try {
  await rollbackAvatars();
  await rollbackWarranties();
  await rollbackFeedback();
  finalizeBatchReport();
  if (apply) {
    await prisma.appLog.create({
      data: {
        level: report.unresolved > 0 ? 'warn' : 'info',
        source: 'SecurityPrivateMediaMigration',
        message: 'Private media references rolled back to legacy URLs',
        context: { ticket, approvedBy, report },
      },
    });
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (apply && report.unresolved > 0) process.exitCode = 2;
} finally {
  await close();
}

async function rollbackAvatars() {
  const page = resolvePrivateMediaBatchPage(await prisma.user.findMany({
    where: { avatarUrl: { contains: '/media/' } },
    select: { id: true, avatarUrl: true },
    orderBy: { id: 'asc' },
    ...privateMediaBatchQuery(batch),
  }), batch);
  recordBatchCategory('avatar', page);
  for (const row of page.rows) {
    const next = await legacyReference(row.avatarUrl, 'AVATAR', row.id);
    if (next === row.avatarUrl) continue;
    report.recordsChanged.avatar += 1;
    if (apply) {
      await prisma.user.update({ where: { id: row.id }, data: { avatarUrl: next } });
    }
  }
}

async function rollbackWarranties() {
  const page = resolvePrivateMediaBatchPage(await prisma.warranty.findMany({
    where: { imageLinks: { contains: '/media/' } },
    select: { id: true, imageLinks: true },
    orderBy: { id: 'asc' },
    ...privateMediaBatchQuery(batch),
  }), batch);
  recordBatchCategory('warranty', page);
  for (const row of page.rows) {
    const current = splitLinks(row.imageLinks);
    const next = [];
    for (const value of current) {
      next.push(await legacyReference(value, 'WARRANTY', row.id));
    }
    const nextValue = next.join(';');
    if (nextValue === row.imageLinks) continue;
    report.recordsChanged.warranty += 1;
    if (apply) {
      await prisma.warranty.update({
        where: { id: row.id },
        data: { imageLinks: nextValue },
      });
    }
  }
}

async function rollbackFeedback() {
  const page = resolvePrivateMediaBatchPage(await prisma.feedback.findMany({
    where: { content: { contains: '/media/' } },
    select: { id: true, content: true },
    orderBy: { id: 'asc' },
    ...privateMediaBatchQuery(batch),
  }), batch);
  recordBatchCategory('feedback', page);
  for (const row of page.rows) {
    const marker = 'Hình ảnh:';
    const markerIndex = row.content.lastIndexOf(marker);
    if (markerIndex < 0) continue;
    const lineStart = markerIndex + marker.length;
    const lineEndCandidate = row.content.indexOf('\n', lineStart);
    const lineEnd = lineEndCandidate < 0 ? row.content.length : lineEndCandidate;
    const current = splitLinks(row.content.slice(lineStart, lineEnd));
    const next = [];
    for (const value of current) {
      next.push(await legacyReference(value, 'FEEDBACK', row.id));
    }
    const nextContent =
      row.content.slice(0, lineStart) +
      ` ${next.join(';')}` +
      row.content.slice(lineEnd);
    if (nextContent === row.content) continue;
    report.recordsChanged.feedback += 1;
    if (apply) {
      await prisma.feedback.update({
        where: { id: row.id },
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
  report.batch.nextOffset = report.batch.hasMore ? 0 : null;
}

async function legacyReference(value, ownerFeature, ownerRecordId) {
  const mediaId = mediaIdFromUrl(value);
  if (!mediaId) return value;
  report.referencesScanned += 1;
  const media = await prisma.mediaObject.findFirst({
    where: { id: mediaId, ownerFeature, ownerRecordId, legacyUrl: { not: null } },
    select: { legacyUrl: true },
  });
  if (!media?.legacyUrl) {
    report.unresolved += 1;
    return value;
  }
  report.referencesRestored += 1;
  return media.legacyUrl;
}

function mediaIdFromUrl(value) {
  try {
    const target = new URL(String(value));
    if (
      target.origin !== publicBase.origin ||
      target.search ||
      target.hash ||
      target.username ||
      target.password
    ) {
      return null;
    }
    const prefix = `${basePath}/media/`;
    if (!target.pathname.startsWith(prefix)) return null;
    const id = target.pathname.slice(prefix.length);
    return /^[0-9a-f-]{36}$/i.test(id) ? id : null;
  } catch {
    return null;
  }
}

function splitLinks(value) {
  return String(value || '')
    .split(';')
    .map((item) => item.trim())
    .filter(Boolean);
}

function requiredEnv(key) {
  const value = process.env[key]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${key}`);
  return value;
}

function arg(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1]?.trim() || null : null;
}
