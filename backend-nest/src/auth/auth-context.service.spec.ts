import { AuthContextService } from './auth-context.service';

describe('AuthContextService', () => {
  it('hydrates once and reuses the versioned L1 context', async () => {
    const authService = {
      getUserData: jest.fn(),
      projectUserData: jest.fn().mockResolvedValue({
        firstName: 'An',
        organizationAccessCodes: ['CP01'],
        organizationNodeIds: ['node-1'],
        assignedStores: [{ storeId: 'CP01' }],
      }),
    };
    const featureService = {
      resolveFeatureAccessMap: jest.fn().mockResolvedValue({ HOME: true }),
    };
    const policyService = {
      resolvePolicyAccessMap: jest.fn().mockResolvedValue({ REPORT: true }),
    };
    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue(null) },
    };
    const redis = {
      getJson: jest.fn().mockResolvedValue(null),
      tryAcquireLease: jest.fn().mockResolvedValue('lease-token'),
      releaseLease: jest.fn().mockResolvedValue(undefined),
      setJsonWithTtl: jest.fn().mockResolvedValue(undefined),
    };
    const service = new AuthContextService(
      authService as any,
      featureService as any,
      policyService as any,
      prisma as any,
      redis as any,
    );
    const user = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      tokenVersion: 2,
      accessVersion: 7,
      authSession: { sessionVersion: 3 },
    };

    const first = await service.getContext(user);
    const second = await service.getContext(user);

    expect(second).toBe(first);
    expect(authService.getUserData).not.toHaveBeenCalled();
    expect(authService.projectUserData).toHaveBeenCalledTimes(1);
    expect(prisma.user.findUnique).toHaveBeenCalledTimes(1);
    expect(featureService.resolveFeatureAccessMap).toHaveBeenCalledTimes(1);
    expect(policyService.resolvePolicyAccessMap).toHaveBeenCalledTimes(1);
    expect(first.version).toEqual({
      userId: 'user-1',
      tokenVersion: 2,
      sessionVersion: 3,
      accessVersion: 7,
    });
    expect(redis.setJsonWithTtl).toHaveBeenCalledTimes(1);
  });

  it('returns a stable ETag for the version tuple and projection identity', () => {
    const service = new AuthContextService(
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
    );
    const user = {
      id: 'user-1',
      tokenVersion: 2,
      accessVersion: 7,
      updatedAt: new Date('2026-07-16T09:00:00.000Z'),
      authSession: { sessionVersion: 3 },
    };

    expect(service.etagForUser(user)).toBe(service.etagForUser(user));
    expect(service.etagForUser({ ...user, accessVersion: 8 })).not.toBe(
      service.etagForUser(user),
    );
    expect(
      service.etagForUser({
        ...user,
        updatedAt: new Date('2026-07-16T09:01:00.000Z'),
      }),
    ).not.toBe(service.etagForUser(user));
  });

  it('selects only scope fields before storing the context', async () => {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'user-1',
          email: 'staff@phongvu.vn',
          password: 'must-not-be-cached',
          organizationAssignments: [],
        }),
      },
    };
    const service = new AuthContextService(
      { projectUserData: jest.fn().mockResolvedValue({}) } as any,
      { resolveFeatureAccessMap: jest.fn().mockResolvedValue({}) } as any,
      { resolvePolicyAccessMap: jest.fn().mockResolvedValue({}) } as any,
      prisma as any,
      {
        getJson: jest.fn().mockResolvedValue(null),
        tryAcquireLease: jest.fn().mockResolvedValue('lease-token'),
        releaseLease: jest.fn().mockResolvedValue(undefined),
        setJsonWithTtl: jest.fn().mockResolvedValue(undefined),
      } as any,
    );

    await service.getContext({
      id: 'user-1',
      email: 'staff@phongvu.vn',
      tokenVersion: 0,
      accessVersion: 0,
      authSession: { sessionVersion: 1 },
    });

    const query = prisma.user.findUnique.mock.calls[0][0];
    expect(query.select.password).toBeUndefined();
    expect(query.select.tokenVersion).toBeUndefined();
    expect(query.select.accessVersion).toBeUndefined();
  });

  it('serves profile-only requests without hydrating feature or policy maps', async () => {
    const authService = {
      getUserData: jest.fn(),
      projectUserData: jest.fn().mockResolvedValue({ firstName: 'An' }),
    };
    const featureService = {
      resolveFeatureAccessMap: jest.fn(),
    };
    const policyService = {
      resolvePolicyAccessMap: jest.fn(),
    };
    const redis = {
      getJson: jest.fn().mockResolvedValue(null),
      setJsonWithTtl: jest.fn().mockResolvedValue(undefined),
    };
    const service = new AuthContextService(
      authService as any,
      featureService as any,
      policyService as any,
      {
        user: {
          findUnique: jest
            .fn()
            .mockResolvedValue({ id: 'user-1', organizationAssignments: [] }),
        },
      } as any,
      redis as any,
    );

    await expect(
      service.profile({
        id: 'user-1',
        email: 'staff@phongvu.vn',
        tokenVersion: 0,
        accessVersion: 0,
        authSession: { sessionVersion: 1 },
      }),
    ).resolves.toEqual({ firstName: 'An' });
    expect(authService.getUserData).not.toHaveBeenCalled();
    expect(authService.projectUserData).toHaveBeenCalledTimes(1);
    expect(featureService.resolveFeatureAccessMap).not.toHaveBeenCalled();
    expect(policyService.resolvePolicyAccessMap).not.toHaveBeenCalled();
  });
});
