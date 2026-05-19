import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { UserService } from './user.service';

describe('UserService admin store management', () => {
  let service: UserService;
  let prisma: any;

  const superAdmin = { role: 'SUPER_ADMIN' };
  const admin = { role: 'ADMIN' };

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
      },
    };
    service = new UserService(prisma, {} as any);
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
      }),
    ).resolves.toMatchObject({
      storeId: 'CP99',
      storeName: 'Cửa hàng CP99',
      transferAccountNumber: '123456',
      transferBankBin: '970415',
      userCount: 0,
    });

    expect(prisma.store.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          storeId: 'CP99',
          storeName: 'Cửa hàng CP99',
        }),
      }),
    );
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
