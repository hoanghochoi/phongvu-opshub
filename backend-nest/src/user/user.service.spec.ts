import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { UserService } from './user.service';

describe('UserService admin store management', () => {
  let service: UserService;
  let prisma: any;
  let passwordResetService: { setPasswordForUserId: jest.Mock };

  const superAdmin = { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' };
  const admin = { role: 'ADMIN' };
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
            return { id: 'store-1', storeId: 'CP01', storeName: 'CP01', areaCode: area.code, area };
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
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code, isActive: true })),
      },
      departmentDefinition: {
        upsert: jest.fn(),
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code, isActive: true })),
      },
      jobRoleDefinition: {
        upsert: jest.fn(),
        findUnique: jest.fn(async ({ where }: any) => ({ code: where.code, isActive: true })),
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
            return { ...chatsaleRegion, regionCode: chatsaleRegion.code, region: chatsaleRegion };
          }
          return null;
        }),
      },
      user: {
        findUnique: jest.fn(),
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
          region: data.regionCode === chatsaleRegion.code ? chatsaleRegion : null,
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
    service = new UserService(prisma, {} as any, passwordResetService as any);
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
    ).resolves.toMatchObject({ personnelCode: 'CHATSALE_CHATSALE_CHATSALE_CHATSALE' });
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
          { AND: [{ regionCode: region.code }, { NOT: { workScopeType: 'STORE' } }] },
          { AND: [{ regionCode: region.code }, { workScopeType: 'STORE' }, { storeId: null }] },
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
          { AND: [{ areaCode: area.code }, { NOT: { workScopeType: 'STORE' } }] },
          { AND: [{ areaCode: area.code }, { workScopeType: 'STORE' }, { storeId: null }] },
          { workScopeType: 'STORE', store: { is: { areaCode: area.code } } },
        ],
      },
    });
  });

  it('syncs existing STORE-scope users when an SR moves to another area', async () => {
    prisma.user.updateMany.mockResolvedValueOnce({ count: 3 });

    await expect(
      service.adminUpdateStore(superAdmin, 'CP01', { areaCode: defaultArea.code }),
    ).resolves.toMatchObject({
      storeId: 'CP01',
      areaCode: defaultArea.code,
      regionCode: defaultArea.regionCode,
    });

    expect(prisma.user.updateMany).toHaveBeenCalledWith({
      where: { storeId: 'store-1', workScopeType: 'STORE' },
      data: { areaCode: defaultArea.code, regionCode: defaultArea.regionCode },
    });
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

  it('lets only super admin set a user password directly', async () => {
    await expect(
      service.adminSetUserPassword(superAdmin, 'user-1', 'Password2!'),
    ).resolves.toEqual({ ok: true });
    expect(passwordResetService.setPasswordForUserId).toHaveBeenCalledWith(
      'user-1',
      'Password2!',
      { id: 'admin-1', email: 'admin@phongvu.vn' },
    );

    await expect(
      service.adminSetUserPassword(manager, 'user-1', 'Password2!'),
    ).rejects.toBeInstanceOf(ForbiddenException);
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
});
