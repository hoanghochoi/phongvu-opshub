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

  const setStoreChainAssignment = (featureCode: string, enabled = true) => {
    setNodeAssignment(featureCode, enabled, 'LV2_REGION', 'MIEN_NAM');
    setNodeAssignment(featureCode, enabled, 'LV3_AREA', 'HCM');
    setNodeAssignment(featureCode, enabled, 'LV4_STORE', 'CP62');
  };

  const setLv5ChainAssignment = (featureCode: string, enabled = true) => {
    setStoreChainAssignment(featureCode, enabled);
    setNodeAssignment(featureCode, enabled, 'LV5_POSITION', 'SA');
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
        findMany: jest.fn(async ({ where }: any = {}) => {
          const featureCodes = Array.isArray(where?.featureCode?.in)
            ? where.featureCode.in
            : where?.featureCode
              ? [where.featureCode]
              : [];
          const targets = Array.isArray(where?.OR) ? where.OR : [];
          if (where?.enabled !== true || targets.length === 0) return [];
          const rows: any[] = [];
          for (const target of targets) {
            if (target.scopeRootNodeId !== 'org-domain-acare-vn') continue;
            for (const featureCode of featureCodes) {
              const key = assignmentKey(
                target.nodeType,
                target.nodeKey,
                featureCode,
              );
              if (nodeAssignments[key] === true) {
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
        findUnique: jest.fn(
          async ({ where }: any) =>
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

  it('allows only features assigned to the direct node group and parent chain', async () => {
    setStoreChainAssignment('FIFO');

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(true);
    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'BANK_STATEMENTS'),
    ).resolves.toBe(false);
  });

  it('seeds personnel catalog as a visible admin feature', async () => {
    await service.seedDefaultFeatures();

    expect(prisma.featureDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'ADMIN_PERSONNEL' },
        update: expect.objectContaining({
          displayName: 'Danh mục nhân sự',
          visibleInUserPicker: true,
          sortOrder: 75,
        }),
        create: expect.objectContaining({
          code: 'ADMIN_PERSONNEL',
          displayName: 'Danh mục nhân sự',
          visibleInUserPicker: true,
          sortOrder: 75,
        }),
      }),
    );
  });

  it('denies child node assignments when an organization parent is missing the feature', async () => {
    setNodeAssignment('FIFO', true, 'LV2_REGION', 'MIEN_NAM');
    setNodeAssignment('FIFO', true, 'LV4_STORE', 'CP62');

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('denies child node assignments when a higher non-root ancestor is missing the feature', async () => {
    setNodeAssignment('FIFO', true, 'LV3_AREA', 'HCM');
    setNodeAssignment('FIFO', true, 'LV4_STORE', 'CP62');

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('does not require the root organization node to be assigned', async () => {
    setStoreChainAssignment('FIFO');
    setNodeAssignment('FIFO', false, 'LV0_DOMAIN', 'ACARE');

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(true);
  });

  it('does not grant child nodes from parent assignments alone', async () => {
    setNodeAssignment('FIFO', true, 'LV2_REGION', 'MIEN_NAM');
    setNodeAssignment('FIFO', true, 'LV3_AREA', 'HCM');

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('resolves /features/me with one assignment batch across active features', async () => {
    prisma.featureDefinition.findMany.mockResolvedValueOnce([
      { code: 'FIFO' },
      { code: 'BANK_STATEMENTS' },
    ]);
    prisma.organizationNodeFeatureAssignment.findMany.mockClear();
    setStoreChainAssignment('FIFO');

    await expect(
      service.resolveFeatureAccessMap({ id: 'user-1' }),
    ).resolves.toEqual({
      FIFO: true,
      BANK_STATEMENTS: false,
    });
    expect(
      prisma.organizationNodeFeatureAssignment.findMany,
    ).toHaveBeenCalledTimes(1);
    expect(
      prisma.organizationNodeFeatureAssignment.findMany,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          enabled: true,
          featureCode: { in: ['FIFO', 'BANK_STATEMENTS'] },
        }),
      }),
    );
  });

  it('does not use legacy rule or per-user assignment for runtime access', async () => {
    rules = [{ featureCode: 'FIFO', enabled: true, userId: 'user-1' }];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
    expect(prisma.userFeatureAssignment.findUnique).not.toHaveBeenCalled();
  });

  it('denies disabled node feature assignments', async () => {
    setNodeAssignment('FIFO', true, 'LV2_REGION', 'MIEN_NAM');
    setNodeAssignment('FIFO', true, 'LV3_AREA', 'HCM');
    setNodeAssignment('FIFO', false);

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('denies inactive features even when assigned', async () => {
    featureActive = false;
    setStoreChainAssignment('FIFO');

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('denies assignments when the direct organization node is inactive', async () => {
    directNodeActive = false;
    setStoreChainAssignment('FIFO');

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'FIFO'),
    ).resolves.toBe(false);
  });

  it('prefers assigned Lv5 organization node over store fallback', async () => {
    setLv5ChainAssignment('FIFO');

    await expect(
      service.canAccessFeature({ id: 'user-lv5' }, 'FIFO'),
    ).resolves.toBe(true);
    expect(
      prisma.organizationNodeFeatureAssignment.findMany,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          enabled: true,
          featureCode: { in: ['FIFO'] },
          OR: expect.arrayContaining([
            {
              scopeRootNodeId: 'org-domain-acare-vn',
              nodeType: 'LV5_POSITION',
              nodeKey: 'SA',
            },
            {
              scopeRootNodeId: 'org-domain-acare-vn',
              nodeType: 'LV4_STORE',
              nodeKey: 'CP62',
            },
            {
              scopeRootNodeId: 'org-domain-acare-vn',
              nodeType: 'LV3_AREA',
              nodeKey: 'HCM',
            },
            {
              scopeRootNodeId: 'org-domain-acare-vn',
              nodeType: 'LV2_REGION',
              nodeKey: 'MIEN_NAM',
            },
          ]),
        }),
      }),
    );
  });

  it('requires PAYMENT_SPEAKER separately from PAYMENT_MONITOR for Lv5 nodes', async () => {
    setLv5ChainAssignment('PAYMENT_MONITOR');

    await expect(
      service.canAccessFeature({ id: 'user-lv5' }, 'PAYMENT_SPEAKER'),
    ).resolves.toBe(false);

    setLv5ChainAssignment('PAYMENT_SPEAKER');

    await expect(
      service.canAccessFeature({ id: 'user-lv5' }, 'PAYMENT_SPEAKER'),
    ).resolves.toBe(true);
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

  it('returns readable Vietnamese validation errors for invalid rule batches', async () => {
    await expect(
      service.adminCreateRules(
        { role: 'SUPER_ADMIN' },
        {
          featureCode: 'FIFO',
          enabled: true,
          workScopeTypes: ['NOT_A_SCOPE'],
        },
      ),
    ).rejects.toThrow('Phạm vi tính năng không hợp lệ');

    await expect(
      service.adminCreateRules(
        { role: 'SUPER_ADMIN' },
        {
          featureCode: 'FIFO',
          enabled: true,
          regionCodes: ['MIEN_NAM'],
          areaCodes: ['UNKNOWN'],
        },
      ),
    ).rejects.toThrow('Vùng không tồn tại');
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
