import 'dotenv/config';
import { createHash, randomBytes } from 'node:crypto';
import { createPrismaClient } from './prisma-local.mjs';

const PURPOSE = 'PASSWORD_RESET';
const SOURCE = 'EMERGENCY_ADMIN_CLI';
const REQUIRED_CONFIRMATION = 'ISSUE_ONE_TIME_RESET';
const DEFAULT_TTL_MINUTES = 10;
const MAX_TTL_MINUTES = 15;

function readArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  if (index < 0) return null;
  const value = process.argv[index + 1]?.trim();
  return value || null;
}

function requiredArg(name) {
  const value = readArg(name);
  if (!value) throw new Error(`Missing required argument: --${name}`);
  return value;
}

function ttlMinutes() {
  const raw = readArg('ttl-minutes') ?? String(DEFAULT_TTL_MINUTES);
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > MAX_TTL_MINUTES) {
    throw new Error(`--ttl-minutes must be between 1 and ${MAX_TTL_MINUTES}`);
  }
  return value;
}

async function main() {
  const email = requiredArg('email').toLowerCase();
  const ticket = requiredArg('ticket');
  const approvedBy = requiredArg('approved-by');
  const confirmation = requiredArg('confirm');
  const ttl = ttlMinutes();

  if (confirmation !== REQUIRED_CONFIRMATION) {
    throw new Error(`--confirm must equal ${REQUIRED_CONFIRMATION}`);
  }
  if (ticket.length > 120 || approvedBy.length > 120) {
    throw new Error('--ticket and --approved-by must not exceed 120 characters');
  }

  const { prisma, close } = createPrismaClient();
  try {
    const user = await prisma.user.findUnique({
      where: { email },
      select: { id: true, role: true, status: true },
    });
    if (!user || user.role !== 'SUPER_ADMIN' || user.status !== 'yes') {
      throw new Error(
        'Target must already be an active SUPER_ADMIN; this tool never creates users or elevates privileges',
      );
    }

    const resetToken = randomBytes(32).toString('base64url');
    const tokenHash = createHash('sha256').update(resetToken).digest('hex');
    const issuedAt = new Date();
    const expiresAt = new Date(issuedAt.getTime() + ttl * 60 * 1000);

    await prisma.$transaction(async (tx) => {
      await tx.passwordResetToken.updateMany({
        where: { userId: user.id, purpose: PURPOSE, consumedAt: null },
        data: { consumedAt: issuedAt },
      });
      await tx.passwordResetToken.create({
        data: {
          userId: user.id,
          email,
          purpose: PURPOSE,
          tokenHash,
          expiresAt,
          source: SOURCE,
        },
      });
      await tx.appLog.create({
        data: {
          level: 'warn',
          source: 'SecurityEmergencyAccess',
          message:
            'One-time password reset token issued for an approved SUPER_ADMIN account',
          userId: user.id,
          context: {
            ticket,
            approvedBy,
            issuedAt: issuedAt.toISOString(),
            expiresAt: expiresAt.toISOString(),
          },
        },
      });
    });

    process.stderr.write(
      'SECURITY NOTICE: the token below is secret, shown once, and must only be sent through an approved secure channel.\n',
    );
    process.stdout.write(
      `${JSON.stringify(
        {
          ok: true,
          targetUserId: user.id,
          expiresAt: expiresAt.toISOString(),
          resetToken,
        },
        null,
        2,
      )}\n`,
    );
  } finally {
    await close();
  }
}

main().catch((error) => {
  const safeMessage = String(error?.message ?? error)
    .replace(/postgres(?:ql)?:\/\/[^@\s]+@/gi, 'postgresql://[redacted]@')
    .replace(/redis(?:s)?:\/\/[^@\s]+@/gi, 'redis://[redacted]@');
  process.stderr.write(`Emergency reset token was not issued: ${safeMessage}\n`);
  process.exitCode = 1;
});
