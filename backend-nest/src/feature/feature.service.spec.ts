import { FeatureService } from './feature.service';

describe('FeatureService', () => {
  let service: FeatureService;
  let prisma: any;
  let featureActive: boolean;
  let rules: any[];

  const area = {
    code: 'HCM',
    abbreviation: 'HCM',
    regionCode: 'MIEN_NAM',
    region: { code: 'MIEN_NAM', abbreviation: 'MN' },
  };
  const storeUser = {
    id: 'user-1',
    role: 'STAFF',
    departmentCode: 'SALES',
    jobRoleCode: 'SALE',
    workScopeType: 'STORE',
    store: { storeId: 'CP62', storeName: 'CP62', area },
  };

  beforeEach(() => {
    featureActive = true;
    rules = [];
    prisma = {
      $transaction: jest.fn(async (operations: Promise<any>[]) =>
        Promise.all(operations),
      ),
      featureDefinition: {
        upsert: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(async () => ({ isActive: featureActive })),
      },
      featureAccessRule: {
        findMany: jest.fn(async () => rules),
        create: jest.fn(async ({ data }: any) => ({
          id: `rule-${data.userId ?? 'all'}`,
          ...data,
        })),
      },
      roleDefinition: {
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code })),
      },
      departmentDefinition: {
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code })),
      },
      jobRoleDefinition: {
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code })),
      },
      regionDefinition: {
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code })),
      },
      areaDefinition: {
        findUnique: jest.fn(async ({ where }: any) =>
          where.code === 'HCM' ? { code: 'HCM', regionCode: 'MIEN_NAM' } : null,
        ),
      },
      store: {
        findUnique: jest.fn(async ({ where }: any) => ({
          storeId: where.storeId,
        })),
      },
      user: {
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.id === 'user-1') return storeUser;
          if (where.id === 'user-2') return { ...storeUser, id: 'user-2' };
          return null;
        }),
      },
    };
    service = new FeatureService(prisma);
  });

  it('keeps legacy access when no feature rule matches', async () => {
    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(true);
    await expect(
      service.canAccessFeature(
        { ...storeUser, role: 'STAFF' },
        'BANK_STATEMENTS',
      ),
    ).resolves.toBe(false);
  });

  it('applies explicit deny at API gate level', async () => {
    rules = [{ featureCode: 'FIFO', enabled: false }];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('lets a more specific allow override a broader deny', async () => {
    rules = [
      { featureCode: 'FIFO', enabled: false },
      { featureCode: 'FIFO', enabled: true, areaCode: 'HCM' },
    ];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(true);
  });

  it('does not let feature rules grant access beyond legacy authorization', async () => {
    rules = [
      { featureCode: 'BANK_STATEMENTS', enabled: true, userId: 'user-1' },
    ];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'BANK_STATEMENTS'),
    ).resolves.toBe(false);
  });

  it('resolves STORE-scope feature context from the assigned SR area', async () => {
    const staleRegion = { code: 'MIEN_CU', abbreviation: 'MC' };
    const staleArea = {
      code: 'VUNG_CU',
      abbreviation: 'VC',
      regionCode: staleRegion.code,
      region: staleRegion,
    };
    prisma.user.findUnique.mockResolvedValueOnce({
      ...storeUser,
      regionCode: staleRegion.code,
      areaCode: staleArea.code,
      region: staleRegion,
      area: staleArea,
    });
    rules = [
      { featureCode: 'FIFO', enabled: false, regionCode: staleRegion.code },
    ];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(true);
  });

  it('makes disabled win when top matching rules have the same specificity', async () => {
    rules = [
      { featureCode: 'FIFO', enabled: true, areaCode: 'HCM' },
      { featureCode: 'FIFO', enabled: false, areaCode: 'HCM' },
    ];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('always bypasses feature gates for super admin', async () => {
    featureActive = false;
    rules = [{ featureCode: 'ADMIN_FEATURES', enabled: false }];

    await expect(
      service.canAccessFeature({ role: 'SUPER_ADMIN' }, 'ADMIN_FEATURES'),
    ).resolves.toBe(true);
  });

  it('creates feature rules in one batch from multiple selected targets', async () => {
    const result = await service.adminCreateRules(
      { role: 'SUPER_ADMIN' },
      {
        featureCode: 'FIFO',
        enabled: false,
        departmentCodes: ['SALES', 'TECHNICAL'],
        regionCodes: ['MIEN_NAM'],
        areaCodes: ['HCM'],
        userIds: ['user-1', 'user-2'],
        note: 'temporary block',
      },
    );

    expect(result).toHaveLength(4);
    expect(prisma.featureAccessRule.create).toHaveBeenCalledTimes(4);
    expect(prisma.featureAccessRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        featureCode: 'FIFO',
        enabled: false,
        departmentCode: 'SALES',
        regionCode: 'MIEN_NAM',
        areaCode: 'HCM',
        userId: 'user-1',
        note: 'temporary block',
      }),
    });
  });
});
