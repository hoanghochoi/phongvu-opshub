import 'dotenv/config';
import { createPrismaClient } from './prisma-local.mjs';

const CONFIRMATION = 'ROLLBACK_PRIVATE_MEDIA_REFERENCES_V1';
const apply = process.argv.includes('--apply');
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
  const rows = await prisma.user.findMany({
    where: { avatarUrl: { contains: '/media/' } },
    select: { id: true, avatarUrl: true },
  });
  for (const row of rows) {
    const next = await legacyReference(row.avatarUrl, 'AVATAR', row.id);
    if (next === row.avatarUrl) continue;
    report.recordsChanged.avatar += 1;
    if (apply) {
      await prisma.user.update({ where: { id: row.id }, data: { avatarUrl: next } });
    }
  }
}

async function rollbackWarranties() {
  const rows = await prisma.warranty.findMany({
    where: { imageLinks: { contains: '/media/' } },
    select: { id: true, imageLinks: true },
  });
  for (const row of rows) {
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
  const rows = await prisma.feedback.findMany({
    where: { content: { contains: '/media/' } },
    select: { id: true, content: true },
  });
  for (const row of rows) {
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
