import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { FeatureService } from './feature.service';

describe('FeatureService', () => {
  let service: FeatureService;
  let prisma: any;
  let featureActive: boolean;
  let rules: any[];
  let policyAccess: Record<string, boolean>;
  let policyService: any;

  const area = {
    code: 'HCM',
    abbreviation: 'HCM',
    regionCode: 'MIEN_NAM',
    region: { code: 'MIEN_NAM', abbreviation: 'MN' },
  };
  const storeUser = {
    id: 'user-1',
    email: 'staff@acaretek.vn',
    role: 'STAFF',
    departmentCode: 'SALES',
    jobRoleCode: 'SALE',
    workScopeType: 'STORE',
    store: { storeId: 'CP62', storeName: 'CP62', area },
  };

  beforeEach(() => {
    featureActive = true;
    rules = [];
    policyAccess = {
      [ADMIN_POLICY_CODES.FIFO]: true,
      [ADMIN_POLICY_CODES.BANK_STATEMENTS]: false,
      [ADMIN_POLICY_CODES.ADMIN_USERS]: true,
      [ADMIN_POLICY_CODES.ADMIN_STORES]: true,
      [ADMIN_POLICY_CODES.FIFO_IMPORT]: true,
      [ADMIN_POLICY_CODES.ADMIN_FEATURES]: false,
    };
    policyService = {
      canAccessPolicyWithContext: jest.fn(async (_context: any, code: string) =>
        policyAccess[String(code).toUpperCase()] === true,
      ),
    };
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
    service = new FeatureService(prisma, policyService);
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

  it('allows ADMIN_ACARE through admin-equivalent legacy gates', async () => {
    await expect(
      service.canAccessFeature({ role: 'ADMIN_ACARE' }, 'ADMIN_USERS'),
    ).resolves.toBe(true);
    await expect(
      service.canAccessFeature({ role: 'ADMIN_ACARE' }, 'ADMIN_STORES'),
    ).resolves.toBe(true);
    await expect(
      service.canAccessFeature({ role: 'ADMIN_ACARE' }, 'FIFO_IMPORT'),
    ).resolves.toBe(true);
    await expect(
      service.canAccessFeature({ role: 'ADMIN_ACARE' }, 'ADMIN_FEATURES'),
    ).resolves.toBe(false);
  });

  it('does not let a domain allow override policy authorization', async () => {
    rules = [
      {
        featureCode: 'ADMIN_FEATURES',
        enabled: true,
        emailDomain: 'acaretek.vn',
      },
    ];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'ADMIN_FEATURES'),
    ).resolves.toBe(false);
  });

  it('lets a domain deny beat a user allow', async () => {
    rules = [
      { featureCode: 'FIFO', enabled: true, userId: 'user-1' },
      { featureCode: 'FIFO', enabled: false, emailDomain: 'acaretek.vn' },
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
  it('creates feature rules in one batch from multiple email domains', async () => {
    const result = await service.adminCreateRules(
      { role: 'SUPER_ADMIN' },
      {
        featureCode: 'ADMIN_FEATURES',
        enabled: true,
        emailDomains: ['@Acaretek.vn', 'phongvu.vn'],
        note: 'domain access',
      },
    );

    expect(result).toHaveLength(2);
    expect(prisma.featureAccessRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        featureCode: 'ADMIN_FEATURES',
        enabled: true,
        emailDomain: 'acaretek.vn',
        note: 'domain access',
      }),
    });
    expect(prisma.featureAccessRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        featureCode: 'ADMIN_FEATURES',
        enabled: true,
        emailDomain: 'phongvu.vn',
        note: 'domain access',
      }),
    });
  });
});
