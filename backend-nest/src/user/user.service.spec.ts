import { BadRequestException, ForbiddenException } from '@nestjs/common';
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
    email: 'admin@acaretek.vn',
    role: 'ADMIN_ACARE',
    workScopeType: 'NATIONAL',
  };
  const manager = { role: 'MANAGER', storeId: 'store-1' };
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
  };

  beforeEach(() => {
    prisma = {
      $transaction: jest.fn(async (handler: any) => handler(prisma)),
      store: {
        findMany: jest.fn(),
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.storeId === 'CP62' || where.id === 'store-62') return store;
          if (where.storeId === 'CP01' || where.id === 'store-1') {
            return {
              id: 'store-1',
              storeId: 'CP01',
              storeName: 'CP01',
              areaCode: area.code,
              area,
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
      user: {
        findUnique: jest.fn(),
        findMany: jest.fn(async () => []),
        count: jest.fn(async () => 0),
        create: jest.fn(async ({ data }: any) => ({
          id: `user-${data.jobRoleCode}`,
          email: data.email,
          firstName: data.firstName,
          lastName: data.lastName,
          role: data.role,
          status: data.status,
          departmentCode: data.departmentCode,
          jobRoleCode: data.jobRoleCode,
          workScopeType: data.workScopeType,
          storeId: data.storeId,
          regionCode: data.regionCode,
          areaCode: data.areaCode,
          store: data.storeId ? store : null,
          region:
            data.regionCode === chatsaleRegion.code ? chatsaleRegion : null,
          area: data.areaCode === area.code ? area : null,
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
      nodesById.set(node.id, node);
      nodesByCode.set(node.code, node);
      return node;
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
      findUnique: jest.fn(async ({ where }: any) => {
        if (where.id) return nodesById.get(where.id) ?? null;
        if (where.code) return nodesByCode.get(where.code) ?? null;
        return null;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const current = where.id
          ? nodesById.get(where.id)
          : nodesByCode.get(where.code);
        if (!current) return null;
        nodesByCode.delete(current.code);
        return saveNode({ ...current, ...data, id: current.id });
      }),
      findMany: jest.fn(async () =>
        Array.from(nodesById.values()).map((node) => ({
          ...node,
          _count: {
            children: 0,
            users: 0,
            stores: node.type === 'SHOWROOM' ? 1 : 0,
            departments: 0,
            jobRoles: 0,
            regions: node.type === 'REGION' ? 1 : 0,
            areas: node.type === 'AREA' ? 1 : 0,
          },
        })),
      ),
      delete: jest.fn(),
    };

    return { nodesByCode, nodesById, saveNode };
  }
  it('normalizes legacy ADMIN role input to ADMIN_PHONGVU', () => {
    expect((service as any).normalizeRoleCode('ADMIN', true)).toBe(
      'ADMIN_PHONGVU',
    );
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

  it('scopes ADMIN_ACARE user management to the acaretek.vn email domain', async () => {
    prisma.user.findMany.mockResolvedValueOnce([
      {
        id: 'acare-user',
        email: 'staff@acaretek.vn',
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
      expect.objectContaining({ email: 'staff@acaretek.vn' }),
    ]);
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([
            {
              email: {
                endsWith: '@acaretek.vn',
                mode: 'insensitive',
              },
            },
          ]),
        }),
      }),
    );

    await expect(
      service.adminCreateUser(adminAcare, {
        email: 'new@acaretek.vn',
        firstName: 'New',
        role: 'STAFF',
      }),
    ).resolves.toMatchObject({ email: 'new@acaretek.vn', role: 'STAFF' });

    await expect(
      service.adminCreateUser(adminAcare, {
        email: 'staff@phongvu.vn',
        firstName: 'Wrong Domain',
        role: 'STAFF',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('blocks ADMIN_ACARE from updating users outside acaretek.vn', async () => {
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
  it('generates personnel codes from SR, area, and region scope', async () => {
    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'sale@phongvu.vn',
        firstName: 'Sale',
        role: 'STAFF',
        storeId: 'CP62',
        departmentCode: 'SALES',
        jobRoleCode: 'SALE',
        workScopeType: 'STORE',
      }),
    ).resolves.toMatchObject({
      personnelCode: 'SALE_CP62_HCM_MN',
      areaCode: 'HCM',
      regionCode: 'MIEN_NAM',
    });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'manager@phongvu.vn',
        firstName: 'Manager',
        role: 'STAFF',
        storeId: 'CP62',
        departmentCode: 'MANAGEMENT',
        jobRoleCode: 'STORE_MANAGER',
        workScopeType: 'STORE',
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
        areaCode: 'HCM',
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
        regionCode: 'CHATSALE',
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
      type: 'SHOWROOM',
      parentId: 'org-domain-phongvu-vn',
    });
    expect(prisma.store.update).toHaveBeenCalledWith({
      where: { id: 'store-62' },
      data: { organizationNodeId: storeNode.id },
    });
    expect(nodes).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: 'STORE_CP62' })]),
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
          type: 'SHOWROOM',
          parentId: 'org-area-old',
        }),
      }),
    );
    expect(prisma.user.updateMany).toHaveBeenCalledWith({
      where: { storeId: 'store-1', workScopeType: 'STORE' },
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
          type: 'ROOT_DOMAIN',
          emailDomain: 'phongvu.vn',
        }),
      }),
    );
    expect(prisma.organizationNode.upsert).not.toHaveBeenCalledWith(
      expect.objectContaining({ where: { code: 'SUBDOMAIN_PHONGVU_VN' } }),
    );
  });
});
