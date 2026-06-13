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
        findUnique: jest.fn(async ({ where }: any) => ({
          code: where.code,
          isActive: true,
        })),
      },
      jobRoleDefinition: {
        upsert: jest.fn(),
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
        updateMany: jest.fn(async () => ({ count: 0 })),
      },
    };
    passwordResetService = {
      setPasswordForUserId: jest.fn().mockResolvedValue({ ok: true }),
    };
    process.env.JWT_SECRET = 'test-secret';
    policyService = {
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
    service = new UserService(
      prisma,
      {} as any,
      passwordResetService as any,
      policyService,
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
            if (where.parentId !== undefined && node.parentId !== where.parentId) {
              return false;
            }
            if (where.type !== undefined && node.type !== canonicalType(where.type)) {
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
            (node) => activeValue === undefined || node.isActive === activeValue,
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
      id: 'org-domain-acaretek-vn',
      code: 'DOMAIN_ACARETEK_VN',
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
      parentId: 'org-domain-acaretek-vn',
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
    ).resolves.toMatchObject({ email: 'new@acare.vn', role: 'USER' });

    await expect(
      service.adminCreateUser(adminAcare, {
        email: 'staff@phongvu.vn',
        firstName: 'Wrong Domain',
        role: 'STAFF',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
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

  it('lets ADMIN_PHONGVU assign the Phong Vu root but not the A Care root', async () => {
    installUserScopeTreeMock();

    await expect(
      service.adminCreateUser(admin, {
        email: 'national@phongvu.vn',
        firstName: 'National',
        role: 'STAFF',
        workScopeType: 'NATIONAL',
        organizationNodeId: 'org-domain-phongvu-vn',
      }),
    ).resolves.toMatchObject({
      email: 'national@phongvu.vn',
      workScopeType: 'NATIONAL',
      organizationNodeId: 'org-domain-phongvu-vn',
    });

    await expect(
      service.adminCreateUser(admin, {
        email: 'wrong-root@phongvu.vn',
        firstName: 'Wrong Root',
        role: 'STAFF',
        workScopeType: 'NATIONAL',
        organizationNodeId: 'org-domain-acaretek-vn',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('lets ADMIN_ACARE assign the A Care root but not the Phong Vu root', async () => {
    installUserScopeTreeMock();

    await expect(
      service.adminCreateUser(adminAcare, {
        email: 'national@acare.vn',
        firstName: 'National',
        role: 'STAFF',
        workScopeType: 'NATIONAL',
        organizationNodeId: 'org-domain-acaretek-vn',
      }),
    ).resolves.toMatchObject({
      email: 'national@acare.vn',
      workScopeType: 'NATIONAL',
      organizationNodeId: 'org-domain-acaretek-vn',
    });

    await expect(
      service.adminCreateUser(adminAcare, {
        email: 'wrong-root@acare.vn',
        firstName: 'Wrong Root',
        role: 'STAFF',
        workScopeType: 'NATIONAL',
        organizationNodeId: 'org-domain-phongvu-vn',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
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

  it('saves user feature assignments from featureTreeCodes with ancestors', async () => {
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

    expect(prisma.userFeatureAssignment.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-NO_ROLE' },
    });
    expect(prisma.userFeatureAssignment.createMany).toHaveBeenCalledWith({
      data: expect.arrayContaining([
        expect.objectContaining({ featureCode: 'FIFO' }),
        expect.objectContaining({ featureCode: 'FIFO_IMPORT' }),
        expect.objectContaining({ featureCode: 'ADMIN' }),
        expect.objectContaining({ featureCode: 'ADMIN_USERS' }),
      ]),
      skipDuplicates: true,
    });
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
      expect.arrayContaining(['org-domain-acaretek-vn', 'org-store-ac001']),
    );
    expect(nodes.map((node: any) => node.id)).not.toEqual(
      expect.arrayContaining(['org-domain-phongvu-vn', 'org-store-cp62']),
    );
  });

  it('creates a region under a block organization node', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-block-sales',
      code: 'BLOCK_KINH_DOANH',
      businessCode: 'KINH_DOANH',
      displayName: 'Kinh Doanh',
      type: 'BLOCK',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 50,
    });

    await expect(
      service.adminCreateOrganizationNode(superAdmin, {
        displayName: 'Hồ Chí Minh - Bình Dương',
        code: 'HCM-BD',
        businessCode: 'HCM-BD',
        type: 'REGION',
        parentId: 'org-block-sales',
        isActive: true,
        sortOrder: 0,
      }),
    ).resolves.toMatchObject({
      code: 'HCM_BD',
      businessCode: 'HCM-BD',
      type: 'LV2_REGION',
      parentId: 'org-block-sales',
    });

    expect(prisma.regionDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'HCM_BD' },
        create: expect.objectContaining({
          code: 'HCM_BD',
          organizationNodeId: 'org-hcm-bd',
        }),
      }),
    );
  });

  it('retires self-service store selection', async () => {
    await expect(
      service.selectStoreOnce('user-1', 'CP62'),
    ).rejects.toBeInstanceOf(GoneException);
  });

  it('normalizes legacy region code when moving a showroom under a tree area', async () => {
    const org = installUserScopeTreeMock();
    org.saveNode({
      id: 'org-region-hcm-bd',
      code: 'HCM_BD',
      businessCode: 'HCM-BD',
      displayName: 'Ho Chi Minh - Binh Duong',
      type: 'REGION',
      parentId: 'org-domain-phongvu-vn',
      isSystem: false,
      isActive: true,
      sortOrder: 100,
    });
    org.saveNode({
      id: 'org-area-hcm1',
      code: 'HCM1',
      businessCode: 'HCM1',
      displayName: 'Ho Chi Minh 1',
      type: 'AREA',
      parentId: 'org-region-hcm-bd',
      isSystem: false,
      isActive: true,
      sortOrder: 200,
    });

    await expect(
      service.adminUpdateOrganizationNode(superAdmin, 'org-store-cp62', {
        displayName: 'CP62',
        code: 'STORE_CP62',
        businessCode: 'CP62',
        storeId: 'CP62',
        type: 'LV4_STORE',
        parentId: 'org-area-hcm1',
        isActive: true,
        sortOrder: 300,
      }),
    ).resolves.toMatchObject({
      id: 'org-store-cp62',
      parentId: 'org-area-hcm1',
      type: 'LV4_STORE',
    });

    expect(prisma.store.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'store-62' },
        data: expect.objectContaining({
          areaCode: 'HCM1',
          organizationNodeId: 'org-store-cp62',
        }),
      }),
    );
    const storeSubtreeIds = Array.from(org.nodesById.values())
      .filter(
        (node) => node.id === 'org-store-cp62' || node.parentId === 'org-store-cp62',
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
    expect(prisma.user.updateMany).toHaveBeenCalledWith({
      where: {
        storeId: expect.any(String),
        workScopeType: 'STORE',
        OR: [
          { organizationNodeId: null },
          { organizationNodeId: { notIn: storeSubtreeIds } },
        ],
      },
      data: {
        organizationNodeId: 'org-store-cp62',
        areaCode: 'HCM1',
        regionCode: 'HCM_BD',
      },
    });
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
        featureTreeCodes: [],
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
        (node) => node.id === 'org-store-cp01' || node.parentId === 'org-store-cp01',
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
        organizationNodeId: 'org-store-cp01',
        areaCode: null,
        regionCode: null,
      },
    });
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
