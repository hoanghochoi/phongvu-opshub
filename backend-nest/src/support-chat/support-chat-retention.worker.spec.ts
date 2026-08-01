import { SupportChatRetentionWorker } from './support-chat-retention.worker';

describe('SupportChatRetentionWorker', () => {
  it('purges bounded expired rows and orphan media under the advisory lock', async () => {
    const tx = {
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([{ acquired: true }])
        .mockResolvedValueOnce([{ id: 'media-orphan' }]),
      supportMessage: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            { id: 'message-old', mediaIds: ['media-message'] },
          ]),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      supportAuditEvent: {
        findMany: jest.fn().mockResolvedValue([{ id: 'audit-old' }]),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      domainOutboxEvent: {
        findMany: jest.fn().mockResolvedValue([{ id: 'outbox-old' }]),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      supportConversation: {
        findMany: jest.fn().mockResolvedValue([{ id: 'conversation-orphan' }]),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const prisma = {
      $transaction: jest
        .fn()
        .mockImplementation((callback: any) => callback(tx)),
    };
    const media = {
      publicUrl: jest.fn((id: string) => `/media/${id}`),
      discardUrlsStrict: jest.fn().mockResolvedValue(undefined),
    };
    const worker = new SupportChatRetentionWorker(prisma as any, media as any);

    const result = await worker.purgeExpired();

    expect(result).toMatchObject({
      messageCount: 1,
      auditCount: 1,
      outboxCount: 1,
      conversationCount: 1,
    });
    expect(media.discardUrlsStrict).toHaveBeenCalledWith([
      '/media/media-message',
      '/media/media-orphan',
    ]);
  });

  it('does not purge when another retention worker owns the lock', async () => {
    const prisma = {
      $transaction: jest.fn().mockImplementation((callback: any) =>
        callback({
          $queryRaw: jest.fn().mockResolvedValue([{ acquired: false }]),
        }),
      ),
    };
    const media = { discardUrlsStrict: jest.fn() };
    const worker = new SupportChatRetentionWorker(prisma as any, media as any);

    await expect(worker.purgeExpired()).resolves.toBeNull();
    expect(media.discardUrlsStrict).not.toHaveBeenCalled();
  });

  it('fails the purge when strict media cleanup fails', async () => {
    const tx = {
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([{ acquired: true }])
        .mockResolvedValueOnce([]),
      supportMessage: {
        findMany: jest
          .fn()
          .mockResolvedValue([{ id: 'message-old', mediaIds: ['media-old'] }]),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      supportAuditEvent: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn(),
      },
      domainOutboxEvent: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn(),
      },
      supportConversation: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn(),
      },
    };
    const prisma = {
      $transaction: jest
        .fn()
        .mockImplementation((callback: any) => callback(tx)),
    };
    const media = {
      publicUrl: jest.fn((id: string) => `/media/${id}`),
      discardUrlsStrict: jest
        .fn()
        .mockRejectedValue(new Error('unlink_failed')),
    };
    const worker = new SupportChatRetentionWorker(prisma as any, media as any);

    await expect(worker.purgeExpired()).rejects.toThrow('unlink_failed');
  });
});
