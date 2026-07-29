import { UnauthorizedException } from '@nestjs/common';
import { AuthSessionService } from './auth-session.service';
import { JwtStrategy } from './jwt.strategy';

const SESSION_EXPIRED_MESSAGE =
  'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
const SESSION_REPLACED_MESSAGE =
  'Tài khoản đã đăng nhập trên thiết bị khác cùng nền tảng. Vui lòng đăng nhập lại.';

describe('JwtStrategy', () => {
  let strategy: JwtStrategy;
  let prisma: { $queryRaw: jest.Mock };

  const payload = {
    sub: 'user-1',
    tokenVersion: 2,
    accessVersion: 7,
    sessionId: 'session-1',
    platform: 'windows',
    sessionVersion: 1,
  };

  const snapshot = (
    user: Record<string, unknown> = {},
    session: Record<string, unknown> = {},
  ) => ({
    id: 'user-1',
    email: 'staff@phongvu.vn',
    password: 'hashed-password',
    tokenVersion: 2,
    accessVersion: 7,
    firstName: 'Staff',
    lastName: null,
    role: 'STAFF',
    status: 'yes',
    avatarUrl: null,
    profileCompletedAt: new Date('2026-01-02T00:00:00.000Z'),
    branchLockedAt: null,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-03T00:00:00.000Z'),
    storeId: null,
    departmentCode: null,
    jobRoleCode: null,
    workScopeType: null,
    regionCode: null,
    areaCode: null,
    organizationNodeId: null,
    authSessionId: 'session-1',
    authSessionUserId: 'user-1',
    authSessionPlatform: 'windows',
    authSessionVersion: 1,
    authSessionRevokedAt: null,
    authSessionExpiresAt: new Date(Date.now() + 60_000),
    ...user,
    ...session,
  });

  beforeEach(() => {
    process.env.JWT_SECRET = 'test-secret';
    prisma = { $queryRaw: jest.fn() };
    const authSessionService = new AuthSessionService(prisma as any, {} as any);
    strategy = new JwtStrategy(prisma as any, authSessionService);
  });

  it('reads the user and platform session through one parameterized snapshot query', async () => {
    prisma.$queryRaw.mockResolvedValue([snapshot()]);

    await expect(strategy.validate(payload)).resolves.toMatchObject({
      id: 'user-1',
      accessVersion: 7,
      authSession: {
        sessionId: 'session-1',
        platform: 'windows',
        sessionVersion: 1,
      },
    });

    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    const [queryParts, sessionId, userId] = prisma.$queryRaw.mock.calls[0];
    const sql = queryParts.join(' ').replace(/\s+/g, ' ').trim();
    expect(sql).toContain('FROM "User" authenticated_user');
    expect(sql).toContain('LEFT JOIN "UserPlatformSession" platform_session');
    expect(sql).toContain('platform_session.id =');
    expect(sql).toContain('authenticated_user.id =');
    expect(sql).toContain('LIMIT 1');
    expect(sessionId).toBe('session-1');
    expect(userId).toBe('user-1');
  });

  it('rejects a deleted user from the same snapshot query', async () => {
    prisma.$queryRaw.mockResolvedValue([]);

    await expect(strategy.validate(payload)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
  });

  it('does not share an active snapshot with a request started after the user is locked', async () => {
    let resolveFirst!: (value: unknown[]) => void;
    prisma.$queryRaw
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveFirst = resolve;
          }),
      )
      .mockResolvedValueOnce([snapshot({ status: 'no' })]);

    const first = strategy.validate(payload);
    const afterLock = strategy.validate(payload);

    await expect(afterLock).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    resolveFirst([snapshot()]);
    await expect(first).resolves.toMatchObject({ id: 'user-1' });
  });

  it('does not share an active snapshot with a request started after token invalidation', async () => {
    let resolveFirst!: (value: unknown[]) => void;
    prisma.$queryRaw
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveFirst = resolve;
          }),
      )
      .mockResolvedValueOnce([snapshot({ tokenVersion: 3 })]);

    const first = strategy.validate(payload);
    const afterTokenChange = strategy.validate(payload);

    await expect(afterTokenChange).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    resolveFirst([snapshot()]);
    await expect(first).resolves.toMatchObject({ id: 'user-1' });
  });

  it.each([
    [
      'session replacement',
      { authSessionVersion: 2 },
      SESSION_REPLACED_MESSAGE,
    ],
    [
      'session revocation',
      { authSessionRevokedAt: new Date() },
      SESSION_EXPIRED_MESSAGE,
    ],
    [
      'session expiry',
      { authSessionExpiresAt: new Date(Date.now() - 60_000) },
      SESSION_EXPIRED_MESSAGE,
    ],
  ])(
    'does not share an active snapshot with a request started after %s',
    async (_label, sessionChange, expectedMessage) => {
      let resolveFirst!: (value: unknown[]) => void;
      prisma.$queryRaw
        .mockImplementationOnce(
          () =>
            new Promise((resolve) => {
              resolveFirst = resolve;
            }),
        )
        .mockResolvedValueOnce([snapshot({}, sessionChange)]);

      const first = strategy.validate(payload);
      const afterSessionChange = strategy.validate(payload);

      await expect(afterSessionChange).rejects.toMatchObject({
        response: expect.objectContaining({ message: expectedMessage }),
      });
      expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
      resolveFirst([snapshot()]);
      await expect(first).resolves.toMatchObject({ id: 'user-1' });
    },
  );

  it.each([
    ['missing row', { authSessionId: null }, SESSION_EXPIRED_MESSAGE],
    [
      'different user',
      { authSessionUserId: 'user-2' },
      SESSION_EXPIRED_MESSAGE,
    ],
    [
      'different platform',
      { authSessionPlatform: 'android' },
      SESSION_EXPIRED_MESSAGE,
    ],
  ])('rejects a platform session with %s', async (_label, change, message) => {
    prisma.$queryRaw.mockResolvedValue([snapshot({}, change)]);

    await expect(strategy.validate(payload)).rejects.toMatchObject({
      response: expect.objectContaining({ message }),
    });
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
  });

  it('preserves the Vietnamese missing-claim and invalid-platform responses', async () => {
    prisma.$queryRaw.mockResolvedValue([snapshot()]);

    await expect(
      strategy.validate({ sub: 'user-1', tokenVersion: 2 }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ message: SESSION_EXPIRED_MESSAGE }),
    });
    await expect(
      strategy.validate({ ...payload, platform: 'unsupported' }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ message: SESSION_EXPIRED_MESSAGE }),
    });
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
  });

  it('returns current access state and independent principals for every request', async () => {
    const firstSnapshot = snapshot();
    const secondSnapshot = snapshot(
      {
        accessVersion: 8,
        createdAt: new Date(firstSnapshot.createdAt),
        updatedAt: new Date(firstSnapshot.updatedAt),
        profileCompletedAt: new Date(firstSnapshot.profileCompletedAt),
      },
      { authSessionExpiresAt: new Date(firstSnapshot.authSessionExpiresAt) },
    );
    prisma.$queryRaw
      .mockResolvedValueOnce([firstSnapshot])
      .mockResolvedValueOnce([secondSnapshot]);

    const first = await strategy.validate(payload);
    const second = await strategy.validate(payload);

    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    expect(first).not.toBe(second);
    expect(first.authSession).not.toBe(second.authSession);
    expect(first.createdAt).not.toBe(second.createdAt);
    expect(first.updatedAt).not.toBe(second.updatedAt);
    expect(first.profileCompletedAt).not.toBe(second.profileCompletedAt);
    expect(first.accessVersion).toBe(7);
    expect(second.accessVersion).toBe(8);
  });
});
