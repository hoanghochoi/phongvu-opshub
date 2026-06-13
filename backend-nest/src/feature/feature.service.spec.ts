import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { FeatureService } from './feature.service';

describe('FeatureService', () => {
  let service: FeatureService;
  let prisma: any;
  let featureActive: boolean;
  let rules: any[];
  let assignments: Record<string, boolean>;
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
    email: 'staff@acare.vn',
    role: 'STAFF',
    departmentCode: 'SALES',
    jobRoleCode: 'SALE',
    workScopeType: 'STORE',
    store: { storeId: 'CP62', storeName: 'CP62', area },
  };

  beforeEach(() => {
    featureActive = true;
    rules = [];
    assignments = {};
    policyAccess = {
      [ADMIN_POLICY_CODES.FIFO]: true,
      [ADMIN_POLICY_CODES.BANK_STATEMENTS]: false,
      [ADMIN_POLICY_CODES.ADMIN_USERS]: true,
      [ADMIN_POLICY_CODES.ADMIN_ORG_TREE]: true,
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
      userFeatureAssignment: {
        findUnique: jest.fn(async ({ where }: any) => {
          const code = where.userId_featureCode.featureCode;
          if (!(code in assignments)) return null;
          return { enabled: assignments[code] };
        }),
        createMany: jest.fn(),
      },
      adminSetting: {
        findUnique: jest.fn(async () => ({ key: 'USER_FEATURE_ALLOWLIST_BACKFILLED_AT' })),
        create: jest.fn(),
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
      organizationNode: {
        findUnique: jest.fn(async ({ where }: any) =>
          where.id === 'org-store-cp62'
            ? { id: 'org-store-cp62', isActive: true }
            : null,
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

  it('allows only features explicitly assigned to the user', async () => {
    assignments = { FIFO: true };

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(true);
    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'BANK_STATEMENTS'),
    ).resolves.toBe(false);
  });

  it('denies legacy rule access without a user feature assignment', async () => {
    rules = [{ featureCode: 'FIFO', enabled: true, userId: 'user-1' }];
    policyAccess[ADMIN_POLICY_CODES.FIFO] = true;

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('denies disabled user feature assignments', async () => {
    assignments = { FIFO: false };

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('denies inactive features even when assigned', async () => {
    featureActive = false;
    assignments = { FIFO: true };

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
        emailDomains: ['@acare.vn', 'phongvu.vn'],
        note: 'domain access',
      },
    );

    expect(result).toHaveLength(2);
    expect(prisma.featureAccessRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        featureCode: 'ADMIN_FEATURES',
        enabled: true,
        emailDomain: 'acare.vn',
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

  it('creates feature rules from organization tree nodes without legacy location selectors', async () => {
    const result = await service.adminCreateRules(
      { role: 'SUPER_ADMIN' },
      {
        featureCode: 'ADMIN_USERS',
        enabled: true,
        organizationNodeIds: ['org-store-cp62'],
        note: 'tree-only access',
      },
    );

    expect(result).toHaveLength(1);
    expect(prisma.featureAccessRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        featureCode: 'ADMIN_USERS',
        enabled: true,
        organizationNodeId: 'org-store-cp62',
        regionCode: null,
        areaCode: null,
        storeCode: null,
      }),
    });
  });

  it('returns only active visible features for the user picker tree', async () => {
    await service.adminListFeatureTree({ role: 'SUPER_ADMIN' });

    expect(prisma.featureDefinition.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { isActive: true, visibleInUserPicker: true },
      }),
    );
  });
});
