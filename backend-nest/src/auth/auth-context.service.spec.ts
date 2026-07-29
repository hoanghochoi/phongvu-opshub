import { FeatureService } from '../feature/feature.service';
import { AuthContextService } from './auth-context.service';

describe('AuthContextService', () => {
  afterEach(() => {
    jest.useRealTimers();
  });

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

  it('hydrates from PostgreSQL when Redis cache and lease commands fail', async () => {
    const authService = {
      projectUserData: jest.fn().mockResolvedValue({ firstName: 'An' }),
    };
    const featureService = {
      resolveFeatureAccessMap: jest.fn().mockResolvedValue({ HOME: true }),
    };
    const policyService = {
      resolvePolicyAccessMap: jest.fn().mockResolvedValue({ REPORT: true }),
    };
    const redisError = new Error('Redis unavailable');
    const redis = {
      getJson: jest.fn().mockRejectedValue(redisError),
      tryAcquireLease: jest.fn().mockRejectedValue(redisError),
      releaseLease: jest.fn(),
      setJsonWithTtl: jest.fn().mockRejectedValue(redisError),
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
      service.getContext({
        id: 'user-1',
        email: 'staff@phongvu.vn',
        tokenVersion: 0,
        accessVersion: 0,
        authSession: { sessionVersion: 1 },
      }),
    ).resolves.toMatchObject({
      profile: { firstName: 'An' },
      featureAccess: { HOME: true },
      policyAccess: { REPORT: true },
    });
    expect(redis.tryAcquireLease).toHaveBeenCalledTimes(1);
    expect(redis.setJsonWithTtl).toHaveBeenCalledTimes(1);
    expect(redis.releaseLease).not.toHaveBeenCalled();
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
    expect(query.select.organizationNode).toBeUndefined();
    expect(query.select.store.select.organizationNode).toBeUndefined();
    expect(
      query.select.organizationAssignments.select.organizationNode,
    ).toBeUndefined();
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

  it('batches Home scope rows across principals and denies a missing user', async () => {
    jest.useFakeTimers();
    const authService = {
      getUserData: jest.fn(),
      projectUserData: jest.fn(),
    };
    const featureService = {
      resolveFeatureAccessMap: jest.fn(),
      resolveFeatureAccessMapForCodes: jest.fn(),
      resolveFeatureAccessMapsForCodes: jest.fn(
        async (users: any[], featureCodes: string[]) =>
          users.map((user) =>
            Object.fromEntries(
              featureCodes.map((featureCode) => [
                featureCode,
                user.__authScopeSnapshot.id === 'user-1',
              ]),
            ),
          ),
      ),
    };
    const policyService = { resolvePolicyAccessMap: jest.fn() };
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { id: 'user-2', organizationAssignments: [] },
          { id: 'user-1', organizationAssignments: [] },
        ]),
        findUnique: jest.fn(),
      },
    };
    const redis = {
      getJson: jest.fn(),
      setJsonWithTtl: jest.fn(),
      tryAcquireLease: jest.fn(),
      releaseLease: jest.fn(),
    };
    const service = new AuthContextService(
      authService as any,
      featureService as any,
      policyService as any,
      prisma as any,
      redis as any,
    );
    const featureCodes = ['HOME_DASHBOARD_SALES', 'HOME_DASHBOARD_FINANCE'];

    const firstPromise = service.withFeatureScopeContext(
      { id: 'user-1' },
      featureCodes,
    );
    const secondPromise = service.withFeatureScopeContext(
      { id: 'user-2' },
      featureCodes,
    );
    const missingPromise = service.withFeatureScopeContext(
      { id: 'missing-user' },
      featureCodes,
    );
    jest.advanceTimersByTime(20);
    const [first, second, missing] = await Promise.all([
      firstPromise,
      secondPromise,
      missingPromise,
    ]);

    expect(prisma.user.findMany).toHaveBeenCalledTimes(1);
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          id: { in: ['user-1', 'user-2', 'missing-user'] },
        },
      }),
    );
    expect(first.__authContext).toEqual({
      featureAccess: {
        HOME_DASHBOARD_SALES: true,
        HOME_DASHBOARD_FINANCE: true,
      },
      scopeSnapshot: { id: 'user-1', organizationAssignments: [] },
    });
    expect(second.__authContext).toEqual({
      featureAccess: {
        HOME_DASHBOARD_SALES: false,
        HOME_DASHBOARD_FINANCE: false,
      },
      scopeSnapshot: { id: 'user-2', organizationAssignments: [] },
    });
    expect(missing.__authContext).toEqual({
      featureAccess: {
        HOME_DASHBOARD_SALES: false,
        HOME_DASHBOARD_FINANCE: false,
      },
      scopeSnapshot: null,
    });
    expect(
      featureService.resolveFeatureAccessMapsForCodes,
    ).toHaveBeenCalledTimes(1);
    expect(
      featureService.resolveFeatureAccessMapsForCodes,
    ).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({ id: 'user-1' }),
        expect.objectContaining({ id: 'user-2' }),
      ]),
      featureCodes,
    );
    expect(
      featureService.resolveFeatureAccessMapForCodes,
    ).not.toHaveBeenCalled();
    expect(featureService.resolveFeatureAccessMap).not.toHaveBeenCalled();
    expect(authService.getUserData).not.toHaveBeenCalled();
    expect(authService.projectUserData).not.toHaveBeenCalled();
    expect(policyService.resolvePolicyAccessMap).not.toHaveBeenCalled();
    expect(redis.getJson).not.toHaveBeenCalled();
    expect(redis.setJsonWithTtl).not.toHaveBeenCalled();
  });

  it('deduplicates a principal while isolating mixed feature subsets', async () => {
    jest.useFakeTimers();
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([
          { id: 'user-2', organizationAssignments: [] },
          { id: 'user-1', organizationAssignments: [] },
        ]),
        findUnique: jest.fn(),
      },
    };
    const featureService = {
      resolveFeatureAccessMapsForCodes: jest.fn(async (users: any[]) =>
        users.map((user) => ({
          HOME_DASHBOARD_SALES: user.__authScopeSnapshot.id === 'user-1',
          HOME_DASHBOARD_FINANCE: user.__authScopeSnapshot.id === 'user-2',
        })),
      ),
    };
    const service = new AuthContextService(
      {} as any,
      featureService as any,
      {} as any,
      prisma as any,
      {} as any,
    );

    const firstSales = service.withFeatureScopeContext({ id: 'user-1' }, [
      'HOME_DASHBOARD_SALES',
    ]);
    const firstFinance = service.withFeatureScopeContext({ id: 'user-1' }, [
      'HOME_DASHBOARD_FINANCE',
    ]);
    const secondFinance = service.withFeatureScopeContext({ id: 'user-2' }, [
      'HOME_DASHBOARD_FINANCE',
    ]);
    jest.advanceTimersByTime(20);

    await expect(firstSales).resolves.toMatchObject({
      __authContext: {
        featureAccess: { HOME_DASHBOARD_SALES: true },
        scopeSnapshot: { id: 'user-1' },
      },
    });
    await expect(firstFinance).resolves.toMatchObject({
      __authContext: {
        featureAccess: { HOME_DASHBOARD_FINANCE: false },
        scopeSnapshot: { id: 'user-1' },
      },
    });
    await expect(secondFinance).resolves.toMatchObject({
      __authContext: {
        featureAccess: { HOME_DASHBOARD_FINANCE: true },
        scopeSnapshot: { id: 'user-2' },
      },
    });
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: { in: ['user-1', 'user-2'] } },
      }),
    );
    expect(
      featureService.resolveFeatureAccessMapsForCodes,
    ).toHaveBeenCalledTimes(1);
    expect(
      featureService.resolveFeatureAccessMapsForCodes,
    ).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({ id: 'user-1' }),
        expect.objectContaining({ id: 'user-2' }),
      ]),
      ['HOME_DASHBOARD_SALES', 'HOME_DASHBOARD_FINANCE'],
    );
  });

  it('passes each batched scope snapshot through the real feature resolver', async () => {
    jest.useFakeTimers();
    const nodes = [
      {
        id: 'root',
        parentId: null,
        type: 'LV0_DOMAIN',
        code: 'DOMAIN_ACARE_VN',
        businessCode: 'ACARE',
        isActive: true,
      },
      {
        id: 'region',
        parentId: 'root',
        type: 'LV2_REGION',
        code: 'REGION_ACARE_MIEN_NAM',
        businessCode: 'MIEN_NAM',
        isActive: true,
      },
      {
        id: 'area',
        parentId: 'region',
        type: 'LV3_AREA',
        code: 'AREA_ACARE_HCM',
        businessCode: 'HCM',
        isActive: true,
      },
      {
        id: 'store-1',
        parentId: 'area',
        type: 'LV4_STORE',
        code: 'STORE_CP01',
        businessCode: 'CP01',
        isActive: true,
      },
      {
        id: 'store-2',
        parentId: 'area',
        type: 'LV4_STORE',
        code: 'STORE_CP02',
        businessCode: 'CP02',
        isActive: true,
      },
    ];
    const scopeRows = [
      {
        id: 'user-1',
        role: 'STAFF',
        workScopeType: 'STORE',
        organizationNodeId: 'store-1',
        organizationAssignments: [],
      },
      {
        id: 'user-2',
        role: 'STAFF',
        workScopeType: 'STORE',
        organizationNodeId: 'store-2',
        organizationAssignments: [],
      },
    ];
    const grants = new Set([
      'LV2_REGION:MIEN_NAM:HOME_DASHBOARD_SALES',
      'LV3_AREA:HCM:HOME_DASHBOARD_SALES',
      'LV4_STORE:CP01:HOME_DASHBOARD_SALES',
      'LV2_REGION:MIEN_NAM:HOME_DASHBOARD_FINANCE',
      'LV3_AREA:HCM:HOME_DASHBOARD_FINANCE',
      'LV4_STORE:CP02:HOME_DASHBOARD_FINANCE',
    ]);
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue(scopeRows),
        findUnique: jest.fn(),
      },
      featureDefinition: {
        findMany: jest.fn(async ({ where }: any) =>
          where.code.in.map((code: string) => ({ code })),
        ),
      },
      organizationNode: {
        findMany: jest.fn().mockResolvedValue(nodes),
      },
      organizationNodeFeatureAssignment: {
        findMany: jest.fn(async ({ where }: any) => {
          const rows: any[] = [];
          for (const target of where.OR) {
            for (const featureCode of where.featureCode.in) {
              if (
                grants.has(
                  `${target.nodeType}:${target.nodeKey}:${featureCode}`,
                )
              ) {
                rows.push({
                  scopeRootNodeId: target.scopeRootNodeId,
                  nodeType: target.nodeType,
                  nodeKey: target.nodeKey,
                  featureCode,
                });
              }
            }
          }
          return rows;
        }),
      },
    };
    const featureService = new FeatureService(prisma as any, {} as any);
    const service = new AuthContextService(
      {} as any,
      featureService,
      {} as any,
      prisma as any,
      {} as any,
    );
    const featureCodes = ['HOME_DASHBOARD_SALES', 'HOME_DASHBOARD_FINANCE'];

    const firstPromise = service.withFeatureScopeContext(
      { id: 'user-1' },
      featureCodes,
    );
    const secondPromise = service.withFeatureScopeContext(
      { id: 'user-2' },
      featureCodes,
    );
    jest.advanceTimersByTime(20);
    const [first, second] = await Promise.all([firstPromise, secondPromise]);

    expect(first.__authContext.featureAccess).toEqual({
      HOME_DASHBOARD_SALES: true,
      HOME_DASHBOARD_FINANCE: false,
    });
    expect(second.__authContext.featureAccess).toEqual({
      HOME_DASHBOARD_SALES: false,
      HOME_DASHBOARD_FINANCE: true,
    });
    expect(prisma.user.findMany).toHaveBeenCalledTimes(1);
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
    expect(prisma.featureDefinition.findMany).toHaveBeenCalledTimes(1);
    expect(prisma.organizationNode.findMany).toHaveBeenCalledTimes(1);
    expect(
      prisma.organizationNodeFeatureAssignment.findMany,
    ).toHaveBeenCalledTimes(1);
  });

  it('assembles a sorted organization graph from one flat shared tree query', async () => {
    jest.useFakeTimers();
    const nodes = [
      {
        id: 'root',
        parentId: null,
        type: 'LV0_DOMAIN',
        code: 'DOMAIN_ACARE_VN',
        businessCode: 'ACARE',
        displayName: 'Acare',
        abbreviation: null,
        isActive: true,
        sortOrder: 0,
        stores: [],
      },
      {
        id: 'area',
        parentId: 'root',
        type: 'LV3_AREA',
        code: 'AREA_ACARE_HCM',
        businessCode: 'HCM',
        displayName: 'Hồ Chí Minh',
        abbreviation: 'HCM',
        isActive: true,
        sortOrder: 1,
        stores: [],
      },
      {
        id: 'store-2',
        parentId: 'area',
        type: 'LV4_STORE',
        code: 'STORE_CP02',
        businessCode: 'CP02',
        displayName: 'CP02',
        abbreviation: null,
        isActive: true,
        sortOrder: 2,
        stores: [{ storeId: 'CP02', storeName: 'Cửa hàng 02' }],
      },
      {
        id: 'store-1',
        parentId: 'area',
        type: 'LV4_STORE',
        code: 'STORE_CP01',
        businessCode: 'CP01',
        displayName: 'CP01',
        abbreviation: null,
        isActive: true,
        sortOrder: 1,
        stores: [{ storeId: 'CP01', storeName: 'Cửa hàng 01' }],
      },
    ];
    const scopeRow = {
      id: 'user-1',
      organizationNodeId: 'area',
      store: {
        storeId: 'CP01',
        storeName: 'Cửa hàng 01',
        organizationNodeId: 'store-1',
        area: { code: 'HCM', abbreviation: 'HCM', region: null },
      },
      organizationAssignments: [
        {
          isActive: true,
          isPrimary: true,
          createdAt: new Date('2026-07-01T00:00:00.000Z'),
          organizationNodeId: 'store-1',
        },
      ],
    };
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([scopeRow]),
        findUnique: jest.fn(),
      },
      organizationNode: { findMany: jest.fn().mockResolvedValue(nodes) },
    };
    const featureService = {
      resolveFeatureAccessMapsForCodes: jest.fn().mockResolvedValue([{}]),
    };
    const service = new AuthContextService(
      {} as any,
      featureService as any,
      {} as any,
      prisma as any,
      {} as any,
    );

    const promise = service.withFeatureScopeContext({ id: 'user-1' }, [
      'HOME_DASHBOARD_SALES',
    ]);
    jest.advanceTimersByTime(20);
    const enriched = await promise;
    const snapshot = enriched.__authContext.scopeSnapshot;
    const query = prisma.user.findMany.mock.calls[0][0];

    expect(query.select.organizationNode).toBeUndefined();
    expect(query.select.store.select.organizationNode).toBeUndefined();
    expect(
      query.select.organizationAssignments.select.organizationNode,
    ).toBeUndefined();
    expect(prisma.organizationNode.findMany).toHaveBeenCalledTimes(1);
    expect(snapshot.organizationNode.id).toBe('area');
    expect(snapshot.organizationNode.parent.id).toBe('root');
    expect(
      snapshot.organizationNode.children.map((node: any) => node.id),
    ).toEqual(['store-1', 'store-2']);
    expect(() => JSON.stringify(snapshot)).not.toThrow();
    expect(() => JSON.stringify(snapshot)).not.toThrow();
    expect(snapshot.store.organizationNode.id).toBe('store-1');
    expect(snapshot.organizationAssignments[0].organizationNode.parent.id).toBe(
      'area',
    );
  });

  it('uses the same flat-tree enrichment for the independent fallback', async () => {
    const nodes = [
      {
        id: 'root',
        parentId: null,
        type: 'LV0_DOMAIN',
        code: 'DOMAIN_ACARE_VN',
        businessCode: 'ACARE',
        displayName: 'Acare',
        abbreviation: null,
        isActive: true,
        sortOrder: 0,
        stores: [],
      },
      {
        id: 'store-1',
        parentId: 'root',
        type: 'LV4_STORE',
        code: 'STORE_CP01',
        businessCode: 'CP01',
        displayName: 'CP01',
        abbreviation: null,
        isActive: true,
        sortOrder: 1,
        stores: [{ storeId: 'CP01', storeName: 'Cửa hàng 01' }],
      },
    ];
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'user-1',
          organizationNodeId: 'store-1',
          organizationAssignments: [],
        }),
      },
      organizationNode: { findMany: jest.fn().mockResolvedValue(nodes) },
    };
    const featureService = {
      resolveFeatureAccessMapForCodes: jest.fn(async (user: any) => ({
        HOME_DASHBOARD_SALES:
          user.__authScopeSnapshot.organizationNode.id === 'store-1',
      })),
    };
    const service = new AuthContextService(
      {} as any,
      featureService as any,
      {} as any,
      prisma as any,
      {} as any,
    );

    const enriched = await service.withFeatureScopeContext({ id: 'user-1' }, [
      'HOME_DASHBOARD_SALES',
    ]);

    expect(enriched.__authContext.featureAccess).toEqual({
      HOME_DASHBOARD_SALES: true,
    });
    expect(
      enriched.__authContext.scopeSnapshot.organizationNode.parent.id,
    ).toBe('root');
    expect(prisma.organizationNode.findMany).toHaveBeenCalledTimes(1);
  });

  it('caps materialized organization branches at the legacy depth', () => {
    const service = new AuthContextService(
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
    );
    const nodes = Array.from({ length: 10 }, (_, index) => ({
      id: `node-${index}`,
      parentId: index === 0 ? null : `node-${index - 1}`,
      type: index === 9 ? 'LV4_STORE' : 'LV3_AREA',
      code: `NODE_${index}`,
      businessCode: `NODE_${index}`,
      displayName: `Node ${index}`,
      abbreviation: null,
      isActive: true,
      sortOrder: index,
      stores: [],
    }));

    const tree = (service as any).organizationGraph(nodes).treeFor('node-0');
    let cursor = tree;
    for (let depth = 0; depth < 6; depth += 1) {
      expect(cursor.children).toHaveLength(1);
      cursor = cursor.children[0];
    }
    expect(cursor.id).toBe('node-6');
    expect(cursor.children).toEqual([]);
    expect(() => JSON.stringify(tree)).not.toThrow();
  });

  it('detaches the pending Home batch before its query can be shared', async () => {
    jest.useFakeTimers();
    let resolveFirstQuery!: (rows: any[]) => void;
    const firstQuery = new Promise<any[]>((resolve) => {
      resolveFirstQuery = resolve;
    });
    const prisma = {
      user: {
        findMany: jest
          .fn()
          .mockReturnValueOnce(firstQuery)
          .mockResolvedValueOnce([
            { id: 'user-2', organizationAssignments: [] },
          ]),
        findUnique: jest.fn(),
      },
    };
    const featureService = {
      resolveFeatureAccessMapsForCodes: jest.fn(async (users: any[]) =>
        users.map(() => ({ HOME_DASHBOARD_SALES: true })),
      ),
    };
    const service = new AuthContextService(
      {} as any,
      featureService as any,
      {} as any,
      prisma as any,
      {} as any,
    );

    const firstPromise = service.withFeatureScopeContext({ id: 'user-1' }, [
      'HOME_DASHBOARD_SALES',
    ]);
    jest.advanceTimersByTime(20);
    expect(prisma.user.findMany).toHaveBeenCalledTimes(1);

    const secondPromise = service.withFeatureScopeContext({ id: 'user-2' }, [
      'HOME_DASHBOARD_SALES',
    ]);
    jest.advanceTimersByTime(20);
    await expect(secondPromise).resolves.toMatchObject({ id: 'user-2' });
    expect(prisma.user.findMany).toHaveBeenCalledTimes(2);

    resolveFirstQuery([{ id: 'user-1', organizationAssignments: [] }]);
    await expect(firstPromise).resolves.toMatchObject({ id: 'user-1' });
  });

  it('recovers the next Home scope batch after a database failure', async () => {
    jest.useFakeTimers();
    const databaseError = new Error('database unavailable');
    const prisma = {
      user: {
        findMany: jest
          .fn()
          .mockRejectedValueOnce(databaseError)
          .mockResolvedValueOnce([
            { id: 'user-2', organizationAssignments: [] },
          ]),
        findUnique: jest.fn(),
      },
    };
    const service = new AuthContextService(
      {} as any,
      {
        resolveFeatureAccessMapsForCodes: jest.fn(async (users: any[]) =>
          users.map(() => ({ HOME_DASHBOARD_SALES: true })),
        ),
      } as any,
      {} as any,
      prisma as any,
      {} as any,
    );

    const failedPromise = service.withFeatureScopeContext({ id: 'user-1' }, [
      'HOME_DASHBOARD_SALES',
    ]);
    jest.advanceTimersByTime(20);
    await expect(failedPromise).rejects.toBe(databaseError);

    const recoveredPromise = service.withFeatureScopeContext({ id: 'user-2' }, [
      'HOME_DASHBOARD_SALES',
    ]);
    jest.advanceTimersByTime(20);
    await expect(recoveredPromise).resolves.toMatchObject({ id: 'user-2' });
    expect(prisma.user.findMany).toHaveBeenCalledTimes(2);
  });

  it('recovers the next Home batch after batched feature resolution fails', async () => {
    jest.useFakeTimers();
    const featureError = new Error('feature lookup unavailable');
    const prisma = {
      user: {
        findMany: jest.fn(async ({ where }: any) =>
          where.id.in.map((id: string) => ({
            id,
            organizationAssignments: [],
          })),
        ),
        findUnique: jest.fn(),
      },
    };
    const featureService = {
      resolveFeatureAccessMapsForCodes: jest
        .fn()
        .mockRejectedValueOnce(featureError)
        .mockResolvedValueOnce([{ HOME_DASHBOARD_SALES: true }]),
    };
    const service = new AuthContextService(
      {} as any,
      featureService as any,
      {} as any,
      prisma as any,
      {} as any,
    );
    const failureLog = jest
      .spyOn((service as any).logger, 'error')
      .mockImplementation(() => undefined);

    const failedPromise = service.withFeatureScopeContext(
      {
        id: 'user-1',
        email: 'secret.person@phongvu.vn',
        token: 'raw-secret-token',
      },
      ['HOME_DASHBOARD_SALES'],
    );
    const secondFailedPromise = service.withFeatureScopeContext(
      { id: 'user-2' },
      ['HOME_DASHBOARD_SALES'],
    );
    jest.advanceTimersByTime(20);
    await expect(failedPromise).rejects.toBe(featureError);
    await expect(secondFailedPromise).rejects.toBe(featureError);
    expect(failureLog).toHaveBeenCalledTimes(1);
    const failureMessage = String(failureLog.mock.calls[0][0]);
    expect(failureMessage).toContain('callers=2');
    expect(failureMessage).toContain('principals=2');
    expect(failureMessage).toContain('features=1');
    expect(failureMessage).toContain('feature lookup unavailable');
    expect(failureMessage).not.toContain('secret.person@phongvu.vn');
    expect(failureMessage).not.toContain('raw-secret-token');

    const recoveredPromise = service.withFeatureScopeContext({ id: 'user-2' }, [
      'HOME_DASHBOARD_SALES',
    ]);
    jest.advanceTimersByTime(20);
    await expect(recoveredPromise).resolves.toMatchObject({ id: 'user-2' });
    expect(prisma.user.findMany).toHaveBeenCalledTimes(2);
    expect(
      featureService.resolveFeatureAccessMapsForCodes,
    ).toHaveBeenCalledTimes(2);
  });

  it('falls back to an independent scope query when the Home batch is full', async () => {
    jest.useFakeTimers();
    const row = { id: 'user-1', organizationAssignments: [] };
    const overflowRow = { id: 'overflow-user', organizationAssignments: [] };
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValue([row]),
        findUnique: jest.fn().mockResolvedValue(overflowRow),
      },
    };
    const featureService = {
      resolveFeatureAccessMapForCodes: jest
        .fn()
        .mockResolvedValue({ HOME_DASHBOARD_SALES: true }),
      resolveFeatureAccessMapsForCodes: jest.fn(async (users: any[]) =>
        users.map(() => ({ HOME_DASHBOARD_SALES: true })),
      ),
    };
    const service = new AuthContextService(
      {} as any,
      featureService as any,
      {} as any,
      prisma as any,
      {} as any,
    );

    const pending = Array.from({ length: 5_000 }, () =>
      service.withFeatureScopeContext({ id: 'user-1' }, [
        'HOME_DASHBOARD_SALES',
      ]),
    );
    const overflow = service.withFeatureScopeContext({ id: 'overflow-user' }, [
      'HOME_DASHBOARD_SALES',
    ]);

    await expect(overflow).resolves.toMatchObject({ id: 'overflow-user' });
    expect(prisma.user.findUnique).toHaveBeenCalledTimes(1);
    expect(prisma.user.findMany).not.toHaveBeenCalled();
    jest.advanceTimersByTime(20);
    await Promise.all(pending);
    expect(prisma.user.findMany).toHaveBeenCalledTimes(1);
  });
});
