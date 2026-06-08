import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { AuthSessionService } from './auth-session.service';

describe('AuthSessionService', () => {
  let service: AuthSessionService;
  let prisma: any;

  beforeEach(() => {
    prisma = {
      userPlatformSession: {
        findUnique: jest.fn(),
        upsert: jest.fn(),
        updateMany: jest.fn(),
      },
    };
    service = new AuthSessionService(prisma);
  });

  it('creates a platform session for the first login', async () => {
    prisma.userPlatformSession.upsert.mockImplementation(
      async ({ create }: any) => ({
        id: 'session-1',
        ...create,
      }),
    );

    await expect(
      service.replacePlatformSession(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { platform: 'windows', deviceId: 'device-123456' },
      ),
    ).resolves.toEqual({
      sessionId: 'session-1',
      platform: 'windows',
      sessionVersion: 1,
    });

    expect(prisma.userPlatformSession.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          userId: 'user-1',
          platform: 'windows',
          sessionVersion: 1,
          deviceIdHash: expect.stringMatching(/^[a-f0-9]{64}$/),
        }),
        update: expect.objectContaining({
          sessionVersion: { increment: 1 },
        }),
      }),
    );
  });

  it('replaces an existing session on the same platform', async () => {
    prisma.userPlatformSession.upsert.mockResolvedValue({
      id: 'session-1',
      userId: 'user-1',
      platform: 'android',
      sessionVersion: 2,
    });

    await expect(
      service.replacePlatformSession(
        { id: 'user-1', email: 'staff@phongvu.vn' },
        { platform: 'android', deviceId: 'android-device-1' },
      ),
    ).resolves.toEqual({
      sessionId: 'session-1',
      platform: 'android',
      sessionVersion: 2,
    });

    expect(prisma.userPlatformSession.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId_platform: { userId: 'user-1', platform: 'android' } },
        update: expect.objectContaining({
          sessionVersion: { increment: 1 },
          revokedAt: null,
          revokedReason: null,
        }),
      }),
    );
  });

  it('accepts a JWT session only when active claims match the row', async () => {
    prisma.userPlatformSession.findUnique.mockResolvedValue({
      id: 'session-1',
      userId: 'user-1',
      platform: 'ios',
      sessionVersion: 4,
      revokedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
    });

    await expect(
      service.validateJwtSession('user-1', {
        sessionId: 'session-1',
        platform: 'ios',
        sessionVersion: 4,
      }),
    ).resolves.toEqual({
      sessionId: 'session-1',
      platform: 'ios',
      sessionVersion: 4,
    });
  });

  it('rejects missing JWT session claims to enforce app update immediately', async () => {
    await expect(
      service.validateJwtSession('user-1', { tokenVersion: 0 }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.userPlatformSession.findUnique).not.toHaveBeenCalled();
  });

  it('rejects stale same-platform session versions', async () => {
    prisma.userPlatformSession.findUnique.mockResolvedValue({
      id: 'session-1',
      userId: 'user-1',
      platform: 'windows',
      sessionVersion: 2,
      revokedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
    });

    await expect(
      service.validateJwtSession('user-1', {
        sessionId: 'session-1',
        platform: 'windows',
        sessionVersion: 1,
      }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('returns a clear message when the platform session has expired', async () => {
    prisma.userPlatformSession.findUnique.mockResolvedValue({
      id: 'session-1',
      userId: 'user-1',
      platform: 'windows',
      sessionVersion: 1,
      revokedAt: null,
      expiresAt: new Date(Date.now() - 60_000),
    });

    try {
      await service.validateJwtSession('user-1', {
        sessionId: 'session-1',
        platform: 'windows',
        sessionVersion: 1,
      });
      fail('Expected expired platform session to be rejected');
    } catch (error) {
      expect(error).toBeInstanceOf(UnauthorizedException);
      expect((error as UnauthorizedException).getResponse()).toMatchObject({
        message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      });
    }
  });

  it('rejects unsupported platforms before touching the database', async () => {
    expect(() =>
      service.normalizeDevice({
        platform: 'desktop',
        deviceId: 'device-123456',
      }),
    ).toThrow(BadRequestException);
    expect(prisma.userPlatformSession.findUnique).not.toHaveBeenCalled();
  });
});
