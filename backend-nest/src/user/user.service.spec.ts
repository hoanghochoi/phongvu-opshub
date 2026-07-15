import {
  BadRequestException,
  ForbiddenException,
  GoneException,
} from '@nestjs/common';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { UserService } from './user.service';

describe('UserService admin store management', () => {
  let service: UserService;
  let prisma: any;
  let passwordResetService: { setPasswordForUserId: jest.Mock };
  let policyService: any;
  let accessChangeService: any;
  let mailService: { sendMail: jest.Mock };

  const superAdmin = {
    id: 'admin-1',
    email: 'admin@phongvu.vn',
    role: 'SUPER_ADMIN',
  };
  const admin = {
    id: 'admin-phongvu',
    email: 'admin@phongvu.vn',
    role: 'ADMIN_PHONGVU',
  };
  const adminAcare = {
    id: 'admin-acare',
    email: 'admin@acare.vn',
    role: 'ADMIN_ACARE',
    workScopeType: 'NATIONAL',
  };
  const manager = { role: 'MANAGER', storeId: 'store-1' };
  const canonicalType = (type: string) =>
    ({
      ROOT_DOMAIN: 'LV0_DOMAIN',
      BLOCK: 'LV1_BLOCK',
      DEPARTMENT: 'LV2_DEPARTMENT',
      REGION: 'LV2_REGION',
      AREA: 'LV3_AREA',
      VIRTUAL_SCOPE: 'LV3_UNIT',
      SHOWROOM: 'LV4_STORE',
      JOB_ROLE: 'LV5_POSITION',
    })[type] ?? type;
  const region = {
    code: 'MIEN_NAM',
    displayName: 'Mien Nam',
    abbreviation: 'MN',
    isActive: true,
  };
  const area = {
    code: 'HCM',
    displayName: 'Ho Chi Minh',
    abbreviation: 'HCM',
    regionCode: region.code,
    region,
    isActive: true,
  };
  const defaultArea = {
    code: 'CHUA_GAN',
    displayName: 'Chua gan',
    abbreviation: 'CHUA_GAN',
    regionCode: 'CHUA_GAN',
    region: {
      code: 'CHUA_GAN',
      displayName: 'Chua gan',
      abbreviation: 'CHUA_GAN',
      isActive: true,
    },
    isActive: true,
  };
  const chatsaleRegion = {
    code: 'CHATSALE',
    displayName: 'Chatsale',
    abbreviation: 'CHATSALE',
    isActive: true,
  };
  const store = {
    id: 'store-62',
    storeId: 'CP62',
    storeName: 'CP62',
    areaCode: area.code,
    area,
    organizationNodeId: 'org-store-cp62',
  };
  const featureDefinitions = [
    { code: 'ADMIN', parentCode: null },
    { code: 'FIFO', parentCode: null },
    { code: 'FIFO_IMPORT', parentCode: 'FIFO' },
    { code: 'ADMIN_USERS', parentCode: 'ADMIN' },
  ];

  beforeEach(() => {
    prisma = {
      $transaction: jest.fn(async (handler: any) => handler(prisma)),
      store: {
        findMany: jest.fn(),
        findFirst: jest.fn(async ({ where }: any) => {
          if (where.organizationNodeId === 'org-store-cp62') return store;
          if (where.organizationNodeId === 'org-store-cp01') {
            return {
              id: 'store-1',
              storeId: 'CP01',
              storeName: 'CP01',
              areaCode: area.code,
              area,
              organizationNodeId: 'org-store-cp01',
            };
          }
          if (where.organizationNodeId === 'org-store-ac001') {
            return {
              id: 'store-ac001',
              storeId: 'AC001',
              storeName: 'AC001',
              areaCode: area.code,
              area,
              organizationNodeId: 'org-store-ac001',
            };
          }
          return null;
        }),
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.storeId === 'CP62' || where.id === 'store-62') return store;
          if (where.storeId === 'CP01' || where.id === 'store-1') {
            return {
              id: 'store-1',
              storeId: 'CP01',
              storeName: 'CP01',
              areaCode: area.code,
              area,
              organizationNodeId: 'org-store-cp01',
            };
          }
          return null;
        }),
        create: jest.fn(async ({ data }: any) => ({
          id: 'store-1',
          ...data,
          area: data.areaCode === area.code ? area : defaultArea,
          _count: { users: 0 },
        })),
        update: jest.fn(async ({ data }: any) => ({
          id: 'store-1',
          storeId: 'CP01',
          storeName: 'CP01',
          ...data,
          area: data.areaCode === area.code ? area : defaultArea,
          _count: { users: 1 },
        })),
        delete: jest.fn(),
      },
      roleDefinition: {
        upsert: jest.fn(),
        findUnique: jest.fn(async ({ where }: any) => ({
          code: where.code,
          isActive: true,
        })),
      },
      departmentDefinition: {
        upsert: jest.fn(),
        create: jest.fn(async ({ data }: any) => data),
        update: jest.fn(async ({ data }: any) => data),
        delete: jest.fn(),
        findUnique: jest.fn(async ({ where }: any) => ({
          code: where.code,
          isActive: true,
        })),
      },
      jobRoleDefinition: {
        upsert: jest.fn(),
        create: jest.fn(async ({ data }: any) => data),
        update: jest.fn(async ({ data }: any) => data),
        delete: jest.fn(),
        findUnique: jest.fn(async ({ where }: any) => ({
          code: where.code,
          isActive: true,
        })),
      },
      regionDefinition: {
        upsert: jest.fn(),
        findMany: jest.fn(async () => [
          { ...region, _count: { areas: 1, featureAccessRules: 0 } },
        ]),
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.code === chatsaleRegion.code) return chatsaleRegion;
          if (where.code === region.code) return region;
          if (where.code === defaultArea.region.code) return defaultArea.region;
          return null;
        }),
      },
      areaDefinition: {
        upsert: jest.fn(),
        findMany: jest.fn(async () => [
          { ...area, _count: { stores: 1, featureAccessRules: 0 } },
        ]),
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.code === area.code) return area;
          if (where.code === defaultArea.code) return defaultArea;
          if (where.code === chatsaleRegion.code) {
            return {
              ...chatsaleRegion,
              regionCode: chatsaleRegion.code,
              region: chatsaleRegion,
            };
          }
          return null;
        }),
      },
      featureDefinition: {
        findMany: jest.fn(async (args?: any) => {
          const codes = args?.where?.code?.in;
          if (Array.isArray(codes)) {
            return featureDefinitions.filter((feature) =>
              codes.includes(feature.code),
            );
          }
          return featureDefinitions;
        }),
      },
      userFeatureAssignment: {
        deleteMany: jest.fn(async () => ({ count: 0 })),
        createMany: jest.fn(async ({ data }: any) => ({ count: data.length })),
      },
      adminPolicyRule: {
        deleteMany: jest.fn(async () => ({ count: 0 })),
      },
      featureAccessRule: {
        deleteMany: jest.fn(async () => ({ count: 0 })),
      },
      userPlatformSession: {
        deleteMany: jest.fn(async () => ({ count: 0 })),
      },
      passwordResetToken: {
        deleteMany: jest.fn(async () => ({ count: 0 })),
      },
      emailVerificationCode: {
        deleteMany: jest.fn(async () => ({ count: 0 })),
      },
      warranty: {
        count: jest.fn(async () => 0),
      },
      feedback: {
        count: jest.fn(async () => 0),
      },
      fifoLog: {
        count: jest.fn(async () => 0),
      },
      vietQrPaymentIntent: {
        count: jest.fn(async () => 0),
      },
      mapVietinTransaction: {
        count: jest.fn(async () => 0),
      },
      mapVietinTransactionOrderAudit: {
        count: jest.fn(async () => 0),
      },
      organizationNodeFeatureAssignment: {
        count: jest.fn(async () => 0),
      },
      user: {
        findUnique: jest.fn(),
        findMany: jest.fn(async () => []),
        count: jest.fn(async () => 0),
        create: jest.fn(async ({ data }: any) => ({
          id: `user-${data.jobRole?.connect?.code ?? 'NO_ROLE'}`,
          email: data.email,
          firstName: data.firstName,
          lastName: data.lastName,
          role: data.role,
          status: data.status,
          departmentCode: data.department?.connect?.code ?? null,
          jobRoleCode: data.jobRole?.connect?.code ?? null,
          workScopeType: data.workScopeType,
          storeId: data.store?.connect?.id ?? null,
          regionCode: data.region?.connect?.code ?? null,
          areaCode: data.area?.connect?.code ?? null,
          store: data.store?.connect?.id ? store : null,
          region:
            data.region?.connect?.code === chatsaleRegion.code
              ? chatsaleRegion
              : null,
          area: data.area?.connect?.code === area.code ? area : null,
          organizationNodeId: data.organizationNode?.connect?.id ?? null,
          organizationNode: data.organizationNode?.connect?.id
            ? { id: data.organizationNode.connect.id, displayName: 'Node' }
            : null,
        })),
        update: jest.fn(),
        upsert: jest.fn(),
        updateMany: jest.fn(async () => ({ count: 0 })),
        delete: jest.fn(async ({ where }: any) => ({ id: where.id })),
      },
    };
    passwordResetService = {
      setPasswordForUserId: jest.fn().mockResolvedValue({ ok: true }),
    };
    mailService = { sendMail: jest.fn().mockResolvedValue(undefined) };
    process.env.JWT_SECRET = 'test-secret';
    policyService = {
      getAllowedEmailDomains: jest.fn(async (fallback: string[]) => [
        ...fallback,
        'phongvu-mna.vn',
      ]),
      canAccessPolicy: jest.fn(async (user: any, code: string) => {
        if (user?.role === 'SUPER_ADMIN') return true;
        const role = String(user?.role || '').toUpperCase();
        const policyCode = String(code || '').toUpperCase();
        if (policyCode === ADMIN_POLICY_CODES.ADMIN) {
          return ['ADMIN_PHONGVU', 'ADMIN_ACARE', 'MANAGER'].includes(role);
        }
        if (policyCode === ADMIN_POLICY_CODES.ADMIN_STORES) {
          return ['ADMIN_PHONGVU', 'ADMIN_ACARE', 'MANAGER'].includes(role);
        }
        return false;
      }),
    };
    accessChangeService = {
      publishForUserIds: jest.fn().mockResolvedValue({
        recipientCount: 1,
        eventCount: 1,
        failedEventCount: 0,
      }),
      publishForOrganizationNodeIds: jest.fn().mockResolvedValue({
        recipientCount: 1,
        eventCount: 1,
        failedEventCount: 0,
      }),
      publishForAllUsers: jest.fn().mockResolvedValue({
        recipientCount: 1,
        eventCount: 1,
        failedEventCount: 0,
      }),
    };
    service = new UserService(
      prisma,
      {} as any,
      passwordResetService as any,
      policyService,
      accessChangeService,
      mailService as any,
    );
  });

  it('does not create, update or elevate any user during module initialization', async () => {
    jest.spyOn(service as any, 'seedDefaultRoles').mockResolvedValue(undefined);
    jest
      .spyOn(service as any, 'seedDefaultPersonnelCatalog')
      .mockResolvedValue(undefined);
    jest
      .spyOn(service as any, 'seedDefaultOrganizationTree')
      .mockResolvedValue(undefined);
    jest
      .spyOn(service as any, 'syncStoreOrganizationNodes')
      .mockResolvedValue(undefined);

    await service.onModuleInit();

    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(prisma.user.update).not.toHaveBeenCalled();
    expect(prisma.user.updateMany).not.toHaveBeenCalled();
  });

  it('invalidates access only for existing users changed by BigQuery sync', async () => {
    const previousEnv = {
      source: process.env.DATA_SYNC_SOURCE,
      project: process.env.BIGQUERY_PROJECT_ID,
      dataset: process.env.BIGQUERY_USER_DATASET_ID,
      table: process.env.BIGQUERY_USER_TABLE_ID,
    };
    process.env.DATA_SYNC_SOURCE = 'bigquery';
    process.env.BIGQUERY_PROJECT_ID = 'project';
    process.env.BIGQUERY_USER_DATASET_ID = 'dataset';
    process.env.BIGQUERY_USER_TABLE_ID = 'users';
    (service as any).bigquery = {
      query: jest.fn().mockResolvedValue([
        [
          {
            email: 'staff@phongvu.vn',
            first_name: 'Staff',
            role: 'ADMIN',
            status: 'yes',
          },
          {
            email: 'new@phongvu.vn',
            first_name: 'New',
            role: 'USER',
            status: 'yes',
          },
        ],
      ]),
    };
    prisma.user.findMany.mockResolvedValue([
      {
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        status: 'yes',
        workScopeType: 'STORE',
        storeId: 'store-1',
        regionCode: 'MIEN_NAM',
        areaCode: 'HCM',
      },
    ]);
    prisma.user.upsert
      .mockResolvedValueOnce({
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'ADMIN',
        status: 'yes',
        workScopeType: 'NATIONAL',
        storeId: null,
        regionCode: null,
        areaCode: null,
      })
      .mockResolvedValueOnce({
        id: 'user-new',
        email: 'new@phongvu.vn',
        role: 'USER',
        status: 'yes',
        workScopeType: 'STORE',
        storeId: null,
        regionCode: null,
        areaCode: null,
      });

    try {
      await service.syncUsersFromBigQuery();
    } finally {
      if (previousEnv.source === undefined) delete process.env.DATA_SYNC_SOURCE;
      else process.env.DATA_SYNC_SOURCE = previousEnv.source;
      if (previousEnv.project === undefined)
        delete process.env.BIGQUERY_PROJECT_ID;
      else process.env.BIGQUERY_PROJECT_ID = previousEnv.project;
      if (previousEnv.dataset === undefined)
        delete process.env.BIGQUERY_USER_DATASET_ID;
      else process.env.BIGQUERY_USER_DATASET_ID = previousEnv.dataset;
      if (previousEnv.table === undefined)
        delete process.env.BIGQUERY_USER_TABLE_ID;
      else process.env.BIGQUERY_USER_TABLE_ID = previousEnv.table;
    }

    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      ['user-1'],
      'user-access-bigquery-updated',
    );
  });

  function installOrganizationNodeMock() {
    const nodesByCode = new Map<string, any>();
    const nodesById = new Map<string, any>();
    const nodeIdForCode = (code: string) =>
      'org-' + code.toLowerCase().replace(/_/g, '-');
    const saveNode = (node: any) => {
      const saved = { ...node, type: canonicalType(node.type) };
      nodesById.set(saved.id, saved);
      nodesByCode.set(saved.code, saved);
      return saved;
    };

    prisma.organizationNode = {
      upsert: jest.fn(async ({ where, update, create }: any) => {
        const current = nodesByCode.get(where.code);
        if (current) {
          nodesByCode.delete(current.code);
          return saveNode({ ...current, ...update, id: current.id });
        }
        return saveNode({
          id: create.id ?? nodeIdForCode(where.code),
          ...create,
        });
      }),
      create: jest.fn(async ({ data }: any) =>
        saveNode({
          id: data.id ?? nodeIdForCode(data.code),
          ...data,
        }),
      ),
      findUnique: jest.fn(async ({ where }: any) => {
        if (where.id) return nodesById.get(where.id) ?? null;
        if (where.code) return nodesByCode.get(where.code) ?? null;
        return null;
      }),
      findFirst: jest.fn(async ({ where }: any) => {
        return (
          Array.from(nodesById.values()).find((node) => {
            if (
              where.parentId !== undefined &&
              node.parentId !== where.parentId
            ) {
              return false;
            }
            if (
              where.type !== undefined &&
              node.type !== canonicalType(where.type)
            ) {
              return false;
            }
            if (
              where.businessCode !== undefined &&
              node.businessCode !== where.businessCode
            ) {
              return false;
            }
            return true;
          }) ?? null
        );
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const current = where.id
          ? nodesById.get(where.id)
          : nodesByCode.get(where.code);
        if (!current) return null;
        nodesByCode.delete(current.code);
        return saveNode({ ...current, ...data, id: current.id });
      }),
      updateMany: jest.fn(async ({ where, data }: any) => {
        const allowedIds = where?.id?.in ? new Set<string>(where.id.in) : null;
        const activeValue = where?.isActive;
        let count = 0;
        for (const node of Array.from(nodesById.values())) {
          if (allowedIds && !allowedIds.has(node.id)) continue;
          if (activeValue !== undefined && node.isActive !== activeValue) {
            continue;
          }
          saveNode({ ...node, ...data });
          count += 1;
        }
        return { count };
      }),
      findMany: jest.fn(async (args?: any) => {
        const clauses = [
          args?.where,
          ...((args?.where?.AND as any[] | undefined) ?? []),
        ].filter(Boolean);
        const idClause = clauses.find((clause: any) => clause?.id?.in);
        const typeNotClause = clauses.find((clause: any) => clause?.type?.not);
        const activeClause = clauses.find(
          (clause: any) => clause?.isActive !== undefined,
        );
        const allowedIds = idClause?.id?.in
          ? new Set<string>(idClause.id.in)
          : null;
        const disallowedType = typeNotClause?.type?.not;
        const activeValue = activeClause?.isActive;
        return Array.from(nodesById.values())
          .filter((node) => !allowedIds || allowedIds.has(node.id))
          .filter((node) => !disallowedType || node.type !== disallowedType)
          .filter(
            (node) =>
              activeValue === undefined || node.isActive === activeValue,
          )
          .map((node) => ({
            ...node,
            _count: {
              children: 0,
              users: 0,
              stores: node.type === 'LV4_STORE' ? 1 : 0,
              departments: 0,
              jobRoles: 0,
              regions: node.type === 'LV2_REGION' ? 1 : 0,
              areas: node.type === 'LV3_AREA' ? 1 : 0,
            },
          }));
      }),
      delete: jest.fn(),
    };

    return { nodesByCode, nodesById, saveNode };
  }

  function installUserScopeTreeMock() {
    const org = installOrganizationNodeMock();
    org.saveNode({
      id: 'org-domain-phongvu-vn',
      code: 'DOMAIN_PHONGVU_VN',
      displayName: 'phongvu.vn',
      type: 'ROOT_DOMAIN',
      parentId: null,
      emailDomain: 'phongvu.vn',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    org.saveNode({
      id: 'org-domain-acare-vn',
      code: 'DOMAIN_ACARE_VN',
      businessCode: 'ACARE_VN',
      displayName: 'acare.vn',
      type: 'ROOT_DOMAIN',
      parentId: null,
      emailDomain: 'acare.vn',
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    });
    org.saveNode({
      id: 'org-region-mien-nam',
      code: 'REGION_PHONGVU_MIEN_NAM',
      businessCode: region.code,
      displayName: region.displayName,
      type: 'REGION',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 100,
    });
    org.saveNode({
      id: 'org-area-hcm',
      code: 'AREA_PHONGVU_HCM',
      businessCode: area.code,
      displayName: area.displayName,
      type: 'AREA',
      parentId: 'org-region-mien-nam',
      isSystem: false,
      isActive: true,
      sortOrder: 200,
    });
    org.saveNode({
      id: 'org-store-cp62',
      code: 'STORE_CP62',
      businessCode: 'CP62',
      displayName: 'CP62',
      type: 'SHOWROOM',
      parentId: 'org-area-hcm',
      isSystem: false,
      isActive: true,
      sortOrder: 300,
    });
    org.saveNode({
      id: 'org-store-cp01',
      code: 'STORE_CP01',
      businessCode: 'CP01',
      displayName: 'CP01',
      type: 'SHOWROOM',
      parentId: 'org-area-hcm',
      isSystem: false,
      isActive: true,
      sortOrder: 301,
    });
    org.saveNode({
      id: 'org-region-chatsale',
      code: 'REGION_PHONGVU_CHATSALE',
      businessCode: chatsaleRegion.code,
      displayName: chatsaleRegion.displayName,
      type: 'REGION',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 110,
    });
    org.saveNode({
      id: 'org-store-ac001',
      code: 'STORE_AC001',
      businessCode: 'AC001',
      displayName: 'AC001',
      type: 'SHOWROOM',
      parentId: 'org-domain-acare-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 400,
    });
    return org;
  }
  it('normalizes legacy admin role aliases to ADMIN', () => {
    expect((service as any).normalizeRoleCode('ADMIN', true)).toBe('ADMIN');
    expect((service as any).normalizeRoleCode('ADMIN_PHONGVU', true)).toBe(
      'ADMIN',
    );
    expect((service as any).normalizeRoleCode('MANAGER', true)).toBe('ADMIN');
    expect((service as any).normalizeRoleCode('STAFF', true)).toBe('USER');
  });

  it('creates a store with normalized payment fields and default area', async () => {
    installOrganizationNodeMock();
    prisma.store.findUnique.mockImplementationOnce(async () => null);

    await expect(
      service.adminCreateStore(superAdmin, {
        storeId: ' cp99 ',
        storeName: '  Cua hang CP99 ',
        transferAccountNumber: ' 123456 ',
        transferAccountName: ' Phong Vu CP99 ',
        transferBankName: ' VietinBank ',
        transferBankBin: ' 970415 ',
        mapVietinUsername: ' map-user ',
        mapVietinPassword: ' map-pass ',
      }),
    ).resolves.toMatchObject({
      storeId: 'CP99',
      storeName: 'Cua hang CP99',
      areaCode: 'CHUA_GAN',
      regionCode: 'CHUA_GAN',
      transferAccountNumber: '123456',
      transferBankBin: '970415',
      mapVietinUsername: 'map-user',
      hasMapVietinPassword: true,
      userCount: 0,
    });
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'store-organization-created',
    );
  });

  it('lets a manager update only their own store MAP credentials', async () => {
    await expect(
      service.adminUpdateStore(manager, 'CP01', {
        mapVietinUsername: 'manager-map',
        mapVietinPassword: 'new-secret',
      }),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      mapVietinUsername: 'manager-map',
      hasMapVietinPassword: true,
    });

    expect(prisma.store.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          mapVietinUsername: 'manager-map',
          mapVietinPasswordCipher: expect.stringMatching(/^v1:/),
        }),
      }),
    );
  });

  it('lets ADMIN_PHONGVU update only SR MAP credentials', async () => {
    await expect(
      service.adminUpdateStore(admin, 'CP01', {
        mapVietinUsername: 'pv-map',
        mapVietinPassword: 'new-secret',
      }),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      mapVietinUsername: 'pv-map',
      hasMapVietinPassword: true,
    });

    const updateArg = prisma.store.update.mock.calls[0][0];
    expect(updateArg.data).toEqual(
      expect.objectContaining({
        mapVietinUsername: 'pv-map',
        mapVietinPasswordCipher: expect.stringMatching(/^v1:/),
      }),
    );
    expect(updateArg.data.transferAccountNumber).toBeUndefined();
    expect(updateArg.data.transferAccountName).toBeUndefined();
    expect(updateArg.data.transferBankName).toBeUndefined();
    expect(updateArg.data.transferBankBin).toBeUndefined();
  });

  it('blocks ADMIN_ACARE from changing SR transfer account fields', async () => {
    await expect(
      service.adminUpdateStore(adminAcare, 'CP01', {
        transferAccountNumber: '999999',
      }),
    ).rejects.toThrow('số tài khoản nhận tiền');
    expect(prisma.store.update).not.toHaveBeenCalled();
  });

  it('blocks a manager from changing user roles', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu.vn',
      firstName: 'Staff',
      role: 'STAFF',
      status: 'yes',
      storeId: 'store-1',
      store: { storeId: 'CP01', storeName: 'CP01', area },
    });

    await expect(
      service.adminUpdateUser(manager, 'user-1', { role: 'MANAGER' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('scopes ADMIN_ACARE user management to the acare.vn email domain', async () => {
    installUserScopeTreeMock();
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'acare-user',
        email: 'staff@acare.vn',
        firstName: 'ACare',
        lastName: null,
        role: 'STAFF',
        status: 'yes',
        workScopeType: 'STORE',
        storeId: null,
        store: null,
      },
    ]);

    await expect(service.adminListUsers(adminAcare)).resolves.toEqual([
      expect.objectContaining({ email: 'staff@acare.vn' }),
    ]);
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([
            expect.objectContaining({
              OR: expect.arrayContaining([
                {
                  email: {
                    endsWith: '@acare.vn',
                    mode: 'insensitive',
                  },
                },
              ]),
            }),
          ]),
        }),
      }),
    );

    await expect(
      service.adminCreateUser(adminAcare, {
        email: 'new@acare.vn',
        firstName: 'New',
        role: 'STAFF',
        workScopeType: 'STORE',
        organizationNodeId: 'org-store-ac001',
      }),
    ).rejects.toThrow('Bạn không có quyền thêm người dùng');
  });

  it('uses the linked store organization node for legacy store-assigned users', async () => {
    installUserScopeTreeMock();
    prisma.store.findMany.mockResolvedValueOnce([]);
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'legacy-store-user',
        email: 'legacy@phongvu.vn',
        firstName: 'Legacy',
        lastName: null,
        role: 'USER',
        status: 'yes',
        workScopeType: 'STORE',
        storeId: store.id,
        store: {
          ...store,
          organizationNode: {
            id: 'org-store-cp62',
            displayName: 'CP62',
          },
        },
        organizationNodeId: null,
        organizationNode: null,
        userFeatureAssignments: [],
      },
    ]);

    await expect(service.adminListUsers(superAdmin)).resolves.toEqual([
      expect.objectContaining({
        email: 'legacy@phongvu.vn',
        organizationNodeId: 'org-store-cp62',
        organizationNodeName: 'CP62',
        assignmentPending: false,
      }),
    ]);
  });

  it('searches admin users in the database when q is provided', async () => {
    installUserScopeTreeMock();
    const query = 'vu.nt1@phongvu-mna.vn';
    prisma.user.findMany.mockResolvedValueOnce([]);

    await service.adminListUsers(superAdmin, { q: query });

    const where = prisma.user.findMany.mock.calls.at(-1)?.[0]?.where;
    const searchClause = where.AND.find(
      (item: any) =>
        Array.isArray(item.OR) &&
        item.OR.some((condition: any) => condition.email?.contains === query),
    );
    expect(searchClause.OR).toEqual(
      expect.arrayContaining([
        { email: { contains: query, mode: 'insensitive' } },
        { firstName: { contains: query, mode: 'insensitive' } },
        { store: { storeId: { contains: query, mode: 'insensitive' } } },
        {
          organizationAssignments: {
            some: expect.objectContaining({
              isActive: true,
              OR: expect.arrayContaining([
                {
                  organizationNodeId: {
                    contains: query,
                    mode: 'insensitive',
                  },
                },
              ]),
            }),
          },
        },
      ]),
    );
    expect(prisma.user.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({
        take: 200,
        where: expect.objectContaining({
          AND: expect.arrayContaining([searchClause]),
        }),
      }),
    );
  });

  it('blocks ADMIN_ACARE from updating users outside acare.vn', async () => {
    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'phongvu-user',
      email: 'staff@phongvu.vn',
      firstName: 'Phong Vu',
      lastName: null,
      role: 'STAFF',
      status: 'yes',
      workScopeType: 'STORE',
      storeId: null,
      store: null,
    });

    await expect(
      service.adminUpdateUser(adminAcare, 'phongvu-user', {
        firstName: 'Blocked',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('lets a store-manager Lv5 admin list every user in the managed showroom subtree', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-manager',
      code: 'STORE_CP62_POS_STORE_MANAGER',
      businessCode: 'STORE_MANAGER',
      displayName: 'Quản lý Cửa hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    });
    org.saveNode({
      id: 'org-store-cp62-pos-cash',
      code: 'STORE_CP62_POS_CASH',
      businessCode: 'CASH',
      displayName: 'Nhân viên Thu ngân',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 30,
    });
    org.saveNode({
      id: 'org-store-cp01-pos-sa',
      code: 'STORE_CP01_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng CP01',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp01',
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    });
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'cp62-sa',
        email: 'sa@phongvu.vn',
        firstName: 'SA',
        lastName: null,
        role: 'USER',
        status: 'yes',
        workScopeType: 'STORE',
        organizationNodeId: 'org-store-cp62-pos-sa',
        organizationNode: {
          id: 'org-store-cp62-pos-sa',
          displayName: 'Nhân viên Bán hàng',
        },
        storeId: store.id,
        store,
      },
      {
        id: 'cp62-cash',
        email: 'cash@phongvu.vn',
        firstName: 'Cash',
        lastName: null,
        role: 'USER',
        status: 'yes',
        workScopeType: 'STORE',
        organizationNodeId: 'org-store-cp62-pos-cash',
        organizationNode: {
          id: 'org-store-cp62-pos-cash',
          displayName: 'Nhân viên Thu ngân',
        },
        storeId: store.id,
        store,
      },
    ]);

    const scopedAdmin = {
      ...admin,
      email: 'hoang.nv1@phongvu-mna.vn',
      workScopeType: 'STORE',
      storeId: store.id,
      organizationNodeId: 'org-store-cp62-pos-manager',
    };

    await expect(service.adminListUsers(scopedAdmin)).resolves.toEqual([
      expect.objectContaining({ email: 'sa@phongvu.vn' }),
      expect.objectContaining({ email: 'cash@phongvu.vn' }),
    ]);

    const where = prisma.user.findMany.mock.calls.at(-1)?.[0]?.where;
    const locationScope = where.AND[0].AND[1];
    const nodeFilter = locationScope.OR.find(
      (item: any) => item.organizationNodeId,
    );
    expect(nodeFilter.organizationNodeId.in).toEqual(
      expect.arrayContaining([
        'org-store-cp62',
        'org-store-cp62-pos-manager',
        'org-store-cp62-pos-sa',
        'org-store-cp62-pos-cash',
      ]),
    );
    expect(nodeFilter.organizationNodeId.in).not.toContain(
      'org-store-cp01-pos-sa',
    );
  });

  it('lets an area-manager Lv5 admin inherit the complete parent area subtree', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-area-hcm-pos-manager',
      code: 'AREA_HCM_POS_MANAGER',
      businessCode: 'AM',
      displayName: 'Quản lý Vùng',
      type: 'LV5_POSITION',
      parentId: 'org-area-hcm',
      isSystem: false,
      isActive: true,
      sortOrder: 210,
    });
    prisma.user.findMany.mockResolvedValueOnce([]);

    await service.adminListUsers({
      ...admin,
      email: 'area-manager@phongvu.vn',
      workScopeType: 'AREA',
      areaCode: 'HCM',
      organizationNodeId: 'org-area-hcm-pos-manager',
    });

    const where = prisma.user.findMany.mock.calls.at(-1)?.[0]?.where;
    const locationScope = where.AND[0].AND[1];
    const nodeFilter = locationScope.OR.find(
      (item: any) => item.organizationNodeId,
    );
    expect(nodeFilter.organizationNodeId.in).toEqual(
      expect.arrayContaining([
        'org-area-hcm',
        'org-area-hcm-pos-manager',
        'org-store-cp62',
        'org-store-cp01',
      ]),
    );
  });

  it('blocks ADMIN_PHONGVU from creating users', async () => {
    installUserScopeTreeMock();

    await expect(
      service.adminCreateUser(admin, {
        email: 'national@phongvu.vn',
        firstName: 'National',
        role: 'STAFF',
        workScopeType: 'NATIONAL',
        organizationNodeId: 'org-domain-phongvu-vn',
      }),
    ).rejects.toThrow('Bạn không có quyền thêm người dùng');
  });

  it('blocks ADMIN_ACARE from creating users', async () => {
    installUserScopeTreeMock();

    await expect(
      service.adminCreateUser(adminAcare, {
        email: 'national@acare.vn',
        firstName: 'National',
        role: 'STAFF',
        workScopeType: 'NATIONAL',
        organizationNodeId: 'org-domain-acare-vn',
      }),
    ).rejects.toThrow('Bạn không có quyền thêm người dùng');
  });

  it('derives STORE scope from the selected showroom organization node', async () => {
    installUserScopeTreeMock();

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'store@phongvu.vn',
        firstName: 'Store',
        role: 'STAFF',
        storeId: 'CP01',
        departmentCode: 'SALES',
        jobRoleCode: 'SALE',
        workScopeType: 'STORE',
        organizationNodeId: 'org-store-cp62',
      }),
    ).resolves.toMatchObject({
      storeId: 'CP62',
      areaCode: 'HCM',
      regionCode: 'MIEN_NAM',
      organizationNodeId: 'org-store-cp62',
      jobRoleCode: null,
      personnelCode: null,
    });

    expect(prisma.user.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          store: { connect: { id: 'store-62' } },
          area: { connect: { code: 'HCM' } },
          region: { connect: { code: 'MIEN_NAM' } },
          organizationNode: { connect: { id: 'org-store-cp62' } },
        }),
      }),
    );
  });

  it('ignores legacy per-user featureTreeCodes when creating users', async () => {
    installUserScopeTreeMock();

    await service.adminCreateUser(superAdmin, {
      email: 'features@phongvu.vn',
      firstName: 'Feature',
      role: 'STAFF',
      departmentCode: 'SALES',
      jobRoleCode: 'SALE',
      workScopeType: 'STORE',
      organizationNodeId: 'org-store-cp62',
      featureTreeCodes: ['FIFO_IMPORT', 'ADMIN_USERS'],
    });

    expect(prisma.userFeatureAssignment.deleteMany).not.toHaveBeenCalled();
    expect(prisma.userFeatureAssignment.createMany).not.toHaveBeenCalled();
  });

  it('keeps a created user when welcome email fails', async () => {
    installUserScopeTreeMock();
    mailService.sendMail.mockRejectedValueOnce(new Error('smtp down'));

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'welcome@phongvu.vn',
        firstName: 'Welcome',
        role: 'STAFF',
        organizationNodeId: 'org-store-cp62',
      }),
    ).resolves.toMatchObject({
      email: 'welcome@phongvu.vn',
      welcomeEmailSent: false,
      welcomeEmailError: expect.stringContaining('smtp down'),
    });
    expect(prisma.user.create).toHaveBeenCalled();
  });

  it('keeps the ROOT_DOMAIN organization node for NATIONAL scope', async () => {
    installUserScopeTreeMock();

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'national@phongvu.vn',
        firstName: 'National',
        role: 'STAFF',
        workScopeType: 'NATIONAL',
        organizationNodeId: 'org-domain-phongvu-vn',
      }),
    ).resolves.toMatchObject({
      workScopeType: 'NATIONAL',
      organizationNodeId: 'org-domain-phongvu-vn',
      areaCode: null,
      regionCode: null,
    });
  });

  it('blocks scoped admins from editing SUPER_ADMIN users', async () => {
    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'super-1',
      email: 'root@phongvu.vn',
      firstName: 'Root',
      lastName: null,
      role: 'SUPER_ADMIN',
      status: 'yes',
      workScopeType: 'NATIONAL',
      storeId: null,
      store: null,
    });

    await expect(
      service.adminUpdateUser(admin, 'super-1', { firstName: 'Blocked' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('returns only in-domain nodes from the user scope tree endpoint', async () => {
    installUserScopeTreeMock();
    prisma.store.findMany.mockResolvedValueOnce([]);

    const nodes = await service.adminListUserScopeTree(adminAcare);

    expect(nodes.map((node: any) => node.id)).toEqual(
      expect.arrayContaining(['org-domain-acare-vn', 'org-store-ac001']),
    );
    expect(nodes.map((node: any) => node.id)).not.toEqual(
      expect.arrayContaining(['org-domain-phongvu-vn', 'org-store-cp62']),
    );
  });

  it('keeps Lv5 showroom assignments when user scope tree sync refreshes store nodes', async () => {
    const org = installUserScopeTreeMock();
    prisma.store.findMany.mockResolvedValueOnce([store]);

    await service.adminListUserScopeTree(superAdmin);

    const storeSubtreeIds = Array.from(org.nodesById.values())
      .filter(
        (node) =>
          node.id === 'org-store-cp62' || node.parentId === 'org-store-cp62',
      )
      .map((node) => node.id);
    expect(storeSubtreeIds).toEqual(
      expect.arrayContaining([
        'org-store-cp62',
        'org-store-cp62-pos-sa',
        'org-store-cp62-pos-cash',
        'org-store-cp62-pos-warehouse',
      ]),
    );
    expect(prisma.user.updateMany).toHaveBeenNthCalledWith(1, {
      where: {
        storeId: 'store-62',
        workScopeType: 'STORE',
        OR: [
          { areaCode: null },
          { areaCode: { not: 'HCM' } },
          { regionCode: null },
          { regionCode: { not: 'MIEN_NAM' } },
        ],
      },
      data: {
        areaCode: 'HCM',
        regionCode: 'MIEN_NAM',
      },
    });
    expect(prisma.user.updateMany).toHaveBeenNthCalledWith(2, {
      where: {
        storeId: 'store-62',
        workScopeType: 'STORE',
        OR: [
          { organizationNodeId: null },
          { organizationNodeId: { notIn: storeSubtreeIds } },
        ],
      },
      data: {
        organizationNodeId: 'org-store-cp62-pos-cash',
        jobRoleCode: 'CASH',
      },
    });
  });

  it('returns aggregate user counts for organization tree subtrees and legacy store links', async () => {
    installUserScopeTreeMock().saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    });
    prisma.store.findMany.mockResolvedValueOnce([]);
    prisma.user.count.mockImplementation(async ({ where }: any) => {
      const directIds = new Set(where.OR?.[0]?.organizationNodeId?.in ?? []);
      const storeFallbackIds = new Set(
        where.OR?.[1]?.AND?.[1]?.store?.organizationNodeId?.in ?? [],
      );
      let count = 0;
      if (directIds.has('org-store-cp62-pos-sa')) count += 1;
      if (storeFallbackIds.has('org-store-cp62')) count += 1;
      return count;
    });

    const nodes = await service.adminListOrganizationTree(superAdmin);

    expect(
      nodes.find((node: any) => node.id === 'org-store-cp62')?._count.users,
    ).toBe(2);
    expect(
      nodes.find((node: any) => node.id === 'org-area-hcm')?._count.users,
    ).toBe(2);
    expect(
      nodes.find((node: any) => node.id === 'org-store-cp62-pos-sa')?._count
        .users,
    ).toBe(1);
  });

  it('creates Lv1-Lv3 organization nodes without legacy catalog coupling', async () => {
    const org = installUserScopeTreeMock();

    const block = await service.adminCreateOrganizationNode(superAdmin, {
      displayName: 'Kinh Doanh',
      code: 'BLOCK_KINH_DOANH',
      businessCode: 'KINH_DOANH',
      type: 'BLOCK',
      parentId: 'org-domain-phongvu-vn',
      isActive: true,
      sortOrder: 50,
    });
    const regionNode = await service.adminCreateOrganizationNode(superAdmin, {
      displayName: 'Hồ Chí Minh - Bình Dương',
      code: 'HCM-BD',
      businessCode: 'HCM-BD',
      type: 'REGION',
      parentId: block.id,
      isActive: true,
      sortOrder: 100,
    });
    const areaNode = await service.adminCreateOrganizationNode(superAdmin, {
      displayName: 'Hồ Chí Minh 1',
      code: 'HCM1',
      businessCode: 'HCM1',
      type: 'AREA',
      parentId: regionNode.id,
      isActive: true,
      sortOrder: 200,
    });

    expect(block).toMatchObject({
      type: 'LV1_BLOCK',
      parentId: 'org-domain-phongvu-vn',
    });
    expect(regionNode).toMatchObject({
      type: 'LV2_REGION',
      parentId: block.id,
    });
    expect(areaNode).toMatchObject({
      type: 'LV3_AREA',
      parentId: regionNode.id,
    });
    expect(prisma.organizationNode.create).toHaveBeenCalledTimes(3);
    expect(prisma.regionDefinition.upsert).not.toHaveBeenCalled();
    expect(prisma.areaDefinition.upsert).not.toHaveBeenCalled();
    expect(prisma.departmentDefinition.upsert).not.toHaveBeenCalled();
    expect(prisma.jobRoleDefinition.upsert).not.toHaveBeenCalled();
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledTimes(3);
    expect(accessChangeService.publishForAllUsers).toHaveBeenNthCalledWith(
      1,
      'organization-node-created',
    );
    expect(accessChangeService.publishForAllUsers).toHaveBeenNthCalledWith(
      2,
      'organization-node-created',
    );
    expect(accessChangeService.publishForAllUsers).toHaveBeenNthCalledWith(
      3,
      'organization-node-created',
    );
  });

  it('syncs UI-created Lv5 positions and assigns their parent area scope', async () => {
    installUserScopeTreeMock();

    const positionNode = await service.adminCreateOrganizationNode(superAdmin, {
      displayName: 'Quản lý Vùng',
      code: 'LV5_POSITION_AM',
      businessCode: 'AM',
      type: 'LV5_POSITION',
      parentId: 'org-area-hcm',
      isActive: true,
      sortOrder: 250,
    });

    expect(prisma.jobRoleDefinition.upsert).toHaveBeenCalledWith({
      where: { code: 'AM' },
      update: expect.objectContaining({
        displayName: 'Quản lý Vùng',
        departmentCode: null,
        isActive: true,
      }),
      create: expect.objectContaining({
        code: 'AM',
        displayName: 'Quản lý Vùng',
        departmentCode: null,
        isActive: true,
      }),
    });

    prisma.jobRoleDefinition.upsert.mockClear();
    prisma.jobRoleDefinition.findUnique.mockResolvedValueOnce(null);
    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'area-manager@phongvu.vn',
        firstName: 'Area Manager',
        role: 'USER',
        organizationNodeId: positionNode.id,
      }),
    ).resolves.toMatchObject({
      jobRoleCode: 'AM',
      workScopeType: 'AREA',
      storeId: null,
      areaCode: 'HCM',
      regionCode: 'MIEN_NAM',
      organizationNodeId: positionNode.id,
    });
    expect(prisma.jobRoleDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ where: { code: 'AM' } }),
    );
    expect(prisma.user.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          workScopeType: 'AREA',
          jobRole: { connect: { code: 'AM' } },
          organizationNode: { connect: { id: positionNode.id } },
        }),
      }),
    );
  });

  it('retires self-service store selection', async () => {
    await expect(
      service.selectStoreOnce('user-1', 'CP62'),
    ).rejects.toBeInstanceOf(GoneException);
  });

  it('rejects moving an Lv4 store under an equal or lower child level node', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhan vien ban hang',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: false,
      isActive: true,
      sortOrder: 400,
    });

    await expect(
      service.adminUpdateOrganizationNode(superAdmin, 'org-store-cp62', {
        displayName: 'CP62',
        code: 'STORE_CP62',
        businessCode: 'CP62',
        storeId: 'CP62',
        type: 'LV4_STORE',
        parentId: 'org-store-cp62-pos-sa',
        isActive: true,
        sortOrder: 300,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.organizationNode.update).not.toHaveBeenCalled();
    expect(prisma.store.update).not.toHaveBeenCalled();
  });

  it('syncs legacy region and area rows before moving a showroom under a new area node', async () => {
    const org = installUserScopeTreeMock();
    const newRegion = org.saveNode({
      id: 'org-region-hcm-bd',
      code: 'REGION_PHONGVU_HCM_BD',
      businessCode: 'HCM_BD',
      displayName: 'Ho Chi Minh - Binh Duong',
      type: 'REGION',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 120,
    });
    const newArea = org.saveNode({
      id: 'org-area-nguyen-thi-minh-khai',
      code: 'AREA_PHONGVU_NTMK',
      businessCode: 'NTMK',
      displayName: 'Nguyen Thi Minh Khai',
      type: 'AREA',
      parentId: newRegion.id,
      isSystem: false,
      isActive: true,
      sortOrder: 210,
    });

    await expect(
      service.adminUpdateOrganizationNode(superAdmin, 'org-store-cp01', {
        displayName: 'Nguyen Thi Minh Khai',
        code: 'STORE_CP01',
        businessCode: 'CP01',
        storeId: 'CP01',
        storeName: 'Nguyen Thi Minh Khai',
        type: 'LV4_STORE',
        parentId: newArea.id,
        isActive: true,
        sortOrder: 10300,
      }),
    ).resolves.toMatchObject({
      id: 'org-store-cp01',
      type: 'LV4_STORE',
      parentId: newArea.id,
    });

    expect(prisma.regionDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'HCM_BD' },
      }),
    );
    expect(prisma.areaDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'NTMK' },
        create: expect.objectContaining({ regionCode: 'HCM_BD' }),
        update: expect.objectContaining({ regionCode: 'HCM_BD' }),
      }),
    );
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'organization-node-updated',
    );
    expect(
      prisma.areaDefinition.upsert.mock.invocationCallOrder[0],
    ).toBeLessThan(prisma.store.update.mock.invocationCallOrder[0]);
    expect(prisma.store.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          areaCode: 'NTMK',
          organizationNodeId: 'org-store-cp01',
        }),
      }),
    );
    expect(prisma.user.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          areaCode: 'NTMK',
          regionCode: 'HCM_BD',
        }),
      }),
    );
  });

  it('invalidates cached access after deleting an organization node', async () => {
    prisma.organizationNode = {
      findUnique: jest.fn().mockResolvedValue({
        id: 'custom-node',
        isSystem: false,
        _count: { children: 0 },
      }),
      delete: jest.fn().mockResolvedValue({ id: 'custom-node' }),
    };
    jest
      .spyOn(service as any, 'organizationNodeReferenceCounts')
      .mockResolvedValue({
        users: 0,
        stores: 0,
        departments: 0,
        jobRoles: 0,
        regions: 0,
        areas: 0,
        featureRules: 0,
        nodeFeatureAssignments: 0,
        policyRules: 0,
      });

    await expect(
      service.adminDeleteOrganizationNode(superAdmin, 'custom-node'),
    ).resolves.toEqual({ deleted: true, id: 'custom-node' });

    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'organization-node-deleted',
    );
  });

  it('invalidates access after department catalog mutations', async () => {
    const department = {
      code: 'CUSTOM_DEPARTMENT',
      displayName: 'Custom department',
      description: null,
      isSystem: false,
      isActive: true,
    };
    prisma.departmentDefinition.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(department)
      .mockResolvedValueOnce({
        ...department,
        _count: { users: 0, featureAccessRules: 0 },
      });
    prisma.departmentDefinition.create.mockResolvedValue(department);
    prisma.departmentDefinition.update.mockResolvedValue({
      ...department,
      displayName: 'Updated department',
    });

    await service.adminCreateDepartment(superAdmin, department);
    await service.adminUpdateDepartment(superAdmin, department.code, {
      displayName: 'Updated department',
    });
    await service.adminDeleteDepartment(superAdmin, department.code);

    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'personnel-department-created',
    );
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'personnel-department-updated',
    );
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'personnel-department-deleted',
    );
  });

  it('invalidates access after job-role catalog mutations', async () => {
    const jobRole = {
      code: 'CUSTOM_JOB_ROLE',
      displayName: 'Custom job role',
      description: null,
      departmentCode: null,
      isSystem: false,
      isActive: true,
    };
    prisma.jobRoleDefinition.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(jobRole)
      .mockResolvedValueOnce({
        ...jobRole,
        _count: { users: 0, featureAccessRules: 0 },
      });
    prisma.jobRoleDefinition.create.mockResolvedValue(jobRole);
    prisma.jobRoleDefinition.update.mockResolvedValue({
      ...jobRole,
      displayName: 'Updated job role',
    });

    await service.adminCreateJobRole(superAdmin, jobRole);
    await service.adminUpdateJobRole(superAdmin, jobRole.code, {
      displayName: 'Updated job role',
    });
    await service.adminDeleteJobRole(superAdmin, jobRole.code);

    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'personnel-job-role-created',
    );
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'personnel-job-role-updated',
    );
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'personnel-job-role-deleted',
    );
  });

  it('uses legacy codes as display names when startup sync finds blank org labels', async () => {
    const org = installUserScopeTreeMock();
    const legacyRegion = org.saveNode({
      id: 'org-region-legacy-blank',
      code: 'REGION_LEGACY_BLANK',
      businessCode: 'LEGACY_REGION',
      displayName: '',
      type: 'REGION',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 120,
    });
    const legacyArea = org.saveNode({
      id: 'org-area-legacy-blank',
      code: 'AREA_LEGACY_BLANK',
      businessCode: 'LEGACY_AREA',
      displayName: '',
      type: 'AREA',
      parentId: legacyRegion.id,
      isSystem: false,
      isActive: true,
      sortOrder: 210,
    });
    const showroom = org.saveNode({
      id: 'org-store-legacy-blank',
      code: 'STORE_CP77',
      businessCode: 'CP77',
      displayName: 'CP77',
      type: 'SHOWROOM',
      parentId: legacyArea.id,
      isSystem: false,
      isActive: true,
      sortOrder: 10300,
    });

    await expect(
      (service as any).organizationLocationForShowroomNode(prisma, showroom),
    ).resolves.toEqual({
      areaCode: 'LEGACY_AREA',
      regionCode: 'LEGACY_REGION',
    });

    expect(prisma.regionDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'LEGACY_REGION' },
        create: expect.objectContaining({ displayName: 'LEGACY_REGION' }),
        update: expect.objectContaining({ displayName: 'LEGACY_REGION' }),
      }),
    );
    expect(prisma.areaDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'LEGACY_AREA' },
        create: expect.objectContaining({ displayName: 'LEGACY_AREA' }),
        update: expect.objectContaining({ displayName: 'LEGACY_AREA' }),
      }),
    );
  });

  it('generates personnel codes from SR, area, and region scope', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    });
    org.saveNode({
      id: 'org-store-cp62-pos-manager',
      code: 'STORE_CP62_POS_STORE_MANAGER',
      businessCode: 'STORE_MANAGER',
      displayName: 'Quản lý Cửa hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    org.saveNode({
      id: 'org-area-hcm-pos-manager',
      code: 'AREA_HCM_POS_AREA_MANAGER',
      businessCode: 'AREA_MANAGER',
      displayName: 'Quản lý Vùng',
      type: 'JOB_ROLE',
      parentId: 'org-area-hcm',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    org.saveNode({
      id: 'org-region-chatsale-pos-chatsale',
      code: 'REGION_CHATSALE_POS_CHATSALE',
      businessCode: 'CHATSALE',
      displayName: 'Chatsale',
      type: 'JOB_ROLE',
      parentId: 'org-region-chatsale',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'sale@phongvu.vn',
        firstName: 'Sale',
        role: 'STAFF',
        departmentCode: 'SALES',
        jobRoleCode: 'SALE',
        workScopeType: 'STORE',
        organizationNodeId: 'org-store-cp62-pos-sa',
      }),
    ).resolves.toMatchObject({
      personnelCode: 'SA_CP62_HCM_MN',
      areaCode: 'HCM',
      regionCode: 'MIEN_NAM',
      organizationNodeId: 'org-store-cp62-pos-sa',
    });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'manager@phongvu.vn',
        firstName: 'Manager',
        role: 'STAFF',
        departmentCode: 'MANAGEMENT',
        jobRoleCode: 'STORE_MANAGER',
        workScopeType: 'STORE',
        organizationNodeId: 'org-store-cp62-pos-manager',
      }),
    ).resolves.toMatchObject({ personnelCode: 'STORE_MANAGER_CP62_HCM_MN' });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'area@phongvu.vn',
        firstName: 'Area',
        role: 'STAFF',
        departmentCode: 'MANAGEMENT',
        jobRoleCode: 'AREA_MANAGER',
        workScopeType: 'AREA',
        organizationNodeId: 'org-area-hcm-pos-manager',
      }),
    ).resolves.toMatchObject({ personnelCode: 'AREA_MANAGER_HCM_HCM_MN' });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'chat@phongvu.vn',
        firstName: 'Chat',
        role: 'STAFF',
        departmentCode: 'SALES',
        jobRoleCode: 'CHATSALE',
        workScopeType: 'REGION',
        organizationNodeId: 'org-region-chatsale-pos-chatsale',
      }),
    ).resolves.toMatchObject({
      personnelCode: 'CHATSALE_CHATSALE_CHATSALE_CHATSALE',
    });
  });

  it('derives STORE-scope user area and region from the assigned SR', () => {
    const staleRegion = {
      code: 'MIEN_CU',
      displayName: 'Mien cu',
      abbreviation: 'MC',
    };
    const staleArea = {
      code: 'VUNG_CU',
      displayName: 'Vung cu',
      abbreviation: 'VC',
      region: staleRegion,
    };

    const dto = (service as any).toUserDto({
      id: 'user-store',
      email: 'store@phongvu.vn',
      firstName: 'Store',
      lastName: null,
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'SALES',
      jobRoleCode: 'SALE',
      workScopeType: 'STORE',
      areaCode: staleArea.code,
      regionCode: staleRegion.code,
      area: staleArea,
      region: staleRegion,
      store,
    });

    expect(dto).toMatchObject({
      areaCode: 'HCM',
      regionCode: 'MIEN_NAM',
      personnelCode: 'SALE_CP62_HCM_MN',
    });
  });

  it('derives assigned SRs from parent showroom nodes for Lv5 assignments', () => {
    const cp75Store = {
      ...store,
      id: 'store-75',
      storeId: 'CP75',
      storeName: 'CP75',
      organizationNodeId: 'org-store-cp75',
    };
    const dto = (service as any).toUserDto({
      id: 'user-multi-sr',
      email: 'multi@phongvu.vn',
      firstName: 'Multi',
      lastName: null,
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'SALES',
      jobRoleCode: 'CASH',
      workScopeType: 'STORE',
      store,
      organizationAssignments: [
        {
          id: 'assign-cp62',
          organizationNodeId: 'org-store-cp62-pos-cash',
          isPrimary: true,
          organizationNode: {
            id: 'org-store-cp62-pos-cash',
            displayName: 'Thu ngân CP62',
            type: 'LV5_POSITION',
            stores: [],
            parent: {
              id: 'org-store-cp62',
              displayName: 'CP62',
              type: 'LV4_STORE',
              stores: [store],
            },
          },
        },
        {
          id: 'assign-cp75',
          organizationNodeId: 'org-store-cp75-pos-cash',
          isPrimary: false,
          organizationNode: {
            id: 'org-store-cp75-pos-cash',
            displayName: 'Thu ngân CP75',
            type: 'LV5_POSITION',
            stores: [],
            parent: {
              id: 'org-store-cp75',
              displayName: 'CP75',
              type: 'LV4_STORE',
              stores: [cp75Store],
            },
          },
        },
      ],
      userFeatureAssignments: [],
    });

    expect(dto.assignedStores.map((item: any) => item.storeId)).toEqual([
      'CP62',
      'CP75',
    ]);
    expect(dto.organizationAssignments).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          organizationNodeId: 'org-store-cp75-pos-cash',
          storeId: 'CP75',
          storeName: 'CP75',
        }),
      ]),
    );
  });

  it('derives assigned SRs from descendant showroom nodes for region assignments', () => {
    const cp75Store = {
      ...store,
      id: 'store-75',
      storeId: 'CP75',
      storeName: 'CP75',
      organizationNodeId: 'org-store-cp75',
    };
    const dto = (service as any).toUserDto({
      id: 'user-region',
      email: 'region@phongvu.vn',
      firstName: 'Region',
      lastName: null,
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'SALES',
      jobRoleCode: 'REGION_MANAGER',
      workScopeType: 'REGION',
      store: null,
      organizationAssignments: [
        {
          id: 'assign-region',
          organizationNodeId: 'org-region-hcm',
          isPrimary: true,
          organizationNode: {
            id: 'org-region-hcm',
            displayName: 'Miền Nam',
            type: 'REGION',
            stores: [],
            children: [
              {
                id: 'org-store-cp62',
                displayName: 'CP62',
                type: 'STORE',
                stores: [store],
                children: [],
              },
              {
                id: 'org-store-cp75',
                displayName: 'CP75',
                type: 'STORE',
                stores: [cp75Store],
                children: [],
              },
            ],
          },
        },
      ],
      userFeatureAssignments: [],
    });

    expect(dto.assignedStores.map((item: any) => item.storeId)).toEqual([
      'CP62',
      'CP75',
    ]);
    expect(dto.storeId).toBe('CP62');
    expect(dto.organizationAssignments).toEqual([
      expect.objectContaining({
        organizationNodeId: 'org-region-hcm',
        organizationNodeType: 'REGION',
        storeId: 'CP62',
      }),
    ]);
  });

  it('counts region and area users through STORE-scope SR assignments', async () => {
    prisma.user.count.mockResolvedValueOnce(7).mockResolvedValueOnce(4);

    await expect(service.adminListRegions(superAdmin)).resolves.toEqual([
      expect.objectContaining({
        code: region.code,
        _count: expect.objectContaining({ users: 7, areas: 1 }),
      }),
    ]);
    expect(prisma.user.count).toHaveBeenNthCalledWith(1, {
      where: {
        OR: [
          {
            AND: [
              { regionCode: region.code },
              { NOT: { workScopeType: 'STORE' } },
            ],
          },
          {
            AND: [
              { regionCode: region.code },
              { workScopeType: 'STORE' },
              { storeId: null },
            ],
          },
          {
            workScopeType: 'STORE',
            store: { is: { area: { is: { regionCode: region.code } } } },
          },
        ],
      },
    });

    await expect(service.adminListAreas(superAdmin)).resolves.toEqual([
      expect.objectContaining({
        code: area.code,
        _count: expect.objectContaining({ users: 4, stores: 1 }),
      }),
    ]);
    expect(prisma.user.count).toHaveBeenNthCalledWith(2, {
      where: {
        OR: [
          {
            AND: [{ areaCode: area.code }, { NOT: { workScopeType: 'STORE' } }],
          },
          {
            AND: [
              { areaCode: area.code },
              { workScopeType: 'STORE' },
              { storeId: null },
            ],
          },
          { workScopeType: 'STORE', store: { is: { areaCode: area.code } } },
        ],
      },
    });
  });

  it('does not sync STORE-scope users from legacy SR area without an organization node', async () => {
    prisma.user.updateMany.mockResolvedValueOnce({ count: 3 });

    await expect(
      service.adminUpdateStore(superAdmin, 'CP01', {
        areaCode: defaultArea.code,
      }),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      areaCode: defaultArea.code,
      regionCode: defaultArea.regionCode,
    });

    expect(prisma.user.updateMany).not.toHaveBeenCalled();
  });

  it('rejects legacy ONLINE and MULTI_STORE scopes after migration', async () => {
    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'online@phongvu.vn',
        firstName: 'Online',
        role: 'STAFF',
        departmentCode: 'SALES',
        jobRoleCode: 'CHATSALE',
        workScopeType: 'ONLINE',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'multi@phongvu.vn',
        firstName: 'Multi',
        role: 'STAFF',
        departmentCode: 'SALES',
        jobRoleCode: 'SALE',
        workScopeType: 'MULTI_STORE',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('lets super admin and scoped domain admins set user passwords', async () => {
    const targetUser = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      firstName: 'Staff',
      role: 'STAFF',
      status: 'yes',
      storeId: null,
      store: null,
    };
    prisma.user.findUnique.mockResolvedValue(targetUser);

    await expect(
      service.adminSetUserPassword(superAdmin, 'user-1', 'Password2!'),
    ).resolves.toEqual({ ok: true });
    expect(passwordResetService.setPasswordForUserId).toHaveBeenCalledWith(
      'user-1',
      'Password2!',
      { id: 'admin-1', email: 'admin@phongvu.vn' },
    );

    prisma.user.count.mockResolvedValueOnce(1);
    await expect(
      service.adminSetUserPassword(admin, 'user-1', 'Password3!'),
    ).resolves.toEqual({ ok: true });
    expect(passwordResetService.setPasswordForUserId).toHaveBeenCalledWith(
      'user-1',
      'Password3!',
      { id: 'admin-phongvu', email: 'admin@phongvu.vn' },
    );

    await expect(
      service.adminSetUserPassword(manager, 'user-1', 'Password2!'),
    ).rejects.toBeInstanceOf(ForbiddenException);

    prisma.user.findUnique.mockResolvedValueOnce({
      ...targetUser,
      id: 'super-1',
      role: 'SUPER_ADMIN',
    });
    await expect(
      service.adminSetUserPassword(admin, 'super-1', 'Password2!'),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(passwordResetService.setPasswordForUserId).toHaveBeenCalledTimes(2);
  });

  it('hard deletes locked users with no history', async () => {
    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'locked-user',
      email: 'locked@phongvu.vn',
      role: 'USER',
      status: 'no',
    });

    await expect(
      service.adminDeleteUser(superAdmin, 'locked-user'),
    ).resolves.toEqual({
      deleted: true,
      id: 'locked-user',
      email: 'locked@phongvu.vn',
    });

    expect(prisma.userPlatformSession.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'locked-user' },
    });
    expect(prisma.user.delete).toHaveBeenCalledWith({
      where: { id: 'locked-user' },
    });
    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      ['locked-user'],
      'user-access-deleted',
    );
  });

  it('invalidates access when an admin update changes effective scope', async () => {
    const current = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      role: 'USER',
      status: 'yes',
      workScopeType: 'STORE',
      organizationNodeId: 'org-store-cp62',
      organizationAssignments: [],
    };
    const updated = {
      ...current,
      workScopeType: 'NATIONAL',
      organizationNodeId: null,
    };
    jest.spyOn(service as any, 'assertAdmin').mockResolvedValue(undefined);
    jest
      .spyOn(service as any, 'assertAdminCanUpdateUser')
      .mockResolvedValue(undefined);
    jest.spyOn(service as any, 'prepareAdminUserMutation').mockResolvedValue({
      updateData: {
        workScopeType: 'NATIONAL',
        organizationNode: { disconnect: true },
      },
      organizationNodeIds: [],
      role: 'USER',
      workScopeType: 'NATIONAL',
    });
    jest
      .spyOn(service as any, 'syncUserOrganizationAssignments')
      .mockResolvedValue(undefined);
    jest.spyOn(service as any, 'toUserDto').mockImplementation((user) => user);
    prisma.user.findUnique
      .mockResolvedValueOnce(current)
      .mockResolvedValueOnce(updated);
    prisma.user.update.mockResolvedValue(updated);

    await service.adminUpdateUser(superAdmin, 'user-1', {
      workScopeType: 'NATIONAL',
    });

    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      ['user-1'],
      'user-access-updated',
    );
  });

  it('blocks deleting active, super-admin, self, or history-backed users', async () => {
    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'active-user',
      email: 'active@phongvu.vn',
      role: 'USER',
      status: 'yes',
    });
    await expect(
      service.adminDeleteUser(superAdmin, 'active-user'),
    ).rejects.toThrow('đã khóa');

    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'super-2',
      email: 'root@phongvu.vn',
      role: 'SUPER_ADMIN',
      status: 'no',
    });
    await expect(
      service.adminDeleteUser(superAdmin, 'super-2'),
    ).rejects.toThrow('quản trị toàn hệ thống');

    await expect(
      service.adminDeleteUser(superAdmin, superAdmin.id),
    ).rejects.toThrow('tự xóa');

    prisma.user.findUnique.mockResolvedValueOnce({
      id: 'history-user',
      email: 'history@phongvu.vn',
      role: 'USER',
      status: 'no',
    });
    prisma.warranty.count.mockResolvedValueOnce(1);
    await expect(
      service.adminDeleteUser(superAdmin, 'history-user'),
    ).rejects.toThrow('dữ liệu lịch sử');
    expect(prisma.user.delete).not.toHaveBeenCalledWith({
      where: { id: 'history-user' },
    });
  });

  it('blocks branch admin from mutating stores', async () => {
    await expect(
      service.adminCreateStore(admin, {
        storeId: 'CP99',
        storeName: 'Cua hang CP99',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.store.create).not.toHaveBeenCalled();
  });

  it('does not delete stores assigned to users or feature rules', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-1',
      storeId: 'CP99',
      storeName: 'Cua hang CP99',
      _count: { users: 2, featureAccessRules: 0 },
    });

    await expect(
      service.adminDeleteStore(superAdmin, 'CP99'),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.store.delete).not.toHaveBeenCalled();
  });

  it('backfills missing SR organization nodes directly under the root domain when listing the tree', async () => {
    const org = installOrganizationNodeMock();
    prisma.store.findMany.mockResolvedValueOnce([
      {
        ...store,
        organizationNodeId: null,
        _count: { users: 0 },
      },
    ]);

    const nodes = await service.adminListOrganizationTree(superAdmin);

    const storeNode = org.nodesByCode.get('STORE_CP62');
    expect(org.nodesByCode.get('REGION_PHONGVU_MIEN_NAM')).toBeUndefined();
    expect(org.nodesByCode.get('AREA_PHONGVU_HCM')).toBeUndefined();
    expect(storeNode).toMatchObject({
      type: 'LV4_STORE',
      parentId: 'org-domain-phongvu-vn',
    });
    expect(prisma.store.update).toHaveBeenCalledWith({
      where: { id: 'store-62' },
      data: { organizationNodeId: storeNode.id },
    });
    expect(nodes).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: 'STORE_CP62' })]),
    );
    expect(
      ['STORE_MANAGER', 'SA', 'TECHNICIAN', 'CASH', 'WAREHOUSE'].map(
        (code) =>
          Array.from(org.nodesById.values()).find(
            (node) =>
              node.parentId === storeNode.id &&
              node.type === 'LV5_POSITION' &&
              node.businessCode === code,
          )?.displayName,
      ),
    ).toEqual([
      'Quản lý Cửa hàng',
      'Nhân viên Bán hàng',
      'Kỹ thuật viên',
      'Nhân viên Thu ngân',
      'Nhân viên Kho',
    ]);
  });

  it('keeps manually inactive showroom organization nodes inactive during store sync', async () => {
    const org = installOrganizationNodeMock();
    org.saveNode({
      id: 'org-store-cp62',
      code: 'STORE_CP62',
      displayName: 'CP62',
      businessCode: 'CP62',
      type: 'LV4_STORE',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: false,
      sortOrder: 10300,
    });
    prisma.store.findMany.mockResolvedValueOnce([
      {
        ...store,
        organizationNodeId: 'org-store-cp62',
        _count: { users: 0 },
      },
    ]);

    const nodes = await service.adminListOrganizationTree(superAdmin);

    expect(org.nodesById.get('org-store-cp62')).toMatchObject({
      isActive: false,
      parentId: 'org-domain-phongvu-vn',
    });
    expect(nodes).not.toEqual(
      expect.arrayContaining([expect.objectContaining({ code: 'STORE_CP62' })]),
    );
    expect(prisma.organizationNode.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'org-store-cp62' },
        data: expect.objectContaining({ isActive: false }),
      }),
    );
    expect(prisma.user.updateMany).not.toHaveBeenCalled();
  });

  it('cascades inactive organization status to descendant nodes', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    });

    await expect(
      service.adminUpdateOrganizationNode(superAdmin, 'org-area-hcm', {
        displayName: 'Ho Chi Minh',
        code: 'AREA_PHONGVU_HCM',
        businessCode: area.code,
        type: 'AREA',
        parentId: 'org-region-mien-nam',
        isActive: false,
        sortOrder: 200,
      }),
    ).resolves.toMatchObject({
      id: 'org-area-hcm',
      isActive: false,
    });

    expect(org.nodesById.get('org-area-hcm')).toMatchObject({
      isActive: false,
    });
    expect(org.nodesById.get('org-store-cp62')).toMatchObject({
      isActive: false,
    });
    expect(org.nodesById.get('org-store-cp01')).toMatchObject({
      isActive: false,
    });
    expect(org.nodesById.get('org-store-cp62-pos-sa')).toMatchObject({
      isActive: false,
    });
    expect(prisma.organizationNode.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: expect.objectContaining({
            in: expect.arrayContaining([
              'org-store-cp62',
              'org-store-cp01',
              'org-store-cp62-pos-sa',
            ]),
          }),
          isActive: true,
        }),
        data: { isActive: false },
      }),
    );
    expect(prisma.areaDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: area.code },
        update: expect.objectContaining({ isActive: false }),
      }),
    );
    expect(prisma.jobRoleDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'SA' },
        update: expect.objectContaining({ isActive: false }),
      }),
    );
  });

  it('does not reactivate inactive default root domains during seed', async () => {
    const org = installOrganizationNodeMock();
    org.saveNode({
      id: 'org-domain-phongvu-vn',
      code: 'DOMAIN_PHONGVU_VN',
      displayName: 'phongvu.vn',
      type: 'ROOT_DOMAIN',
      parentId: null,
      emailDomain: 'phongvu.vn',
      isSystem: true,
      isActive: false,
      sortOrder: 10,
    });

    await (service as any).seedDefaultOrganizationTree();

    expect(org.nodesById.get('org-domain-phongvu-vn')).toMatchObject({
      isActive: false,
    });
  });

  it('does not reactivate inactive default store position nodes during store sync', async () => {
    const org = installOrganizationNodeMock();
    const storeNode = org.saveNode({
      id: 'org-store-cp62',
      code: 'STORE_CP62',
      displayName: 'CP62',
      businessCode: 'CP62',
      type: 'LV4_STORE',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 10300,
    });
    org.saveNode({
      id: 'org-store-cp62-pos-cash',
      code: 'STORE_CP62_POS_CASH',
      businessCode: 'CASH',
      displayName: 'Nhân viên Thu ngân',
      type: 'LV5_POSITION',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: false,
      sortOrder: 40,
    });

    await (service as any).ensureDefaultStorePositionNodes(prisma, storeNode);

    expect(org.nodesById.get('org-store-cp62-pos-cash')).toMatchObject({
      isActive: false,
    });
    expect(prisma.jobRoleDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'CASH' },
        update: expect.objectContaining({ isActive: false }),
      }),
    );
  });

  it('keeps the selected Lv5 position as the user organization node', async () => {
    const org = installUserScopeTreeMock();
    const positionNode = org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'sa@phongvu.vn',
        firstName: 'Sale',
        role: 'USER',
        organizationNodeId: positionNode.id,
      }),
    ).resolves.toMatchObject({
      departmentCode: 'SALES',
      jobRoleCode: 'SA',
      storeId: 'CP62',
      organizationNodeId: positionNode.id,
      personnelCode: 'SA_CP62_HCM_MN',
    });

    expect(prisma.user.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          store: { connect: { id: 'store-62' } },
          department: { connect: { code: 'SALES' } },
          jobRole: { connect: { code: 'SA' } },
          organizationNode: { connect: { id: positionNode.id } },
        }),
      }),
    );
  });

  it('keeps the linked showroom organization node in place when legacy SR area changes', async () => {
    const org = installOrganizationNodeMock();
    org.saveNode({
      id: 'org-store-cp01',
      code: 'STORE_CP01',
      displayName: 'CP01',
      type: 'SHOWROOM',
      parentId: 'org-area-old',
      isSystem: false,
      isActive: true,
      sortOrder: 10300,
    });
    prisma.store.findUnique.mockResolvedValueOnce({
      id: 'store-1',
      storeId: 'CP01',
      storeName: 'CP01',
      areaCode: area.code,
      area,
      organizationNodeId: 'org-store-cp01',
      _count: { users: 1 },
    });

    await expect(
      service.adminUpdateStore(superAdmin, 'CP01', {
        areaCode: defaultArea.code,
      }),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      areaCode: defaultArea.code,
      organizationNodeId: 'org-store-cp01',
    });

    const storeNode = org.nodesById.get('org-store-cp01');
    expect(storeNode.parentId).toBe('org-area-old');
    expect(prisma.organizationNode.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'org-store-cp01' },
        data: expect.objectContaining({
          code: 'STORE_CP01',
          type: 'LV4_STORE',
          parentId: 'org-area-old',
        }),
      }),
    );
    const storeSubtreeIds = Array.from(org.nodesById.values())
      .filter(
        (node) =>
          node.id === 'org-store-cp01' || node.parentId === 'org-store-cp01',
      )
      .map((node) => node.id);
    expect(storeSubtreeIds).toEqual(
      expect.arrayContaining([
        'org-store-cp01',
        'org-store-cp01-pos-sa',
        'org-store-cp01-pos-cash',
        'org-store-cp01-pos-warehouse',
      ]),
    );
    expect(prisma.user.updateMany).toHaveBeenCalledWith({
      where: {
        storeId: 'store-1',
        workScopeType: 'STORE',
        OR: [
          { organizationNodeId: null },
          { organizationNodeId: { notIn: storeSubtreeIds } },
        ],
      },
      data: {
        organizationNodeId: 'org-store-cp01-pos-cash',
        jobRoleCode: 'CASH',
        areaCode: null,
        regionCode: null,
      },
    });
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'store-organization-updated',
    );
  });

  it('invalidates access when store organization sync creates a missing topology', async () => {
    installOrganizationNodeMock();
    prisma.store.findMany.mockResolvedValueOnce([
      {
        id: 'store-99',
        storeId: 'CP99',
        storeName: 'CP99',
        areaCode: defaultArea.code,
        area: defaultArea,
        organizationNodeId: null,
      },
    ]);

    await (service as any).syncStoreOrganizationNodes('test-sync');

    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'store-organization-sync-updated',
    );
  });

  it('invalidates access after deleting an unused store', async () => {
    prisma.store.findUnique.mockResolvedValueOnce({
      id: 'store-99',
      storeId: 'CP99',
      _count: { users: 0, featureAccessRules: 0 },
    });

    await expect(service.adminDeleteStore(superAdmin, 'CP99')).resolves.toEqual(
      { deleted: true, storeId: 'CP99' },
    );

    expect(prisma.store.delete).toHaveBeenCalledWith({
      where: { storeId: 'CP99' },
    });
    expect(accessChangeService.publishForAllUsers).toHaveBeenCalledWith(
      'store-organization-deleted',
    );
  });

  it('imports passwordless users and upserts existing users from tree-code Excel rows', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    prisma.store.findMany.mockResolvedValue([]);
    const existing = {
      id: 'existing-user',
      email: 'old@phongvu.vn',
      password: 'already-hashed',
      firstName: 'Old',
      lastName: 'Name',
      role: 'USER',
      status: 'no',
      workScopeType: 'STORE',
      storeId: 'store-62',
      store,
      jobRoleCode: 'SA',
      organizationNodeId: 'org-store-cp62-pos-sa',
      organizationNode: {
        id: 'org-store-cp62-pos-sa',
        displayName: 'Nhân viên Bán hàng',
      },
      userFeatureAssignments: [],
    };
    const savedNew = {
      id: 'new-user',
      email: 'new@phongvu.vn',
      firstName: 'New User',
      lastName: null,
      role: 'USER',
      status: 'yes',
      workScopeType: 'STORE',
      storeId: 'store-62',
      store,
      jobRoleCode: 'SA',
      organizationNodeId: 'org-store-cp62-pos-sa',
      organizationNode: existing.organizationNode,
      userFeatureAssignments: [],
    };
    const savedOld = { ...existing, firstName: 'Old Updated', lastName: null };
    prisma.user.findMany
      .mockResolvedValueOnce([existing])
      .mockResolvedValueOnce([savedNew, savedOld]);
    prisma.user.update.mockResolvedValue(savedOld);

    const result = await service.adminImportUsers(superAdmin, {
      totalRows: 2,
      skippedRows: 0,
      rows: [
        {
          rowNumber: 2,
          email: 'new@phongvu.vn',
          fullName: 'New User',
          role: 'USER',
          levelCodes: ['DOMAIN_PHONGVU_VN', '', '', '', 'CP62', 'SA'],
        },
        {
          rowNumber: 3,
          email: 'old@phongvu.vn',
          fullName: 'Old Updated',
          role: 'USER',
          levelCodes: ['DOMAIN_PHONGVU_VN', '', '', '', 'STORE_CP62', 'SA'],
        },
      ],
    });

    expect(result).toMatchObject({
      totalRows: 2,
      createdRows: 1,
      updatedRows: 1,
      skippedRows: 0,
      welcomeEmailSentRows: 1,
      welcomeEmailFailedRows: 0,
    });
    expect(result.results).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          email: 'new@phongvu.vn',
          action: 'created',
          organizationNodeId: 'org-store-cp62-pos-sa',
          personnelCode: 'SA_CP62_HCM_MN',
        }),
        expect.objectContaining({
          email: 'old@phongvu.vn',
          action: 'updated',
          personnelCode: 'SA_CP62_HCM_MN',
        }),
      ]),
    );
    expect(prisma.user.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          email: 'new@phongvu.vn',
          password: '',
          firstName: 'New User',
          organizationNode: { connect: { id: 'org-store-cp62-pos-sa' } },
        }),
      }),
    );
    const updateCall = prisma.user.update.mock.calls[0][0];
    expect(updateCall).toEqual(
      expect.objectContaining({
        where: { id: 'existing-user' },
        data: expect.not.objectContaining({ password: expect.anything() }),
      }),
    );
    expect(updateCall.data).toEqual(expect.objectContaining({ status: 'no' }));
    expect(mailService.sendMail).toHaveBeenCalledTimes(1);
    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      ['existing-user'],
      'user-access-import-updated',
    );
    expect(mailService.sendMail).toHaveBeenCalledWith(
      expect.objectContaining({
        to: 'new@phongvu.vn',
        subject: 'Chào mừng bạn đến với PhongVu OpsHub',
        text: expect.stringContaining(
          'Tài khoản PhongVu OpsHub của bạn đã được tạo.',
        ),
      }),
    );
    const welcomeEmailText = mailService.sendMail.mock.calls[0][0].text;
    expect(welcomeEmailText).toContain(
      'Windows và Android tải tại: https://opshub.hoanghochoi.com/download',
    );
    expect(welcomeEmailText).toContain(
      'iOS: Mở trang https://opshub.hoanghochoi.com bằng trình duyệt Safari -> Share -> Add to Home Screen',
    );
  });

  it('rejects imports outside AUTH_ALLOWED_EMAIL_DOMAINS before writing users', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    prisma.store.findMany.mockResolvedValue([]);
    prisma.user.findMany.mockResolvedValue([]);
    policyService.getAllowedEmailDomains.mockResolvedValueOnce(['phongvu.vn']);

    await expect(
      service.adminImportUsers(superAdmin, {
        totalRows: 1,
        skippedRows: 0,
        rows: [
          {
            rowNumber: 2,
            email: 'staff@blocked.vn',
            fullName: 'Staff',
            role: 'USER',
            levelCodes: ['DOMAIN_PHONGVU_VN', '', '', '', 'CP62', 'SA'],
          },
        ],
      }),
    ).rejects.toThrow('Chỉ chấp nhận email');
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('rejects ambiguous import node codes before writing users', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-sa-1',
      code: 'STORE_CP62_POS_SA_1',
      businessCode: 'SA',
      displayName: 'SA 1',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    org.saveNode({
      id: 'org-store-cp62-pos-sa-2',
      code: 'STORE_CP62_POS_SA_2',
      businessCode: 'SA',
      displayName: 'SA 2',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 11,
    });
    prisma.store.findMany.mockResolvedValue([]);
    prisma.user.findMany.mockResolvedValue([]);

    await expect(
      service.adminImportUsers(superAdmin, {
        totalRows: 1,
        skippedRows: 0,
        rows: [
          {
            rowNumber: 2,
            email: 'staff@phongvu.vn',
            fullName: 'Staff',
            role: 'USER',
            levelCodes: ['DOMAIN_PHONGVU_VN', '', '', '', 'CP62', 'SA'],
          },
        ],
      }),
    ).rejects.toThrow('mơ hồ');
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('blocks non-super admins from importing users', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-store-cp62-pos-sa',
      code: 'STORE_CP62_POS_SA',
      businessCode: 'SA',
      displayName: 'Nhân viên Bán hàng',
      type: 'JOB_ROLE',
      parentId: 'org-store-cp62',
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    prisma.store.findMany.mockResolvedValue([]);
    prisma.user.findMany.mockResolvedValue([]);

    await expect(
      service.adminImportUsers(adminAcare, {
        totalRows: 1,
        skippedRows: 0,
        rows: [
          {
            rowNumber: 2,
            email: 'staff@phongvu.vn',
            fullName: 'Staff',
            role: 'USER',
            levelCodes: ['DOMAIN_PHONGVU_VN', '', '', '', 'CP62', 'SA'],
          },
        ],
      }),
    ).rejects.toThrow('Bạn không có quyền thêm người dùng');
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('allows showroom organization nodes directly under a root domain', async () => {
    const org = installOrganizationNodeMock();
    org.saveNode({
      id: 'org-domain-phongvu-vn',
      code: 'DOMAIN_PHONGVU_VN',
      displayName: 'phongvu.vn',
      type: 'ROOT_DOMAIN',
      parentId: null,
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    });
    const showroom = org.saveNode({
      id: 'org-store-cp88',
      code: 'STORE_CP88',
      businessCode: 'CP88',
      displayName: 'CP88',
      type: 'SHOWROOM',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 10300,
    });

    await expect(
      (service as any).resolveOrganizationParentId(
        'SHOWROOM',
        'org-domain-phongvu-vn',
      ),
    ).resolves.toBe('org-domain-phongvu-vn');
    await expect(
      (service as any).organizationLocationForShowroomNode(prisma, showroom),
    ).resolves.toEqual({ areaCode: null, regionCode: null });
  });

  it('seeds root domains without recreating the legacy phongvu.vn subdomain', async () => {
    prisma.organizationNode = {
      upsert: jest.fn(async ({ where, create }: any) => ({
        id:
          where.code === 'DOMAIN_PHONGVU_VN'
            ? 'org-domain-phongvu-vn'
            : create.id,
        code: where.code,
      })),
    };

    await (service as any).seedDefaultOrganizationTree();

    expect(prisma.organizationNode.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'DOMAIN_PHONGVU_VN' },
        create: expect.objectContaining({
          id: 'org-domain-phongvu-vn',
          type: 'LV0_DOMAIN',
          emailDomain: 'phongvu.vn',
        }),
      }),
    );
    expect(prisma.organizationNode.upsert).not.toHaveBeenCalledWith(
      expect.objectContaining({ where: { code: 'SUBDOMAIN_PHONGVU_VN' } }),
    );
  });
});
