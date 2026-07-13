import * as bcrypt from 'bcrypt';
import { createHash } from 'crypto';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PasswordResetService } from './password-reset.service';

function hashToken(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

describe('PasswordResetService', () => {
  jest.setTimeout(15000);

  let service: PasswordResetService;
  let prisma: any;
  let mailService: { sendMail: jest.Mock };

  beforeEach(() => {
    prisma = {
      user: {
        findUnique: jest.fn(),
        update: jest.fn(),
      },
      emailVerificationCode: {
        updateMany: jest.fn(),
        create: jest.fn(),
        findFirst: jest.fn(),
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

  it('sends a 10-minute reset code without creating a reset link', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      status: 'yes',
    });

    await expect(
      service.sendResetCodeForEmail('staff@phongvu-shop.vn'),
    ).resolves.toEqual({ ok: true, expiresInMinutes: 10 });

    expect(prisma.emailVerificationCode.updateMany).toHaveBeenCalledWith({
      where: {
        email: 'staff@phongvu-shop.vn',
        purpose: 'PASSWORD_RESET',
        consumedAt: null,
      },
      data: { consumedAt: expect.any(Date) },
    });
    expect(prisma.passwordResetToken.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          userId: 'user-1',
          purpose: 'PASSWORD_RESET',
          consumedAt: null,
        }),
      }),
    );
    const createData =
      prisma.emailVerificationCode.create.mock.calls[0][0].data;
    expect(createData).toMatchObject({
      email: 'staff@phongvu-shop.vn',
      purpose: 'PASSWORD_RESET',
      codeHash: expect.any(String),
      expiresAt: expect.any(Date),
    });
    const emailText = mailService.sendMail.mock.calls[0][0].text;
    expect(emailText).toContain('Mã đổi mật khẩu PhongVu OpsHub');
    expect(emailText).toContain('10 phút');
    expect(emailText).not.toContain('/reset-password?token=');
    expect(emailText).not.toContain(createData.codeHash);
  });

  it('returns the generic response for a missing account without sending mail', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.sendResetCodeForEmail('missing@phongvu-shop.vn'),
    ).resolves.toEqual({ ok: true, expiresInMinutes: 10 });
    expect(mailService.sendMail).not.toHaveBeenCalled();
  });

  it('verifies a reset code, consumes it, and returns only the plain reset token', async () => {
    const codeHash = await bcrypt.hash('123456', 4);
    prisma.emailVerificationCode.findFirst.mockResolvedValue({
      id: 'code-1',
      email: 'staff@phongvu-shop.vn',
      purpose: 'PASSWORD_RESET',
      codeHash,
      expiresAt: new Date(Date.now() + 30_000),
      consumedAt: null,
      attempts: 0,
    });
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
    });

    const result = await service.verifyResetCode(
      'staff@phongvu-shop.vn',
      '123456',
    );

    expect(result).toMatchObject({ ok: true, expiresInMinutes: 10 });
    expect(result.resetToken).toEqual(expect.any(String));
    expect(prisma.emailVerificationCode.update).toHaveBeenCalledWith({
      where: { id: 'code-1' },
      data: { consumedAt: expect.any(Date) },
    });
    const createData = prisma.passwordResetToken.create.mock.calls[0][0].data;
    expect(createData).toMatchObject({
      userId: 'user-1',
      email: 'staff@phongvu-shop.vn',
      purpose: 'PASSWORD_RESET',
      source: 'SELF_SERVICE',
      tokenHash: expect.stringMatching(/^[a-f0-9]{64}$/),
      expiresAt: expect.any(Date),
    });
    expect(result.resetToken).not.toBe(createData.tokenHash);
  });

  it('increments attempts when reset code verification fails', async () => {
    prisma.emailVerificationCode.findFirst.mockResolvedValue({
      id: 'code-1',
      email: 'staff@phongvu-shop.vn',
      purpose: 'PASSWORD_RESET',
      codeHash: await bcrypt.hash('123456', 4),
      expiresAt: new Date(Date.now() + 30_000),
      consumedAt: null,
      attempts: 0,
    });

    await expect(
      service.verifyResetCode('staff@phongvu-shop.vn', '654321'),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.emailVerificationCode.update).toHaveBeenCalledWith({
      where: { id: 'code-1' },
      data: { attempts: { increment: 1 } },
    });
    expect(prisma.passwordResetToken.create).not.toHaveBeenCalled();
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

  it('sets the first password for an imported passwordless user', async () => {
    const token = 'first-password-token';
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 'token-1',
      userId: 'user-1',
      email: 'imported@phongvu.vn',
      source: 'SELF_SERVICE',
      tokenHash: hashToken(token),
      expiresAt: new Date(Date.now() + 30_000),
      consumedAt: null,
      attempts: 0,
      user: {
        id: 'user-1',
        email: 'imported@phongvu.vn',
        password: '',
        store: null,
      },
    });

    await expect(service.resetPassword(token, 'Password2!')).resolves.toEqual({
      ok: true,
    });

    const savedPassword = prisma.user.update.mock.calls[0][0].data.password;
    expect(savedPassword).toEqual(expect.any(String));
    await expect(bcrypt.compare('Password2!', savedPassword)).resolves.toBe(
      true,
    );
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

  it('lets an admin set a user password directly and revoke sessions', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      status: 'no',
    });

    await expect(
      service.setPasswordForUserId('user-1', 'Password2!', {
        id: 'admin-1',
        email: 'admin@phongvu.vn',
      }),
    ).resolves.toEqual({ ok: true });

    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'user-1' },
        data: expect.objectContaining({
          password: expect.any(String),
          tokenVersion: { increment: 1 },
        }),
      }),
    );
    expect(prisma.userPlatformSession.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', revokedAt: null },
      data: {
        revokedAt: expect.any(Date),
        revokedReason: 'ADMIN_PASSWORD_RESET',
      },
    });
    expect(prisma.emailVerificationCode.updateMany).toHaveBeenCalledWith({
      where: {
        email: 'staff@phongvu-shop.vn',
        purpose: 'PASSWORD_RESET',
        consumedAt: null,
      },
      data: { consumedAt: expect.any(Date) },
    });
  });
});
