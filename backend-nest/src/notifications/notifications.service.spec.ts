import { NotificationsService } from './notifications.service';

describe('NotificationsService', () => {
  let prisma: any;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = {
      $transaction: jest.fn(async (operations: Array<Promise<unknown>>) =>
        Promise.all(operations),
      ),
      appNotificationReadReceipt: {
        upsert: jest.fn(async (args: any) => args),
        findMany: jest.fn(),
      },
    };
    service = new NotificationsService(prisma);
  });

  it('upserts unique read receipts for the signed-in user', async () => {
    const result = await service.markRead(
      { id: 'user-1' },
      {
        source: 'statement_order_transfer',
        ids: [' request-1 ', 'request-1', '', 'request-2'],
      },
    );

    expect(result).toMatchObject({
      source: 'statement_order_transfer',
      count: 2,
      readAt: expect.any(String),
    });
    expect(prisma.appNotificationReadReceipt.upsert).toHaveBeenCalledTimes(2);
    expect(prisma.appNotificationReadReceipt.upsert).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        where: {
          userId_source_notificationId: {
            userId: 'user-1',
            source: 'statement_order_transfer',
            notificationId: 'request-1',
          },
        },
        create: expect.objectContaining({
          userId: 'user-1',
          source: 'statement_order_transfer',
          notificationId: 'request-1',
        }),
        update: expect.objectContaining({ readAt: expect.any(Date) }),
      }),
    );
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });

  it('skips mark-read when user or ids are missing', async () => {
    await expect(
      service.markRead(null, {
        source: 'offset_adjustment',
        ids: [''],
      }),
    ).resolves.toMatchObject({ source: 'offset_adjustment', count: 0 });

    expect(prisma.appNotificationReadReceipt.upsert).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('returns read timestamps by notification id', async () => {
    const readAt = new Date('2026-06-26T03:00:00.000Z');
    prisma.appNotificationReadReceipt.findMany.mockResolvedValue([
      { notificationId: 'offset-1', readAt },
    ]);

    const result = await service.readAtByNotificationId(
      { id: 'user-1' },
      'offset_adjustment',
      ['offset-1', 'offset-1', ''],
    );

    expect(prisma.appNotificationReadReceipt.findMany).toHaveBeenCalledWith({
      where: {
        userId: 'user-1',
        source: 'offset_adjustment',
        notificationId: { in: ['offset-1'] },
      },
      select: { notificationId: true, readAt: true },
    });
    expect(result.get('offset-1')).toBe(readAt);
  });
});
