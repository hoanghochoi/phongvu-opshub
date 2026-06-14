import { FeatureService } from './feature.service';

describe('FeatureService', () => {
  let service: FeatureService;
  let prisma: any;
  let featureActive: boolean;
  let rules: any[];
  let nodeAssignments: Record<string, boolean>;
  let directNodeActive: boolean;

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
    organizationNodeId: 'org-store-cp62',
    store: {
      storeId: 'CP62',
      storeName: 'CP62',
      organizationNodeId: 'org-store-cp62',
      area,
    },
  };

  const assignmentKey = (
    nodeType: string,
    nodeKey: string,
    featureCode: string,
  ) => `${nodeType}:${nodeKey}:${featureCode}`;

  const setNodeAssignment = (
    featureCode: string,
    enabled: boolean,
    nodeType = 'LV4_STORE',
    nodeKey = 'CP62',
  ) => {
    nodeAssignments[assignmentKey(nodeType, nodeKey, featureCode)] = enabled;
  };

  beforeEach(() => {
    featureActive = true;
    rules = [];
    nodeAssignments = {};
    directNodeActive = true;
    const orgNodes = [
      {
        id: 'org-domain-acare-vn',
        parentId: null,
        type: 'LV0_DOMAIN',
        code: 'DOMAIN_ACARE_VN',
        businessCode: 'ACARE',
        isActive: true,
      },
      {
        id: 'org-region-mien-nam',
        parentId: 'org-domain-acare-vn',
        type: 'LV2_REGION',
        code: 'REGION_ACARE_MIEN_NAM',
        businessCode: 'MIEN_NAM',
        isActive: true,
      },
      {
        id: 'org-area-hcm',
        parentId: 'org-region-mien-nam',
        type: 'LV3_AREA',
        code: 'AREA_ACARE_HCM',
        businessCode: 'HCM',
        isActive: true,
      },
      {
        id: 'org-store-cp62',
        parentId: 'org-area-hcm',
        type: 'LV4_STORE',
        code: 'STORE_CP62',
        businessCode: 'CP62',
        isActive: directNodeActive,
      },
      {
        id: 'org-store-cp62-sa',
        parentId: 'org-store-cp62',
        type: 'LV5_POSITION',
        code: 'STORE_CP62_SA',
        businessCode: 'SA',
        isActive: true,
      },
    ];
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
        findUnique: jest.fn(async () => ({ enabled: true })),
        createMany: jest.fn(),
      },
      organizationNodeFeatureAssignment: {
        findUnique: jest.fn(async ({ where }: any) => {
          const input = where.scopeRootNodeId_nodeType_nodeKey_featureCode;
          const key = assignmentKey(
            input.nodeType,
            input.nodeKey,
            input.featureCode,
          );
          if (
            input.scopeRootNodeId !== 'org-domain-acare-vn' ||
            !(key in nodeAssignments)
          ) {
            return null;
          }
          return { enabled: nodeAssignments[key] };
        }),
        findMany: jest.fn(async () => []),
        upsert: jest.fn(),
        deleteMany: jest.fn(),
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
        findMany: jest.fn(async () =>
          orgNodes.map((node) =>
            node.id === 'org-store-cp62'
              ? { ...node, isActive: directNodeActive }
              : node,
          ),
        ),
        findUnique: jest.fn(async ({ where }: any) =>
          orgNodes.find((node) => node.id === where.id) ?? null,
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
          if (where.id === 'user-lv5') {
            return {
              ...storeUser,
              id: 'user-lv5',
              jobRoleCode: 'SA',
              organizationNodeId: 'org-store-cp62-sa',
            };
          }
          return null;
        }),
      },
    };
    service = new FeatureService(prisma);
  });

  it('allows only features assigned to the direct node group', async () => {
    setNodeAssignment('FIFO', true);

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(true);
    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'BANK_STATEMENTS'),
    ).resolves.toBe(false);
  });

  it('does not use legacy rule or per-user assignment for runtime access', async () => {
    rules = [{ featureCode: 'FIFO', enabled: true, userId: 'user-1' }];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
    expect(prisma.userFeatureAssignment.findUnique).not.toHaveBeenCalled();
  });

  it('denies disabled node feature assignments', async () => {
    setNodeAssignment('FIFO', false);

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('denies inactive features even when assigned', async () => {
    featureActive = false;
    setNodeAssignment('FIFO', true);

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('denies assignments when the direct organization node is inactive', async () => {
    directNodeActive = false;
    setNodeAssignment('FIFO', true);

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('prefers assigned Lv5 organization node over store fallback', async () => {
    setNodeAssignment('FIFO', true, 'LV5_POSITION', 'SA');

    await expect(
      service.canAccessFeature({ id: 'user-lv5' }, 'FIFO'),
    ).resolves.toBe(true);
    expect(
      prisma.organizationNodeFeatureAssignment.findUnique,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          scopeRootNodeId_nodeType_nodeKey_featureCode: {
            scopeRootNodeId: 'org-domain-acare-vn',
            nodeType: 'LV5_POSITION',
            nodeKey: 'SA',
            featureCode: 'FIFO',
          },
        },
      }),
    );
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
