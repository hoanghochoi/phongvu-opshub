import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { PaymentNotificationsService } from './payment-notifications.service';

describe('PaymentNotificationsService', () => {
  const originalEnv = process.env;
  let prisma: any;
  let redis: any;
  let service: PaymentNotificationsService;

  beforeEach(() => {
    process.env = { ...originalEnv };
    delete process.env.TTS_SERVICE_URL;
    prisma = {
      paymentNotification: {
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        findMany: jest.fn(),
      },
      paymentNotificationDeliveryLog: {
        create: jest.fn(),
        deleteMany: jest.fn(),
      },
      appLog: {
        create: jest.fn(),
        deleteMany: jest.fn(),
      },
      mapVietinTransaction: {
        deleteMany: jest.fn(),
      },
      store: {
        findUnique: jest.fn(),
      },
    };
    redis = { publishMessage: jest.fn().mockResolvedValue(undefined) };
    service = new PaymentNotificationsService(prisma, redis);
  });

  afterEach(() => {
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  it('creates notification, marks audio failed without TTS config, and publishes scoped event', async () => {
    prisma.paymentNotification.findUnique.mockResolvedValue(null);
    prisma.paymentNotification.create.mockResolvedValue({
      id: 'note-1',
      storeCode: 'CP01',
      transactionId: 'txn-1',
      amount: 1250000,
      text: 'Đã nhận một triệu hai trăm năm mươi nghìn đồng',
      audioStatus: 'PENDING',
      audioError: null,
    });
    prisma.paymentNotification.update.mockResolvedValue({
      id: 'note-1',
      storeCode: 'CP01',
      transactionId: 'txn-1',
      amount: 1250000,
      text: 'Đã nhận một triệu hai trăm năm mươi nghìn đồng',
      audioStatus: 'FAILED',
      audioError: 'TTS_SERVICE_URL is not configured',
    });
    prisma.paymentNotificationDeliveryLog.create.mockResolvedValue({});

    await service.createForTransaction({
      id: 'txn-1',
      storeCode: 'CP01',
      amount: 1250000,
    });

    expect(prisma.paymentNotification.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          storeCode: 'CP01',
          transactionId: 'txn-1',
          amount: 1250000,
          text: 'Đã nhận một triệu hai trăm năm mươi nghìn đồng',
        }),
      }),
    );
    expect(redis.publishMessage).toHaveBeenCalledWith(
      'PAYMENT_NOTIFICATION_READY',
      expect.objectContaining({
        notificationId: 'note-1',
        storeCode: 'CP01',
        amount: 1250000,
        audioStatus: 'FAILED',
        audioUrl: null,
      }),
    );
  });

  it('blocks audio access outside the signed-in user store', async () => {
    prisma.paymentNotification.findUnique.mockResolvedValue({
      id: 'note-1',
      storeCode: 'CP02',
      audioStatus: 'READY',
      audioPath: 'file.mp3',
    });
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });

    await expect(
      service.getAudioForUser(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        'note-1',
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('records client acknowledgement with store scope', async () => {
    prisma.paymentNotification.findUnique.mockResolvedValue({
      id: 'note-1',
      transactionId: 'txn-1',
      storeCode: 'CP01',
    });
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });
    prisma.paymentNotificationDeliveryLog.create.mockResolvedValue({});

    await expect(
      service.acknowledge(
        { id: 'user-1', role: 'MANAGER', storeId: 'store-uuid-1' },
        'note-1',
        { clientId: 'pc-1', event: 'PLAYED' },
      ),
    ).resolves.toEqual({ ok: true });

    expect(prisma.paymentNotificationDeliveryLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        notificationId: 'note-1',
        transactionId: 'txn-1',
        storeCode: 'CP01',
        userId: 'user-1',
        clientId: 'pc-1',
        event: 'PLAYED',
      }),
    });
  });

  it('returns not found when notification audio is unavailable', async () => {
    prisma.paymentNotification.findUnique.mockResolvedValue({
      id: 'note-1',
      storeCode: 'CP01',
      audioStatus: 'FAILED',
      audioPath: null,
    });

    await expect(
      service.getAudioForUser({ role: 'SUPER_ADMIN' }, 'note-1'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
