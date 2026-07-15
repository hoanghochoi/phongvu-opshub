import { ADMIN_POLICY_CODES, ADMIN_SETTING_KEYS } from './policy.constants';
import { PolicyService } from './policy.service';

describe('PolicyService', () => {
  let service: PolicyService;
  let prisma: any;
  let policies: Record<string, any>;
  let rules: any[];
  let settings: Record<string, any>;
  let accessChangeService: any;

  const context = {
    id: 'user-1',
    email: 'staff@acare.vn',
    emailDomain: 'acare.vn',
    role: 'STAFF',
    departmentCode: 'SALES',
    jobRoleCode: 'SALE',
    workScopeType: 'STORE',
    regionCode: 'MIEN_NAM',
    areaCode: 'HCM',
    storeCode: 'CP62',
    storeName: 'SR CP62',
  };

  beforeEach(() => {
    policies = {
      [ADMIN_POLICY_CODES.FIFO]: {
        code: ADMIN_POLICY_CODES.FIFO,
        defaultAllowed: false,
        isActive: true,
      },
      [ADMIN_POLICY_CODES.FEEDBACK]: {
        code: ADMIN_POLICY_CODES.FEEDBACK,
        defaultAllowed: true,
        isActive: true,
      },
      [ADMIN_POLICY_CODES.ADMIN_POLICIES]: {
        code: ADMIN_POLICY_CODES.ADMIN_POLICIES,
        defaultAllowed: false,
        isActive: true,
      },
      [ADMIN_POLICY_CODES.ADMIN_USERS]: {
        code: ADMIN_POLICY_CODES.ADMIN_USERS,
        defaultAllowed: false,
        isActive: true,
      },
    };
    rules = [];
    settings = {};
    prisma = {
      adminPolicyDefinition: {
        upsert: jest.fn(),
        findMany: jest.fn(async () => Object.values(policies)),
        findUnique: jest.fn(
          async ({ where }: any) => policies[where.code] ?? null,
        ),
        create: jest.fn(),
        update: jest.fn(),
        delete: jest.fn(),
      },
      adminPolicyRule: {
        findFirst: jest.fn(async () => null),
        findMany: jest.fn(async ({ where }: any) =>
          rules.filter((rule) => rule.policyCode === where.policyCode),
        ),
        findUnique: jest.fn(),
        create: jest.fn(async ({ data }: any) => ({
          id: `rule-${rules.length + 1}`,
          ...data,
        })),
        update: jest.fn(),
        delete: jest.fn(),
      },
      adminSetting: {
        upsert: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(
          async ({ where }: any) => settings[where.key] ?? null,
        ),
        create: jest.fn(),
        update: jest.fn(),
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
        findUnique: jest.fn(async ({ where }: any) => ({
          code: where.code,
          regionCode: 'MIEN_NAM',
        })),
      },
      organizationNode: {
        findMany: jest.fn(async () => []),
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
        findUnique: jest.fn(async ({ where }: any) => ({ id: where.id })),
      },
      $transaction: jest.fn(async (operations: Promise<any>[]) =>
        Promise.all(operations),
      ),
    };
    accessChangeService = {
      publishForAllUsers: jest.fn().mockResolvedValue({
        recipientCount: 1,
        eventCount: 1,
      }),
      publishForOrganizationNodeIds: jest.fn().mockResolvedValue({
        recipientCount: 1,
        eventCount: 1,
      }),
    };
    service = new PolicyService(prisma, accessChangeService);
  });

  it('falls back to policy default when no rule matches', async () => {
    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FEEDBACK),
    ).resolves.toBe(true);
    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(false);
  });

  it('applies explicit allow and deny rules', async () => {
    rules = [
      {
        policyCode: ADMIN_POLICY_CODES.FIFO,
        allowed: true,
        systemRole: 'STAFF',
      },
    ];
    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(true);

    rules = [
      {
        policyCode: ADMIN_POLICY_CODES.FEEDBACK,
        allowed: false,
        systemRole: 'STAFF',
      },
    ];
    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FEEDBACK),
    ).resolves.toBe(false);
  });

  it('lets the more specific matching rule win', async () => {
    rules = [
      {
        policyCode: ADMIN_POLICY_CODES.FIFO,
        allowed: false,
        systemRole: 'STAFF',
      },
      { policyCode: ADMIN_POLICY_CODES.FIFO, allowed: true, storeCode: 'CP62' },
    ];

    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(true);
  });

  it('lets deny win when top matching rules have the same specificity', async () => {
    rules = [
      { policyCode: ADMIN_POLICY_CODES.FIFO, allowed: true, areaCode: 'HCM' },
      { policyCode: ADMIN_POLICY_CODES.FIFO, allowed: false, areaCode: 'HCM' },
    ];

    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(false);
  });

  it('always bypasses policy gates for SUPER_ADMIN', async () => {
    policies[ADMIN_POLICY_CODES.FIFO] = {
      code: ADMIN_POLICY_CODES.FIFO,
      defaultAllowed: false,
      isActive: false,
    };
    rules = [{ policyCode: ADMIN_POLICY_CODES.FIFO, allowed: false }];

    await expect(
      service.canAccessPolicyWithContext(
        { ...context, role: 'SUPER_ADMIN' },
        ADMIN_POLICY_CODES.FIFO,
      ),
    ).resolves.toBe(true);
  });

  it('resolves runtime policy access without seeding defaults on the read path', async () => {
    prisma.user.findUnique.mockResolvedValueOnce(context);

    await expect(
      service.resolvePolicyAccessMap({ id: context.id }),
    ).resolves.toEqual({
      [ADMIN_POLICY_CODES.FIFO]: false,
      [ADMIN_POLICY_CODES.FEEDBACK]: true,
      [ADMIN_POLICY_CODES.ADMIN_POLICIES]: false,
      [ADMIN_POLICY_CODES.ADMIN_USERS]: false,
    });
    expect(prisma.adminPolicyDefinition.upsert).not.toHaveBeenCalled();
    expect(prisma.adminSetting.upsert).not.toHaveBeenCalled();
    expect(prisma.adminPolicyRule.findFirst).not.toHaveBeenCalled();
    expect(prisma.adminPolicyRule.create).not.toHaveBeenCalled();
  });

  it('matches scopeContains against the resolved SR scope', async () => {
    rules = [
      {
        policyCode: ADMIN_POLICY_CODES.FIFO,
        allowed: true,
        scopeContains: 'CP6',
      },
    ];

    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(true);
  });

  it('normalizes configured login domains', async () => {
    settings[ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS] = {
      key: ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS,
      value: ['@acare.vn', 'phongvu.vn', 'acare.vn'],
    };

    await expect(
      service.getAllowedEmailDomains(['fallback.vn']),
    ).resolves.toEqual(['acare.vn', 'phongvu.vn']);
  });

  it('uses AUTH_ALLOWED_EMAIL_DOMAINS instead of organization tree login flags', async () => {
    prisma.organizationNode.findMany.mockResolvedValue([
      {
        emailDomain: 'tree-only.vn',
        loginAllowed: true,
      },
    ]);
    settings[ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS] = {
      key: ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS,
      value: ['phongvu-mna.vn'],
    };

    await expect(
      service.getAllowedEmailDomains(['fallback.vn']),
    ).resolves.toEqual(['phongvu-mna.vn']);
    expect(prisma.organizationNode.findMany).not.toHaveBeenCalled();
  });

  it('creates policy rules in one batch from selected organization nodes', async () => {
    const result = await service.adminCreateRules(
      { role: 'SUPER_ADMIN' },
      {
        policyCode: ADMIN_POLICY_CODES.FIFO,
        allowed: false,
        emailDomains: ['phongvu.vn'],
        systemRoles: ['USER'],
        organizationNodeIds: ['org-store-cp62'],
        note: 'temporary policy block',
      },
    );

    expect(result).toHaveLength(1);
    expect(prisma.adminPolicyRule.create).toHaveBeenCalledTimes(1);
    expect(prisma.adminPolicyRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        policyCode: ADMIN_POLICY_CODES.FIFO,
        allowed: false,
        emailDomain: 'phongvu.vn',
        systemRole: 'USER',
        organizationNodeId: 'org-store-cp62',
        departmentCode: null,
        jobRoleCode: null,
        workScopeType: null,
        regionCode: null,
        areaCode: null,
        storeCode: null,
        userId: null,
        scopeContains: null,
        note: 'temporary policy block',
      }),
    });
    expect(
      accessChangeService.publishForOrganizationNodeIds,
    ).toHaveBeenCalledWith(['org-store-cp62'], 'policy-rule-created');
  });

  it('rejects legacy selectors when managing policy rules', async () => {
    await expect(
      service.adminCreateRules(
        { role: 'SUPER_ADMIN' },
        {
          policyCode: ADMIN_POLICY_CODES.FIFO,
          allowed: true,
          organizationNodeIds: ['org-store-cp62'],
          departmentCodes: ['SALES'],
        },
      ),
    ).rejects.toThrow('Policy rule chi ho tro OrganizationNode');
    expect(prisma.adminPolicyRule.create).not.toHaveBeenCalled();
  });

  it('creates policy rules from organization tree nodes without legacy location selectors', async () => {
    const result = await service.adminCreateRules(
      { role: 'SUPER_ADMIN' },
      {
        policyCode: ADMIN_POLICY_CODES.ADMIN_USERS,
        allowed: true,
        organizationNodeIds: ['org-store-cp62'],
        note: 'tree-only policy',
      },
    );

    expect(result).toHaveLength(1);
    expect(prisma.adminPolicyRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        policyCode: ADMIN_POLICY_CODES.ADMIN_USERS,
        allowed: true,
        organizationNodeId: 'org-store-cp62',
        regionCode: null,
        areaCode: null,
        storeCode: null,
      }),
    });
  });

  it('matches policy rules against the assigned Lv5 node before showroom fallback', async () => {
    rules = [
      {
        policyCode: ADMIN_POLICY_CODES.ADMIN_USERS,
        allowed: true,
        organizationNodeId: 'org-store-cp62-pos-sa',
      },
    ];
    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'user-lv5',
      email: 'sale@phongvu.vn',
      role: 'USER',
      departmentCode: 'SALES',
      jobRoleCode: 'SA',
      workScopeType: 'STORE',
      organizationNodeId: 'org-store-cp62-pos-sa',
      organizationNode: {
        id: 'org-store-cp62-pos-sa',
        displayName: 'Nhan vien ban hang',
      },
      store: {
        id: 'store-62',
        storeId: 'CP62',
        storeName: 'SR CP62',
        organizationNodeId: 'org-store-cp62',
        area: null,
        organizationNode: { id: 'org-store-cp62' },
      },
      region: null,
      area: null,
    });
    prisma.organizationNode.findMany.mockResolvedValueOnce([
      {
        id: 'org-region-mien-nam',
        parentId: null,
        type: 'LV2_REGION',
        code: 'REGION_PHONGVU_MIEN_NAM',
        businessCode: 'MIEN_NAM',
        displayName: 'Mien Nam',
        abbreviation: 'MN',
      },
      {
        id: 'org-area-hcm',
        parentId: 'org-region-mien-nam',
        type: 'LV3_AREA',
        code: 'AREA_PHONGVU_HCM',
        businessCode: 'HCM',
        displayName: 'Ho Chi Minh',
        abbreviation: 'HCM',
      },
      {
        id: 'org-store-cp62',
        parentId: 'org-area-hcm',
        type: 'LV4_STORE',
        code: 'STORE_CP62',
        businessCode: 'CP62',
        displayName: 'SR CP62',
        abbreviation: 'CP62',
      },
      {
        id: 'org-store-cp62-pos-sa',
        parentId: 'org-store-cp62',
        type: 'LV5_POSITION',
        code: 'STORE_CP62_POS_SA',
        businessCode: 'SA',
        displayName: 'Nhan vien ban hang',
        abbreviation: 'SA',
      },
    ]);

    await expect(
      service.canAccessPolicy(
        { id: 'user-lv5' },
        ADMIN_POLICY_CODES.ADMIN_USERS,
      ),
    ).resolves.toBe(true);
  });

  it('updates array-valued settings', async () => {
    settings[ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS] = {
      key: ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS,
      displayName: 'Allowed domains',
      description: '',
      category: 'AUTH',
      value: ['phongvu.vn'],
    };
    prisma.adminSetting.update.mockImplementation(async ({ data }: any) => ({
      ...settings[ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS],
      ...data,
    }));

    await expect(
      service.adminUpdateSetting(
        { role: 'SUPER_ADMIN' },
        ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS,
        { value: ['@acare.vn', 'phongvu.vn'] },
      ),
    ).resolves.toMatchObject({ value: ['acare.vn', 'phongvu.vn'] });
  });
});
