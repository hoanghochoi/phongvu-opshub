import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { WarrantyService } from './warranty.service';

describe('WarrantyService', () => {
  let service: WarrantyService;
  let prisma: {
    warranty: {
      findFirst: jest.Mock;
      findMany: jest.Mock;
      create: jest.Mock;
      update: jest.Mock;
    };
  };
  let redisService: { publishMessage: jest.Mock };

  const storeUser = { id: 'user-1', role: 'STAFF', storeId: 'store-1' };
  const superAdmin = { id: 'admin-1', role: 'SUPER_ADMIN', storeId: null };

  beforeEach(() => {
    prisma = {
      warranty: {
        findFirst: jest.fn(),
        findMany: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
    };
    redisService = { publishMessage: jest.fn() };
    service = new WarrantyService(prisma as any, redisService as any);
  });

  it('filters warranty lists to the signed-in store', async () => {
    prisma.warranty.findMany.mockResolvedValue([]);

    await expect(service.getAllWarranties(storeUser)).resolves.toEqual([]);

    expect(prisma.warranty.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { createdBy: { storeId: 'store-1' } },
      }),
    );
  });

  it('lets SUPER_ADMIN list all warranties', async () => {
    prisma.warranty.findMany.mockResolvedValue([]);

    await expect(service.getAllWarranties(superAdmin)).resolves.toEqual([]);

    expect(prisma.warranty.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: {} }),
    );
  });

  it('formats receipt details for the Flutter app within store scope', async () => {
    const createdAt = new Date('2026-04-25T01:02:03.000Z');
    prisma.warranty.findFirst.mockResolvedValue({
      id: 'warranty-1',
      receipt: 'CP01-J12345678',
      imageLinks: 'https://img.example.com/0.jpg;https://img.example.com/1.jpg',
      createdAt,
      createdBy: { firstName: 'An' },
      handledBy: null,
    });

    await expect(
      service.getByReceipt(storeUser, 'CP01-J12345678'),
    ).resolves.toMatchObject({
      receipt: 'CP01-J12345678',
      user: 'An',
      date: '2026-04-25T01:02:03.000Z',
      images: [
        'https://img.example.com/0.jpg',
        'https://img.example.com/1.jpg',
      ],
    });
    expect(prisma.warranty.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          AND: [
            { createdBy: { storeId: 'store-1' } },
            { receipt: 'CP01-J12345678' },
          ],
        },
      }),
    );
  });

  it('throws when receipt is not found in the readable scope', async () => {
    prisma.warranty.findFirst.mockResolvedValue(null);

    await expect(service.getByReceipt(storeUser, 'missing')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('rejects missing receipt details before querying', async () => {
    await expect(service.getByReceipt(storeUser, '')).rejects.toBeInstanceOf(
      BadRequestException,
    );

    expect(prisma.warranty.findFirst).not.toHaveBeenCalled();
  });

  it('blocks non-SUPER_ADMIN users without a store', async () => {
    await expect(
      service.getAllWarranties({ id: 'user-2', role: 'STAFF', storeId: null }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('publishes warranty status updates after scope check', async () => {
    const updated = { id: 'warranty-1', status: 'DONE' };
    prisma.warranty.findFirst.mockResolvedValue({ id: 'warranty-1' });
    prisma.warranty.update.mockResolvedValue(updated);
    redisService.publishMessage.mockResolvedValue(undefined);

    await expect(
      service.updateWarrantyStatus(storeUser, 'warranty-1', 'user-1', 'DONE'),
    ).resolves.toBe(updated);

    expect(prisma.warranty.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          AND: [{ createdBy: { storeId: 'store-1' } }, { id: 'warranty-1' }],
        },
      }),
    );
    expect(redisService.publishMessage).toHaveBeenCalledWith(
      'WARRANTY_STATUS_UPDATED',
      expect.objectContaining({
        warrantyId: 'warranty-1',
        newStatus: 'DONE',
        handledBy: 'user-1',
      }),
    );
  });
});
