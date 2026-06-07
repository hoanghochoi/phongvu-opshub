import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PaymentNotificationsService } from './payment-notifications.service';

describe('PaymentNotificationsService', () => {
  const originalEnv = process.env;
  let prisma: any;
  let redis: any;
  let policyService: { canAccessPolicy: jest.Mock };
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
        findFirst: jest.fn(),
        findMany: jest.fn().mockResolvedValue([]),
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
    policyService = {
      canAccessPolicy: jest.fn(async (user: any, code: string) =>
        user?.role === 'SUPER_ADMIN' &&
        String(code || '').toUpperCase() === ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
      ),
    };
    service = new PaymentNotificationsService(prisma, redis, policyService as any);
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
      text: 'Phong Vũ đã nhận: một triệu hai trăm năm mươi nghìn đồng.',
      audioStatus: 'PENDING',
      audioError: null,
    });
    prisma.paymentNotification.update.mockResolvedValue({
      id: 'note-1',
      storeCode: 'CP01',
      transactionId: 'txn-1',
      amount: 1250000,
      text: 'Phong Vũ đã nhận: một triệu hai trăm năm mươi nghìn đồng.',
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
          text: 'Phong Vũ đã nhận: một triệu hai trăm năm mươi nghìn đồng.',
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

  it('sends Phong Vu payment text with the default Piper voice settings', async () => {
    process.env.TTS_SERVICE_URL = 'http://piper-tts:8000';
    const fetchMock = jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: false,
      status: 500,
    } as Response);
    prisma.paymentNotification.findUnique.mockResolvedValue(null);
    prisma.paymentNotification.create.mockResolvedValue({
      id: 'note-voice',
      storeCode: 'CP01',
      transactionId: 'txn-voice',
      amount: 28756321,
      text: 'Phong Vũ đã nhận: hai mươi tám triệu bảy trăm năm mươi sáu nghìn ba trăm hai mươi mốt đồng.',
      audioStatus: 'PENDING',
      audioError: null,
    });
    prisma.paymentNotification.update.mockResolvedValue({
      id: 'note-voice',
      storeCode: 'CP01',
      transactionId: 'txn-voice',
      amount: 28756321,
      audioStatus: 'FAILED',
      audioError: 'TTS returned HTTP 500',
    });
    prisma.paymentNotificationDeliveryLog.create.mockResolvedValue({});

    await service.createForTransaction({
      id: 'txn-voice',
      storeCode: 'CP01',
      amount: 28756321,
    });

    expect(fetchMock).toHaveBeenCalledWith(
      'http://piper-tts:8000/synthesize',
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    const [, request] = fetchMock.mock.calls[0];
    expect(JSON.parse(String((request as RequestInit).body))).toEqual({
      text: 'Phong Vũ đã nhận: hai mươi tám triệu bảy trăm năm mươi sáu nghìn ba trăm hai mươi mốt đồng.',
      format: 'mp3',
      voice_id: 'piper:vi-vais1000',
      speed: 0.9,
      pitch: 1.0,
    });
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

  it('records playback failed acknowledgement without marking it terminal', async () => {
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
        {
          clientId: 'pc-1',
          event: 'PLAYBACK_FAILED',
          error: 'speaker failed attempt 1',
        },
      ),
    ).resolves.toEqual({ ok: true });

    expect(prisma.paymentNotificationDeliveryLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        notificationId: 'note-1',
        transactionId: 'txn-1',
        storeCode: 'CP01',
        userId: 'user-1',
        clientId: 'pc-1',
        event: 'PLAYBACK_FAILED',
        error: 'speaker failed attempt 1',
      }),
    });
  });

  it('filters ready notifications after the requested createdAt checkpoint', async () => {
    const checkpoint = new Date('2026-05-21T10:00:00.000Z');
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });
    prisma.paymentNotification.findMany.mockResolvedValue([]);

    await service.listReadyForClient(
      { role: 'MANAGER', storeId: 'store-uuid-1' },
      { clientId: 'pc-1', afterCreatedAt: checkpoint.toISOString() },
    );

    expect(prisma.paymentNotification.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          createdAt: { gt: checkpoint },
        }),
      }),
    );
  });

  it('lists ready audio notifications not yet terminal for this client', async () => {
    const createdAt = new Date('2026-05-21T10:00:00.000Z');
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });
    prisma.paymentNotificationDeliveryLog.findMany.mockResolvedValue([
      { notificationId: 'note-played' },
      { notificationId: 'note-failed' },
    ]);
    prisma.paymentNotification.findMany.mockResolvedValue([
      {
        id: 'note-ready',
        transactionId: 'txn-ready',
        storeCode: 'CP01',
        amount: 2000,
        audioStatus: 'READY',
        audioPath: 'ready.wav',
        createdAt,
      },
    ]);

    await expect(
      service.listReadyForClient(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        { clientId: 'pc-1' },
      ),
    ).resolves.toEqual({
      list: [
        {
          notificationId: 'note-ready',
          transactionId: 'txn-ready',
          storeCode: 'CP01',
          amount: 2000,
          audioStatus: 'READY',
          audioUrl: '/payment-notifications/note-ready/audio',
          createdAt: createdAt.toISOString(),
        },
      ],
    });
    expect(
      prisma.paymentNotificationDeliveryLog.findMany,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          clientId: 'pc-1',
          storeCode: 'CP01',
          event: { in: ['PLAYED', 'SILENCED', 'FAILED'] },
        }),
        select: { notificationId: true },
        distinct: ['notificationId'],
      }),
    );
    expect(prisma.paymentNotification.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: { notIn: ['note-played', 'note-failed'] },
        }),
        take: 10,
      }),
    );
  });

  it('does not let an old failed notification hide a newer ready notification', async () => {
    const newer = new Date('2026-05-21T10:05:00.000Z');
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP67' });
    prisma.paymentNotificationDeliveryLog.findMany.mockResolvedValue([
      { notificationId: 'note-old-failed' },
    ]);
    prisma.paymentNotification.findMany.mockResolvedValue([
      {
        id: 'note-new-ready',
        transactionId: 'txn-new-ready',
        storeCode: 'CP67',
        amount: 3835000,
        audioStatus: 'READY',
        audioPath: 'new-ready.wav',
        createdAt: newer,
      },
    ]);

    await expect(
      service.listReadyForClient(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        { clientId: 'pc-1779876132645257' },
      ),
    ).resolves.toEqual({
      list: [
        {
          notificationId: 'note-new-ready',
          transactionId: 'txn-new-ready',
          storeCode: 'CP67',
          amount: 3835000,
          audioStatus: 'READY',
          audioUrl: '/payment-notifications/note-new-ready/audio',
          createdAt: newer.toISOString(),
        },
      ],
    });
    expect(prisma.paymentNotification.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: { notIn: ['note-old-failed'] },
        }),
      }),
    );
  });

  it('does not cap the ready search before excluding many terminal notifications', async () => {
    const newer = new Date('2026-05-21T10:15:00.000Z');
    const terminalIds = Array.from({ length: 12 }, (_, index) => ({
      notificationId: `note-terminal-${index + 1}`,
    }));
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP67' });
    prisma.paymentNotificationDeliveryLog.findMany.mockResolvedValue(
      terminalIds,
    );
    prisma.paymentNotification.findMany.mockResolvedValue([
      {
        id: 'note-new-ready',
        transactionId: 'txn-new-ready',
        storeCode: 'CP67',
        amount: 3835000,
        audioStatus: 'READY',
        audioPath: 'new-ready.wav',
        createdAt: newer,
      },
    ]);

    await expect(
      service.listReadyForClient(
        { role: 'MANAGER', storeId: 'store-uuid-1' },
        { clientId: 'pc-1779876132645257', limit: '3' },
      ),
    ).resolves.toEqual({
      list: [
        {
          notificationId: 'note-new-ready',
          transactionId: 'txn-new-ready',
          storeCode: 'CP67',
          amount: 3835000,
          audioStatus: 'READY',
          audioUrl: '/payment-notifications/note-new-ready/audio',
          createdAt: newer.toISOString(),
        },
      ],
    });

    expect(prisma.paymentNotification.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: {
            notIn: terminalIds.map((row) => row.notificationId),
          },
        }),
        take: 3,
      }),
    );
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
