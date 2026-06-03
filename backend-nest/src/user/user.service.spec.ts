import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { UserService } from './user.service';

describe('UserService admin store management', () => {
  let service: UserService;
  let prisma: any;
  let passwordResetService: { setPasswordForUserId: jest.Mock };

  const superAdmin = { role: 'SUPER_ADMIN' };
  const admin = { role: 'ADMIN' };
  const manager = { role: 'MANAGER', storeId: 'store-1' };

  beforeEach(() => {
    prisma = {
      store: {
        findMany: jest.fn(),
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        delete: jest.fn(),
      },
      roleDefinition: {
        upsert: jest.fn(),
        findUnique: jest.fn(),
      },
      departmentDefinition: {
        upsert: jest.fn(),
        findUnique: jest.fn(),
      },
      jobRoleDefinition: {
        upsert: jest.fn(),
        findUnique: jest.fn(),
      },
      user: {
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
    };
    passwordResetService = {
      setPasswordForUserId: jest.fn().mockResolvedValue({
        ok: true,
      }),
    };
    process.env.JWT_SECRET = 'test-secret';
    service = new UserService(prisma, {} as any, passwordResetService as any);
  });

  it('creates a store with normalized payment fields for super admin', async () => {
    prisma.store.findUnique.mockResolvedValue(null);
    prisma.store.create.mockImplementation(async ({ data }: any) => ({
      id: 'store-1',
      ...data,
      _count: { users: 0 },
    }));

    await expect(
      service.adminCreateStore(superAdmin, {
        storeId: ' cp99 ',
        storeName: '  Cửa hàng CP99 ',
        transferAccountNumber: ' 123456 ',
        transferAccountName: ' Phong Vu CP99 ',
        transferBankName: ' VietinBank ',
        transferBankBin: ' 970415 ',
        mapVietinUsername: ' map-user ',
        mapVietinPassword: ' map-pass ',
      }),
    ).resolves.toMatchObject({
      storeId: 'CP99',
      storeName: 'Cửa hàng CP99',
      transferAccountNumber: '123456',
      transferBankBin: '970415',
      mapVietinUsername: 'map-user',
      hasMapVietinPassword: true,
      userCount: 0,
    });

    expect(prisma.store.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          storeId: 'CP99',
          storeName: 'Cửa hàng CP99',
          mapVietinUsername: 'map-user',
          mapVietinPasswordCipher: expect.stringMatching(/^v1:/),
        }),
      }),
    );
  });

  it('lets a manager update only their own store MAP credentials', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-1',
      storeId: 'CP01',
      storeName: 'CP01',
      mapVietinPasswordCipher: 'old-cipher',
    });
    prisma.store.update.mockImplementation(async ({ data }: any) => ({
      id: 'store-1',
      storeId: 'CP01',
      storeName: 'CP01',
      ...data,
      _count: { users: 1 },
    }));

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
      store: { storeId: 'CP01', storeName: 'CP01' },
    });
    prisma.roleDefinition.findUnique.mockResolvedValue({ code: 'MANAGER' });

    await expect(
      service.adminUpdateUser(manager, 'user-1', { role: 'MANAGER' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('returns predictable personnel codes by job role and work scope', async () => {
    const store = { id: 'store-62', storeId: 'CP62', storeName: 'CP62' };
    prisma.store.findUnique.mockResolvedValue(store);
    prisma.roleDefinition.findUnique.mockResolvedValue({ code: 'STAFF' });
    prisma.departmentDefinition.findUnique.mockImplementation(
      async ({ where }: any) => ({ code: where.code }),
    );
    prisma.jobRoleDefinition.findUnique.mockImplementation(
      async ({ where }: any) => ({ code: where.code }),
    );
    prisma.user.create.mockImplementation(async ({ data }: any) => ({
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
      store: data.storeId ? store : null,
    }));

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
    ).resolves.toMatchObject({ personnelCode: 'SALE_CP62' });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'manager@phongvu.vn',
        firstName: 'Manager',
        role: 'STAFF',
        storeId: 'CP62',
        departmentCode: 'MANAGEMENT',
        jobRoleCode: 'MANAGER',
        workScopeType: 'STORE',
      }),
    ).resolves.toMatchObject({ personnelCode: 'MANAGER_CP62' });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'warehouse@phongvu.vn',
        firstName: 'Warehouse',
        role: 'STAFF',
        storeId: 'CP62',
        departmentCode: 'WAREHOUSE',
        jobRoleCode: 'WAREHOUSE',
        workScopeType: 'STORE',
      }),
    ).resolves.toMatchObject({ personnelCode: 'WAREHOUSE_CP62' });

    await expect(
      service.adminCreateUser(superAdmin, {
        email: 'online@phongvu.vn',
        firstName: 'Online',
        role: 'STAFF',
        departmentCode: 'SALES',
        jobRoleCode: 'SALE_ONLINE',
        workScopeType: 'ONLINE',
      }),
    ).resolves.toMatchObject({ personnelCode: 'SALE_ONLINE' });
  });

  it('lets only super admin set a user password directly', async () => {
    await expect(
      service.adminSetUserPassword(
        { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
        'user-1',
        'Password2!',
      ),
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
        storeName: 'Cửa hàng CP99',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.store.create).not.toHaveBeenCalled();
  });

  it('does not delete stores assigned to users', async () => {
    prisma.store.findUnique.mockResolvedValue({
      id: 'store-1',
      storeId: 'CP99',
      storeName: 'Cửa hàng CP99',
      _count: { users: 2 },
    });

    await expect(
      service.adminDeleteStore(superAdmin, 'CP99'),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.store.delete).not.toHaveBeenCalled();
  });
});
