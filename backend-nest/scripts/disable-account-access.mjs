import 'dotenv/config';
import { createPrismaClient } from './prisma-local.mjs';

const REQUIRED_CONFIRMATION = 'DISABLE_ACCOUNT_AND_REVOKE_SESSIONS';

function requiredArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  const value = index < 0 ? null : process.argv[index + 1]?.trim();
  if (!value) throw new Error(`Missing required argument: --${name}`);
  return value;
}

async function main() {
  const email = requiredArg('email').toLowerCase();
  const ticket = requiredArg('ticket');
  const approvedBy = requiredArg('approved-by');
  const confirmation = requiredArg('confirm');
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
      select: { id: true, status: true },
    });
    if (!user) throw new Error('Target account does not exist');
    const now = new Date();

    const revokedSessions = await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: user.id },
        data: { status: 'no', tokenVersion: { increment: 1 } },
      });
      const sessions = await tx.userPlatformSession.updateMany({
        where: { userId: user.id, revokedAt: null },
        data: { revokedAt: now, revokedReason: 'SECURITY_ACCOUNT_DISABLED' },
      });
      await tx.passwordResetToken.updateMany({
        where: { userId: user.id, consumedAt: null },
        data: { consumedAt: now },
      });
      await tx.emailVerificationCode.updateMany({
        where: { email, consumedAt: null },
        data: { consumedAt: now },
      });
      await tx.appLog.create({
        data: {
          level: 'warn',
          source: 'SecurityAccountAccess',
          message: 'Account disabled and active sessions revoked by approved CLI',
          userId: user.id,
          context: { ticket, approvedBy, disabledAt: now.toISOString() },
        },
      });
      return sessions.count;
    });

    process.stdout.write(
      `${JSON.stringify({
        ok: true,
        targetUserId: user.id,
        alreadyDisabled: user.status === 'no',
        revokedSessions,
        disabledAt: now.toISOString(),
      })}\n`,
    );
  } finally {
    await close();
  }
}

main().catch((error) => {
  const safeMessage = String(error?.message ?? error)
    .replace(/postgres(?:ql)?:\/\/[^@\s]+@/gi, 'postgresql://[redacted]@')
    .replace(/redis(?:s)?:\/\/[^@\s]+@/gi, 'redis://[redacted]@');
  process.stderr.write(`Account access was not changed: ${safeMessage}\n`);
  process.exitCode = 1;
});
