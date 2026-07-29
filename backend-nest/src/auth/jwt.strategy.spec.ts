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

  afterEach(() => {
    jest.useRealTimers();
  });

  it('batches only callers waiting before the authoritative snapshot query', async () => {
    jest.useFakeTimers();
    const sharedSnapshot = snapshot({
      branchLockedAt: new Date('2026-01-02T01:00:00.000Z'),
    });
    prisma.$queryRaw.mockResolvedValue([sharedSnapshot]);

    const first = strategy.validate(payload);
    const joined = strategy.validate(payload);
    expect(prisma.$queryRaw).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(2);
    const [firstPrincipal, joinedPrincipal] = await Promise.all([
      first,
      joined,
    ]);

    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    expect((strategy as any).pendingValidationBatches.size).toBe(0);
    expect(firstPrincipal).not.toBe(joinedPrincipal);
    expect(firstPrincipal.authSession).not.toBe(joinedPrincipal.authSession);
    expect(firstPrincipal.createdAt).not.toBe(joinedPrincipal.createdAt);
    expect(firstPrincipal.updatedAt).not.toBe(joinedPrincipal.updatedAt);
    expect(firstPrincipal.profileCompletedAt).not.toBe(
      joinedPrincipal.profileCompletedAt,
    );
    expect(firstPrincipal.branchLockedAt).not.toBe(
      joinedPrincipal.branchLockedAt,
    );
  });

  it('reduces a 250-request burst across 60 principals to 60 snapshot queries', async () => {
    jest.useFakeTimers();
    prisma.$queryRaw.mockImplementation(
      (_queryParts, sessionId: string, userId: string) =>
        Promise.resolve([
          snapshot(
            { id: userId },
            {
              authSessionId: sessionId,
              authSessionUserId: userId,
            },
          ),
        ]),
    );

    const validations = Array.from({ length: 250 }, (_, index) => {
      const principal = index % 60;
      return strategy.validate({
        ...payload,
        sub: `user-${principal}`,
        sessionId: `session-${principal}`,
      });
    });
    await jest.advanceTimersByTimeAsync(2);

    await expect(Promise.all(validations)).resolves.toHaveLength(250);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(60);
    expect((strategy as any).pendingValidationBatches.size).toBe(0);
  });

  it('does not collapse exact and whitespace-prefixed user claims into one batch', async () => {
    jest.useFakeTimers();
    prisma.$queryRaw
      .mockResolvedValueOnce([snapshot()])
      .mockResolvedValueOnce([]);

    const exact = strategy.validate(payload);
    const differentClaim = strategy.validate({ ...payload, sub: ' user-1' });
    const exactExpectation = expect(exact).resolves.toMatchObject({
      id: 'user-1',
    });
    const differentClaimExpectation = expect(
      differentClaim,
    ).rejects.toBeInstanceOf(UnauthorizedException);
    await jest.advanceTimersByTimeAsync(2);

    await exactExpectation;
    await differentClaimExpectation;
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
  });

  it('uses post-change state when a lock commits before the batch query starts', async () => {
    jest.useFakeTimers();
    prisma.$queryRaw.mockResolvedValue([snapshot({ status: 'no' })]);

    const first = strategy.validate(payload);
    const joinedBeforeQuery = strategy.validate(payload);
    const firstExpectation = expect(first).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    const joinedExpectation = expect(joinedBeforeQuery).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    await jest.advanceTimersByTimeAsync(2);

    await firstExpectation;
    await joinedExpectation;
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
  });

  it('keeps an existing join but independently validates overflow principals when the pending map is full', async () => {
    jest.useFakeTimers();
    const pendingBatches = (strategy as any).pendingValidationBatches as Map<
      string,
      { callers: number; validation: Promise<unknown> }
    >;
    prisma.$queryRaw.mockImplementation(
      (_queryParts, sessionId: string, userId: string) =>
        Promise.resolve([
          snapshot(
            { id: userId },
            {
              authSessionId: sessionId,
              authSessionUserId: userId,
            },
          ),
        ]),
    );

    const existingPayload = {
      ...payload,
      sub: 'existing-user',
      sessionId: 'existing-session',
    };
    const existingFirst = strategy.validate(existingPayload);
    for (let index = 0; index < 4_999; index += 1) {
      pendingBatches.set(`occupied-${index}`, {
        callers: 1,
        validation: new Promise(() => undefined),
      });
    }

    const existingJoin = strategy.validate(existingPayload);
    const overflowA = strategy.validate({
      ...payload,
      sub: 'overflow-user-a',
      sessionId: 'overflow-session-a',
    });
    const overflowB = strategy.validate({
      ...payload,
      sub: 'overflow-user-b',
      sessionId: 'overflow-session-b',
    });

    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    expect(pendingBatches.size).toBe(5_000);
    await jest.advanceTimersByTimeAsync(2);
    await expect(
      Promise.all([existingFirst, existingJoin, overflowA, overflowB]),
    ).resolves.toHaveLength(4);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(3);
    expect(pendingBatches.size).toBe(4_999);
    pendingBatches.clear();
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
    jest.useFakeTimers();
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
    await jest.advanceTimersByTimeAsync(2);
    const afterLock = strategy.validate(payload);
    const afterLockExpectation = expect(afterLock).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    await jest.advanceTimersByTimeAsync(2);

    await afterLockExpectation;
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    resolveFirst([snapshot()]);
    await expect(first).resolves.toMatchObject({ id: 'user-1' });
  });

  it('does not share an active snapshot with a request started after token invalidation', async () => {
    jest.useFakeTimers();
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
    await jest.advanceTimersByTimeAsync(2);
    const afterTokenChange = strategy.validate(payload);
    const afterTokenChangeExpectation = expect(
      afterTokenChange,
    ).rejects.toBeInstanceOf(UnauthorizedException);
    await jest.advanceTimersByTimeAsync(2);

    await afterTokenChangeExpectation;
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
      jest.useFakeTimers();
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
      await jest.advanceTimersByTimeAsync(2);
      const afterSessionChange = strategy.validate(payload);
      const afterSessionChangeExpectation = expect(
        afterSessionChange,
      ).rejects.toMatchObject({
        response: expect.objectContaining({ message: expectedMessage }),
      });
      await jest.advanceTimersByTimeAsync(2);

      await afterSessionChangeExpectation;
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
