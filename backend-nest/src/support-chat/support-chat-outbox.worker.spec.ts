import { SupportChatOutboxWorker } from './support-chat-outbox.worker';

describe('SupportChatOutboxWorker', () => {
  const originalFlag = process.env.SUPPORT_CHAT_ENABLED;

  afterAll(() => {
    if (originalFlag === undefined) delete process.env.SUPPORT_CHAT_ENABLED;
    else process.env.SUPPORT_CHAT_ENABLED = originalFlag;
  });

  it('publishes only requester and current assignee for thread invalidation', async () => {
    process.env.SUPPORT_CHAT_ENABLED = 'true';
    const prisma = {
      $queryRaw: jest.fn().mockResolvedValue([
        {
          id: 'event-1',
          aggregateId: 'conversation-1',
          payload: {
            scope: 'THREAD',
            conversationId: 'conversation-1',
            requesterId: 'requester-1',
            currentAssigneeId: 'admin-current',
            previousAssigneeId: 'admin-former',
            readerId: 'admin-reader',
            revision: '4',
            lastSequence: '9',
            changeType: 'TAKEN_OVER',
          },
          occurredAt: new Date('2026-08-01T01:02:03.000Z'),
          attempts: 1,
        },
      ]),
      domainOutboxEvent: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const redis = { publishMessageOrThrow: jest.fn().mockResolvedValue(1) };
    const worker = new SupportChatOutboxWorker(prisma as any, redis as any);

    await worker.drain();

    const envelope = redis.publishMessageOrThrow.mock.calls[0][1];
    expect(envelope.audience.recipientUserIds).toEqual([
      'requester-1',
      'admin-current',
    ]);
    expect(JSON.stringify(envelope)).not.toContain('admin-former');
    expect(JSON.stringify(envelope)).not.toContain('admin-reader');
    expect(envelope.payload).toEqual({
      scope: 'THREAD',
      conversationId: 'conversation-1',
      revision: '4',
      lastSequence: '9',
      changeType: 'TAKEN_OVER',
    });
  });

  it('releases a failed lease for retry without throwing a committed send', async () => {
    process.env.SUPPORT_CHAT_ENABLED = 'true';
    const updateMany = jest.fn().mockResolvedValue({ count: 1 });
    const prisma = {
      $queryRaw: jest.fn().mockResolvedValue([
        {
          id: 'event-2',
          aggregateId: 'conversation-1',
          payload: {
            scope: 'QUEUE',
            revision: '1',
            changeType: 'MESSAGE_CREATED',
          },
          occurredAt: new Date('2026-08-01T01:02:03.000Z'),
          attempts: 1,
        },
      ]),
      domainOutboxEvent: { updateMany },
    };
    const redis = {
      publishMessageOrThrow: jest
        .fn()
        .mockRejectedValue(new Error('redis_down')),
    };
    const worker = new SupportChatOutboxWorker(prisma as any, redis as any);

    await expect(worker.drain()).resolves.toBeUndefined();
    expect(updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          claimedAt: null,
          claimToken: null,
          leaseExpiresAt: null,
          availableAt: expect.any(Date),
        }),
      }),
    );
  });
});
