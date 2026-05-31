import * as bcrypt from 'bcrypt';
import { createHash } from 'crypto';
import { BadRequestException } from '@nestjs/common';
import { PasswordResetService } from './password-reset.service';

function hashToken(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

describe('PasswordResetService', () => {
  let service: PasswordResetService;
  let prisma: any;
  let mailService: { sendMail: jest.Mock };

  beforeEach(() => {
    process.env.PUBLIC_BASE_URL = 'https://opshub.hoanghochoi.com';
    prisma = {
      user: {
        findUnique: jest.fn(),
        update: jest.fn(),
      },
      passwordResetToken: {
        updateMany: jest.fn(),
        create: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
      },
      userPlatformSession: {
        updateMany: jest.fn(),
      },
      $transaction: jest.fn(async (callback: any) => callback(prisma)),
    };
    mailService = { sendMail: jest.fn().mockResolvedValue(undefined) };
    service = new PasswordResetService(prisma, mailService as any);
  });

  afterEach(() => {
    delete process.env.PUBLIC_BASE_URL;
    delete process.env.PASSWORD_RESET_TTL_MINUTES;
  });

  it('creates a hashed one-time token and sends a reset link without exposing the stored hash', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      status: 'yes',
    });

    await expect(
      service.sendResetLinkForEmail('staff@phongvu-shop.vn'),
    ).resolves.toEqual({ ok: true, expiresInMinutes: 30 });

    expect(prisma.passwordResetToken.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          userId: 'user-1',
          consumedAt: null,
        }),
      }),
    );
    const createData = prisma.passwordResetToken.create.mock.calls[0][0].data;
    expect(createData.tokenHash).toMatch(/^[a-f0-9]{64}$/);
    expect(createData.source).toBe('SELF_SERVICE');
    const emailText = mailService.sendMail.mock.calls[0][0].text;
    expect(emailText).toContain(
      'https://opshub.hoanghochoi.com/reset-password?token=',
    );
    expect(emailText).not.toContain(createData.tokenHash);
  });

  it('returns the same generic response when forgot-password email is missing', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.sendResetLinkForEmail('missing@phongvu-shop.vn'),
    ).resolves.toEqual({ ok: true, expiresInMinutes: 30 });
    expect(mailService.sendMail).not.toHaveBeenCalled();
  });

  it('resets the password, consumes the token, and increments token version', async () => {
    const token = 'valid-reset-token';
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 'token-1',
      userId: 'user-1',
      email: 'staff@phongvu-shop.vn',
      source: 'SELF_SERVICE',
      tokenHash: hashToken(token),
      expiresAt: new Date(Date.now() + 30_000),
      consumedAt: null,
      attempts: 0,
      user: {
        id: 'user-1',
        email: 'staff@phongvu-shop.vn',
        store: null,
      },
    });

    await expect(service.resetPassword(token, 'Password2!')).resolves.toEqual({
      ok: true,
    });

    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'user-1' },
        data: expect.objectContaining({
          password: expect.any(String),
          tokenVersion: { increment: 1 },
        }),
      }),
    );
    const savedPassword = prisma.user.update.mock.calls[0][0].data.password;
    await expect(bcrypt.compare('Password2!', savedPassword)).resolves.toBe(
      true,
    );
    expect(prisma.passwordResetToken.update).toHaveBeenCalledWith({
      where: { id: 'token-1' },
      data: { consumedAt: expect.any(Date) },
    });
    expect(prisma.userPlatformSession.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', revokedAt: null },
      data: {
        revokedAt: expect.any(Date),
        revokedReason: 'PASSWORD_RESET',
      },
    });
  });

  it('increments attempts for a valid token with a weak new password', async () => {
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 'token-1',
      userId: 'user-1',
      email: 'staff@phongvu-shop.vn',
      source: 'SELF_SERVICE',
      tokenHash: hashToken('valid-reset-token'),
      expiresAt: new Date(Date.now() + 30_000),
      consumedAt: null,
      attempts: 0,
      user: { id: 'user-1' },
    });

    await expect(
      service.resetPassword('valid-reset-token', 'weak'),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.passwordResetToken.update).toHaveBeenCalledWith({
      where: { id: 'token-1' },
      data: { attempts: { increment: 1 } },
    });
    expect(prisma.user.update).not.toHaveBeenCalled();
  });
});
