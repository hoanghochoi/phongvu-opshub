import { NotFoundException } from '@nestjs/common';
import { WarrantyService } from './warranty.service';

describe('WarrantyService', () => {
  let service: WarrantyService;
  let prisma: {
    warranty: {
      findUnique: jest.Mock;
      findMany: jest.Mock;
      create: jest.Mock;
      update: jest.Mock;
    };
  };
  let redisService: { publishMessage: jest.Mock };

  beforeEach(() => {
    prisma = {
      warranty: {
        findUnique: jest.fn(),
        findMany: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
    };
    redisService = { publishMessage: jest.fn() };
    service = new WarrantyService(prisma as any, redisService as any);
  });

  it('formats receipt details for the Flutter app', async () => {
    const createdAt = new Date('2026-04-25T01:02:03.000Z');
    prisma.warranty.findUnique.mockResolvedValue({
      id: 'warranty-1',
      receipt: 'CP01-J12345678',
      imageLinks: 'https://img.example.com/0.jpg;https://img.example.com/1.jpg',
      createdAt,
      createdBy: { firstName: 'An' },
      handledBy: null,
    });

    await expect(service.getByReceipt('CP01-J12345678')).resolves.toMatchObject(
      {
        receipt: 'CP01-J12345678',
        user: 'An',
        date: '2026-04-25T01:02:03.000Z',
        images: [
          'https://img.example.com/0.jpg',
          'https://img.example.com/1.jpg',
        ],
      },
    );
  });

  it('throws when receipt is not found', async () => {
    prisma.warranty.findUnique.mockResolvedValue(null);

    await expect(service.getByReceipt('missing')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('publishes warranty status updates', async () => {
    const updated = { id: 'warranty-1', status: 'DONE' };
    prisma.warranty.update.mockResolvedValue(updated);
    redisService.publishMessage.mockResolvedValue(undefined);

    await expect(
      service.updateWarrantyStatus('warranty-1', 'user-1', 'DONE'),
    ).resolves.toBe(updated);

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
