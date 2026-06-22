import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { mkdtemp, readFile, rm, writeFile } from 'fs/promises';
import { tmpdir } from 'os';
import { join } from 'path';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PaymentNotificationsService } from './payment-notifications.service';

describe('PaymentNotificationsService', () => {
  const originalEnv = process.env;
  let prisma: any;
  let redis: any;
  let policyService: { canAccessPolicy: jest.Mock };
  let featureService: { canAccessFeature: jest.Mock };
  let service: PaymentNotificationsService;
  const speakerUser = (overrides: Record<string, unknown> = {}) => ({
    id: 'user-speaker',
    role: 'USER',
    storeId: 'store-uuid-1',
    organizationNodeId: 'org-store-cp01-pos-store-manager',
    hasPaymentSpeakerFeature: true,
    ...overrides,
  });

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
        createMany: jest.fn(),
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
      organizationNode: {
        findUnique: jest.fn(),
      },
      $executeRaw: jest.fn(),
      $transaction: jest.fn(async (callback: any) => callback(prisma)),
    };
    redis = { publishMessage: jest.fn().mockResolvedValue(undefined) };
    policyService = {
      canAccessPolicy: jest.fn(
        async (user: any, code: string) =>
          user?.role === 'SUPER_ADMIN' &&
          String(code || '').toUpperCase() ===
            ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
      ),
    };
    featureService = {
      canAccessFeature: jest.fn(
        async (user: any, code: string) =>
          String(code || '').toUpperCase() === 'PAYMENT_SPEAKER' &&
          (user?.role === 'SUPER_ADMIN' ||
            user?.hasPaymentSpeakerFeature !== false),
      ),
    };
    prisma.organizationNode.findUnique.mockImplementation(
      async ({ where }: any) => {
        const id = String(where?.id || '');
        if (!id) return null;
        const businessCode = id.toUpperCase().includes('CASH')
          ? 'CASH'
          : id.toUpperCase().includes('WAREHOUSE')
            ? 'WAREHOUSE'
            : id.toUpperCase().includes('SA')
              ? 'SA'
              : 'STORE_MANAGER';
        return {
          id,
          type: 'LV5_POSITION',
          businessCode,
          code: `POS_${businessCode}`,
          isActive: true,
        };
      },
    );
    service = new PaymentNotificationsService(
      prisma,
      redis,
      policyService as any,
      featureService as any,
    );
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
      service.getAudioForUser(speakerUser({ id: 'user-1' }), 'note-1'),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('returns original TTS-only audio by default', async () => {
    const temp = await mkdtemp(join(tmpdir(), 'opshub-payment-tts-only-'));
    const voicePath = join(temp, 'ready.wav');
    try {
      await writeFile(voicePath, pcm16Wav({ frames: [0, 1000, -1000] }));
      prisma.paymentNotification.findUnique.mockResolvedValue({
        id: 'note-tts-only',
        storeCode: 'CP01',
        audioStatus: 'READY',
        audioPath: voicePath,
        audioMime: 'audio/wav',
      });
      prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });

      await expect(
        service.getAudioForUser(speakerUser(), 'note-tts-only'),
      ).resolves.toEqual(
        expect.objectContaining({
          fileName: 'ready.wav',
          mimeType: 'audio/wav',
        }),
      );
    } finally {
      await rm(temp, { recursive: true, force: true });
    }
  });

  it('returns a cached cue plus full TTS WAV when includeCue is requested', async () => {
    const temp = await mkdtemp(join(tmpdir(), 'opshub-payment-audio-'));
    const cuePath = join(temp, 'payment-cue.wav');
    const voicePath = join(temp, 'ready.wav');
    const combinedPath = join(temp, 'ready-with-cue.wav');
    const cueWav = pcm16Wav({
      sampleRateHz: 1000,
      frames: [0, 1000, -1000],
    });
    const voiceWav = pcm16Wav({
      sampleRateHz: 1000,
      frames: [...Array(120).fill(0), 2000, -2000, ...Array(400).fill(0)],
    });
    try {
      await writeFile(cuePath, cueWav);
      await writeFile(voicePath, voiceWav);
      process.env.PAYMENT_CUE_WAV_PATH = cuePath;
      service = new PaymentNotificationsService(
        prisma,
        redis,
        policyService as any,
        featureService as any,
      );
      prisma.paymentNotification.findUnique.mockResolvedValue({
        id: 'note-combined',
        storeCode: 'CP01',
        audioStatus: 'READY',
        audioPath: voicePath,
        audioMime: 'audio/wav',
      });
      prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });

      await expect(
        service.getAudioForUser(speakerUser(), 'note-combined', {
          includeCue: true,
        }),
      ).resolves.toEqual(
        expect.objectContaining({
          fileName: 'ready-with-cue.wav',
          mimeType: 'audio/wav',
        }),
      );

      const combined = await readFile(combinedPath);
      const expectedFrames = 3 + 120 + 2 + 400;
      expect(wavDataBytes(combined)).toBe(expectedFrames * 2);

      await expect(
        service.getAudioForUser(speakerUser(), 'note-combined', {
          includeCue: true,
        }),
      ).resolves.toEqual(
        expect.objectContaining({
          fileName: 'ready-with-cue.wav',
          mimeType: 'audio/wav',
        }),
      );
    } finally {
      delete process.env.PAYMENT_CUE_WAV_PATH;
      await rm(temp, { recursive: true, force: true });
    }
  });

  it('rejects combined cue audio for non-WAV legacy audio', async () => {
    prisma.paymentNotification.findUnique.mockResolvedValue({
      id: 'note-mp3',
      storeCode: 'CP01',
      audioStatus: 'READY',
      audioPath: 'ready.mp3',
      audioMime: 'audio/mpeg',
    });
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });

    await expect(
      service.getAudioForUser(speakerUser(), 'note-mp3', {
        includeCue: true,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects combined cue audio when the server cue WAV is missing', async () => {
    const temp = await mkdtemp(join(tmpdir(), 'opshub-payment-missing-cue-'));
    const voicePath = join(temp, 'ready.wav');
    try {
      await writeFile(voicePath, pcm16Wav({ frames: [0, 1000, -1000] }));
      process.env.PAYMENT_CUE_WAV_PATH = join(temp, 'missing-cue.wav');
      service = new PaymentNotificationsService(
        prisma,
        redis,
        policyService as any,
        featureService as any,
      );
      prisma.paymentNotification.findUnique.mockResolvedValue({
        id: 'note-missing-cue',
        storeCode: 'CP01',
        audioStatus: 'READY',
        audioPath: voicePath,
        audioMime: 'audio/wav',
      });
      prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });

      await expect(
        service.getAudioForUser(speakerUser(), 'note-missing-cue', {
          includeCue: true,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    } finally {
      delete process.env.PAYMENT_CUE_WAV_PATH;
      await rm(temp, { recursive: true, force: true });
    }
  });

  it('deletes cached combined cue audio when notification audio expires', async () => {
    const temp = await mkdtemp(join(tmpdir(), 'opshub-payment-cleanup-'));
    const voicePath = join(temp, 'ready.wav');
    const combinedPath = join(temp, 'ready-with-cue.wav');
    try {
      await writeFile(voicePath, pcm16Wav({ frames: [1, 2, 3] }));
      await writeFile(combinedPath, pcm16Wav({ frames: [1, 2, 3, 4] }));
      prisma.paymentNotification.findMany.mockResolvedValue([
        { id: 'note-expired', audioPath: voicePath },
      ]);
      prisma.paymentNotification.update.mockResolvedValue({});

      await service.cleanupExpiredData();

      await expect(readFile(voicePath)).rejects.toThrow();
      await expect(readFile(combinedPath)).rejects.toThrow();
      expect(prisma.paymentNotification.update).toHaveBeenCalledWith({
        where: { id: 'note-expired' },
        data: {
          audioPath: null,
          audioMime: null,
          audioStatus: 'EXPIRED',
        },
      });
    } finally {
      await rm(temp, { recursive: true, force: true });
    }
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
      service.acknowledge(speakerUser({ id: 'user-1' }), 'note-1', {
        clientId: 'pc-1',
        event: 'PLAYED',
      }),
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

  it('lets SUPER_ADMIN acknowledge speaker events without an Lv5 node', async () => {
    prisma.paymentNotification.findUnique.mockResolvedValue({
      id: 'note-1',
      transactionId: 'txn-1',
      storeCode: 'CP01',
    });
    prisma.paymentNotificationDeliveryLog.create.mockResolvedValue({});

    await expect(
      service.acknowledge(
        speakerUser({
          id: 'super-1',
          role: 'SUPER_ADMIN',
          storeId: null,
          organizationNodeId: null,
        }),
        'note-1',
        {
          clientId: 'pc-1',
          event: 'PLAYED',
        },
      ),
    ).resolves.toEqual({ ok: true });

    expect(prisma.organizationNode.findUnique).not.toHaveBeenCalled();
    expect(prisma.paymentNotificationDeliveryLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        notificationId: 'note-1',
        transactionId: 'txn-1',
        storeCode: 'CP01',
        userId: 'super-1',
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
      service.acknowledge(speakerUser({ id: 'user-1' }), 'note-1', {
        clientId: 'pc-1',
        event: 'PLAYBACK_FAILED',
        error: 'speaker failed attempt 1',
      }),
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

    await service.listReadyForClient(speakerUser(), {
      clientId: 'pc-1',
      afterCreatedAt: checkpoint.toISOString(),
    });

    expect(prisma.paymentNotification.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          createdAt: { gt: checkpoint },
        }),
      }),
    );
  });

  it.each([
    ['SA', 'org-store-cp01-pos-sa'],
    ['WAREHOUSE', 'org-store-cp01-pos-warehouse'],
  ])(
    'returns no ready audio notifications without PAYMENT_SPEAKER for Lv5 position %s',
    async (_position, organizationNodeId) => {
      await expect(
        service.listReadyForClient(
          speakerUser({
            organizationNodeId,
            hasPaymentSpeakerFeature: false,
          }),
          {
            clientId: 'pc-1',
          },
        ),
      ).resolves.toEqual({ list: [] });

      expect(prisma.store.findUnique).not.toHaveBeenCalled();
      expect(prisma.paymentNotification.findMany).not.toHaveBeenCalled();
      expect(
        prisma.paymentNotificationDeliveryLog.createMany,
      ).not.toHaveBeenCalled();
    },
  );

  it('rejects audio and ack without PAYMENT_SPEAKER', async () => {
    prisma.paymentNotification.findUnique.mockResolvedValue({
      id: 'note-1',
      transactionId: 'txn-1',
      storeCode: 'CP01',
      audioStatus: 'READY',
      audioPath: 'ready.wav',
    });

    const warehouseUser = speakerUser({
      organizationNodeId: 'org-store-cp01-pos-warehouse',
      hasPaymentSpeakerFeature: false,
    });

    await expect(
      service.getAudioForUser(warehouseUser, 'note-1'),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.acknowledge(warehouseUser, 'note-1', {
        clientId: 'pc-1',
        event: 'PLAYED',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.store.findUnique).not.toHaveBeenCalled();
    expect(prisma.paymentNotificationDeliveryLog.create).not.toHaveBeenCalled();
  });

  it('allows a non-legacy Lv5 position when PAYMENT_SPEAKER is assigned', async () => {
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });
    prisma.paymentNotification.findMany.mockResolvedValue([]);

    await expect(
      service.listReadyForClient(
        speakerUser({ organizationNodeId: 'org-store-cp01-pos-sa' }),
        {
          clientId: 'pc-1',
        },
      ),
    ).resolves.toEqual({ list: [] });

    expect(featureService.canAccessFeature).toHaveBeenCalledWith(
      expect.objectContaining({
        organizationNodeId: 'org-store-cp01-pos-sa',
      }),
      'PAYMENT_SPEAKER',
    );
    expect(prisma.paymentNotification.findMany).toHaveBeenCalled();
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
      service.listReadyForClient(speakerUser(), { clientId: 'pc-1' }),
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
    expect(prisma.paymentNotificationDeliveryLog.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          clientId: 'pc-1',
          storeCode: 'CP01',
          OR: expect.arrayContaining([
            { event: { in: ['PLAYED', 'SILENCED', 'FAILED'] } },
            expect.objectContaining({
              event: 'DELIVERED',
              createdAt: expect.any(Object),
            }),
          ]),
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
    expect(
      prisma.paymentNotificationDeliveryLog.createMany,
    ).toHaveBeenCalledWith({
      data: [
        expect.objectContaining({
          notificationId: 'note-ready',
          transactionId: 'txn-ready',
          storeCode: 'CP01',
          clientId: 'pc-1',
          event: 'DELIVERED',
        }),
      ],
    });
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
      service.listReadyForClient(speakerUser(), {
        clientId: 'pc-1779876132645257',
      }),
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
      service.listReadyForClient(speakerUser(), {
        clientId: 'pc-1779876132645257',
        limit: '3',
      }),
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
    prisma.store.findUnique.mockResolvedValue({ storeId: 'CP01' });

    await expect(
      service.getAudioForUser(speakerUser(), 'note-1'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});

function pcm16Wav({
  sampleRateHz = 22050,
  frames,
}: {
  sampleRateHz?: number;
  frames: number[];
}) {
  const channels = 1;
  const blockAlign = channels * 2;
  const dataBytes = frames.length * blockAlign;
  const buffer = Buffer.alloc(44 + dataBytes);
  buffer.write('RIFF', 0, 'ascii');
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write('WAVE', 8, 'ascii');
  buffer.write('fmt ', 12, 'ascii');
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(channels, 22);
  buffer.writeUInt32LE(sampleRateHz, 24);
  buffer.writeUInt32LE(sampleRateHz * blockAlign, 28);
  buffer.writeUInt16LE(blockAlign, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36, 'ascii');
  buffer.writeUInt32LE(dataBytes, 40);
  frames.forEach((sample, index) => {
    buffer.writeInt16LE(sample, 44 + index * blockAlign);
  });
  return buffer;
}

function wavDataBytes(buffer: Buffer) {
  let offset = 12;
  while (offset + 8 <= buffer.length) {
    const chunkId = buffer.toString('ascii', offset, offset + 4);
    const chunkSize = buffer.readUInt32LE(offset + 4);
    if (chunkId === 'data') return chunkSize;
    offset += 8 + chunkSize + (chunkSize % 2);
  }
  throw new Error('WAV data chunk not found');
}
