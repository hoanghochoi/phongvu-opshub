import { ADMIN_POLICY_CODES, ADMIN_SETTING_KEYS } from './policy.constants';
import { PolicyService } from './policy.service';

describe('PolicyService', () => {
  let service: PolicyService;
  let prisma: any;
  let policies: Record<string, any>;
  let rules: any[];
  let settings: Record<string, any>;

  const context = {
    id: 'user-1',
    email: 'staff@acaretek.vn',
    emailDomain: 'acaretek.vn',
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
    };
    rules = [];
    settings = {};
    prisma = {
      adminPolicyDefinition: {
        upsert: jest.fn(),
        findMany: jest.fn(async () => Object.values(policies)),
        findUnique: jest.fn(async ({ where }: any) => policies[where.code] ?? null),
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
        create: jest.fn(async ({ data }: any) => ({ id: `rule-${rules.length + 1}`, ...data })),
        update: jest.fn(),
        delete: jest.fn(),
      },
      adminSetting: {
        upsert: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(async ({ where }: any) => settings[where.key] ?? null),
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
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code, regionCode: 'MIEN_NAM' })),
      },
      store: {
        findUnique: jest.fn(async ({ where }: any) => ({ storeId: where.storeId })),
      },
      user: {
        findUnique: jest.fn(async ({ where }: any) => ({ id: where.id })),
      },
      $transaction: jest.fn(async (operations: Promise<any>[]) => Promise.all(operations)),
    };
    service = new PolicyService(prisma);
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
    rules = [{ policyCode: ADMIN_POLICY_CODES.FIFO, allowed: true, systemRole: 'STAFF' }];
    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(true);

    rules = [{ policyCode: ADMIN_POLICY_CODES.FEEDBACK, allowed: false, systemRole: 'STAFF' }];
    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FEEDBACK),
    ).resolves.toBe(false);
  });

  it('lets the more specific matching rule win', async () => {
    rules = [
      { policyCode: ADMIN_POLICY_CODES.FIFO, allowed: false, systemRole: 'STAFF' },
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
      service.canAccessPolicyWithContext({ ...context, role: 'SUPER_ADMIN' }, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(true);
  });

  it('matches scopeContains against the resolved SR scope', async () => {
    rules = [{ policyCode: ADMIN_POLICY_CODES.FIFO, allowed: true, scopeContains: 'CP6' }];

    await expect(
      service.canAccessPolicyWithContext(context, ADMIN_POLICY_CODES.FIFO),
    ).resolves.toBe(true);
  });

  it('normalizes configured login domains', async () => {
    settings[ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS] = {
      key: ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS,
      value: ['@Acaretek.vn', 'phongvu.vn', 'acaretek.vn'],
    };

    await expect(service.getAllowedEmailDomains(['fallback.vn'])).resolves.toEqual([
      'acaretek.vn',
      'phongvu.vn',
    ]);
  });

  it('creates policy rules in one batch from multiple selected targets', async () => {
    const result = await service.adminCreateRules(
      { role: 'SUPER_ADMIN' },
      {
        policyCode: ADMIN_POLICY_CODES.FIFO,
        allowed: false,
        departmentCodes: ['SALES', 'TECHNICAL'],
        regionCodes: ['MIEN_NAM'],
        areaCodes: ['HCM'],
        userIds: ['user-1', 'user-2'],
        scopeContainsValues: ['CP'],
        note: 'temporary policy block',
      },
    );

    expect(result).toHaveLength(4);
    expect(prisma.adminPolicyRule.create).toHaveBeenCalledTimes(4);
    expect(prisma.adminPolicyRule.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        policyCode: ADMIN_POLICY_CODES.FIFO,
        allowed: false,
        departmentCode: 'SALES',
        regionCode: 'MIEN_NAM',
        areaCode: 'HCM',
        userId: 'user-1',
        scopeContains: 'CP',
        note: 'temporary policy block',
      }),
    });
  });
});