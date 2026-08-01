import { ConflictException, NotFoundException } from '@nestjs/common';
import { PrivateMediaService } from '../upload/private-media.service';
import { SupportChatService } from './support-chat.service';

const now = new Date('2026-08-01T01:02:03.000Z');

function conversation(overrides: Record<string, unknown> = {}) {
  return {
    id: 'conversation-1',
    requesterId: 'requester-1',
    assigneeId: null,
    status: 'OPEN',
    revision: 0n,
    lastMessageSequence: 0n,
    unassignedSince: now,
    lastMessageAt: null,
    resolvedAt: null,
    createdAt: now,
    updatedAt: now,
    requester: { id: 'requester-1', firstName: 'An', lastName: 'Nguyen' },
    assignee: null,
    readReceipts: [],
    ...overrides,
  };
}

function message(overrides: Record<string, unknown> = {}) {
  return {
    id: 'message-1',
    conversationId: 'conversation-1',
    senderId: 'requester-1',
    senderRole: 'REQUESTER',
    sequence: 1n,
    clientMessageId: 'client-1',
    contentType: 'TEXT',
    text: 'Xin chao',
    mediaIds: [],
    createdAt: now,
    ...overrides,
  };
}

describe('SupportChatService', () => {
  let service: SupportChatService;
  let prisma: any;
  let tx: any;
  let media: any;
  const originalFlag = process.env.SUPPORT_CHAT_ENABLED;

  beforeEach(() => {
    process.env.SUPPORT_CHAT_ENABLED = 'true';
    const base = conversation();
    tx = {
      $queryRaw: jest.fn().mockResolvedValue([{ id: base.id }]),
      supportConversation: {
        upsert: jest.fn().mockResolvedValue({ id: base.id }),
        findUnique: jest.fn().mockResolvedValue(base),
        update: jest.fn().mockResolvedValue(base),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      supportMessage: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue(message()),
      },
      supportAuditEvent: { create: jest.fn().mockResolvedValue({}) },
      domainOutboxEvent: {
        create: jest.fn().mockResolvedValue({}),
        createMany: jest.fn().mockResolvedValue({ count: 2 }),
      },
      supportReadReceipt: {
        findUnique: jest.fn().mockResolvedValue(null),
        upsert: jest.fn().mockResolvedValue({
          lastReadSequence: 1n,
          updatedAt: now,
        }),
      },
    };
    prisma = {
      $transaction: jest
        .fn()
        .mockImplementation(async (callback: any) => callback(tx)),
      supportConversation: {
        findUnique: jest.fn().mockResolvedValue(null),
        findMany: jest.fn().mockResolvedValue([]),
      },
      supportMessage: {
        findUnique: jest.fn(),
        findMany: jest.fn(),
        count: jest.fn(),
      },
      $queryRaw: jest.fn(),
    };
    media = {
      saveImages: jest.fn(),
      discardUrls: jest.fn(),
      discardTemporaryFiles: jest.fn(),
      publicUrl: jest.fn(
        (id: string) => `https://api.example.com/api/media/${id}`,
      ),
    };
    service = new SupportChatService(
      prisma as any,
      media as unknown as PrivateMediaService,
    );
  });

  afterAll(() => {
    if (originalFlag === undefined) delete process.env.SUPPORT_CHAT_ENABLED;
    else process.env.SUPPORT_CHAT_ENABLED = originalFlag;
  });

  it('creates the first requester message atomically with a sequence and IDs-only outbox', async () => {
    const result = await service.sendRequesterText(
      { id: 'requester-1', role: 'USER' },
      { clientMessageId: 'client-1', text: 'Xin chao' },
    );

    expect(result.message).toMatchObject({
      id: 'message-1',
      conversationId: 'conversation-1',
      sequence: '1',
      text: 'Xin chao',
      senderKind: 'REQUESTER',
      type: 'TEXT',
    });
    expect(tx.supportConversation.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { requesterId: 'requester-1' },
        create: expect.objectContaining({ requesterId: 'requester-1' }),
      }),
    );
    const outbox = tx.domainOutboxEvent.createMany.mock.calls[0][0].data;
    expect(outbox).toHaveLength(2);
    expect(JSON.stringify(outbox)).not.toContain('Xin chao');
    expect(outbox[0].payload).toEqual(
      expect.objectContaining({
        scope: 'QUEUE',
        changeType: 'MESSAGE_CREATED',
      }),
    );
    expect(outbox[0].payload).not.toHaveProperty('conversationId');
  });

  it('fails closed when requester multipart files are not an array', async () => {
    await expect(
      service.sendRequesterImages(
        { id: 'requester-1', role: 'USER' },
        { clientMessageId: 'client-image-requester' },
        'tampered-files',
      ),
    ).rejects.toThrow('Vui lòng chọn từ 1 đến 4 ảnh để gửi.');

    expect(media.discardTemporaryFiles).toHaveBeenCalledWith([]);
    expect(media.saveImages).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('fails closed when admin multipart files are not an array', async () => {
    await expect(
      service.sendAdminImages(
        { id: 'admin-1', role: 'SUPER_ADMIN' },
        'conversation-1',
        { clientMessageId: 'client-image-admin' },
        'tampered-files',
      ),
    ).rejects.toThrow('Vui lòng chọn từ 1 đến 4 ảnh để gửi.');

    expect(media.discardTemporaryFiles).toHaveBeenCalledWith([]);
    expect(media.saveImages).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('keeps a requester message that arrived after history unread', async () => {
    prisma.supportConversation.findUnique.mockResolvedValue({
      id: 'conversation-1',
    });
    tx.supportConversation.findUnique.mockResolvedValue(
      conversation({ lastMessageSequence: 6n }),
    );
    tx.supportReadReceipt.findUnique.mockResolvedValue({
      lastReadSequence: 4n,
    });
    tx.supportReadReceipt.upsert.mockResolvedValue({ lastReadSequence: 5n });

    const result = await service.markRequesterRead(
      { id: 'requester-1', role: 'USER' },
      { lastReadSequence: '5' },
    );

    expect(result.lastReadSequence).toBe('5');
    expect(tx.supportReadReceipt.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ lastReadSequence: 5n }),
        update: { lastReadSequence: 5n },
      }),
    );
  });

  it('keeps an admin message that arrived after history unread', async () => {
    tx.supportConversation.findUnique.mockResolvedValue(
      conversation({ lastMessageSequence: 9n }),
    );
    tx.supportReadReceipt.findUnique.mockResolvedValue({
      lastReadSequence: 7n,
    });
    tx.supportReadReceipt.upsert.mockResolvedValue({ lastReadSequence: 8n });

    const result = await service.markAdminRead(
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      'conversation-1',
      { lastReadSequence: '8' },
    );

    expect(result.lastReadSequence).toBe('8');
    expect(tx.supportReadReceipt.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ lastReadSequence: 8n }),
        update: { lastReadSequence: 8n },
      }),
    );
  });

  it('does not decrease or re-emit an unchanged read receipt', async () => {
    let storedSequence = 7n;
    tx.supportConversation.findUnique.mockResolvedValue(
      conversation({ lastMessageSequence: 9n }),
    );
    tx.supportReadReceipt.findUnique.mockImplementation(async () => ({
      lastReadSequence: storedSequence,
    }));
    tx.supportReadReceipt.upsert.mockImplementation(async (input: any) => {
      storedSequence = input.update.lastReadSequence;
      return { lastReadSequence: storedSequence };
    });

    await service.markAdminRead(
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      'conversation-1',
      { lastReadSequence: '8' },
    );
    await service.markAdminRead(
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      'conversation-1',
      { lastReadSequence: '8' },
    );
    const result = await service.markAdminRead(
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      'conversation-1',
      { lastReadSequence: '6' },
    );

    expect(result.lastReadSequence).toBe('8');
    expect(tx.supportReadReceipt.upsert).toHaveBeenCalledTimes(1);
    expect(tx.domainOutboxEvent.create).toHaveBeenCalledTimes(1);
  });

  it('caps a read receipt at the locked conversation sequence', async () => {
    tx.supportConversation.findUnique.mockResolvedValue(
      conversation({ lastMessageSequence: 9n }),
    );
    tx.supportReadReceipt.upsert.mockResolvedValue({ lastReadSequence: 9n });

    const result = await service.markAdminRead(
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      'conversation-1',
      { lastReadSequence: '12' },
    );

    expect(result.lastReadSequence).toBe('9');
    expect(tx.supportReadReceipt.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ lastReadSequence: 9n }),
        update: { lastReadSequence: 9n },
      }),
    );
  });

  it('reopens a resolved requester conversation and clears its assignee in the same transaction', async () => {
    const resolved = conversation({
      status: 'RESOLVED',
      assigneeId: 'admin-1',
      revision: 4n,
      lastMessageSequence: 8n,
    });
    tx.supportConversation.findUnique.mockResolvedValue(resolved);

    await service.sendRequesterText(
      { id: 'requester-1', role: 'USER' },
      { clientMessageId: 'client-2', text: 'Mo lai' },
    );

    expect(tx.supportConversation.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'OPEN',
          assigneeId: null,
          resolvedAt: null,
          lastMessageSequence: 9n,
        }),
      }),
    );
    expect(tx.domainOutboxEvent.createMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.arrayContaining([
          expect.objectContaining({
            payload: expect.objectContaining({
              changeType: 'REOPENED',
            }),
          }),
        ]),
      }),
    );
    expect(
      JSON.stringify(tx.domainOutboxEvent.createMany.mock.calls[0][0]),
    ).not.toContain('previousAssigneeId');
  });

  it('returns the stored message on an idempotent retry without creating a duplicate', async () => {
    tx.supportMessage.findUnique.mockResolvedValue(message());

    const result = await service.sendRequesterText(
      { id: 'requester-1', role: 'USER' },
      { clientMessageId: 'client-1', text: 'du lieu bi bo qua' },
    );

    expect(result.idempotent).toBe(true);
    expect(result.message.text).toBe('Xin chao');
    expect(tx.supportMessage.create).not.toHaveBeenCalled();
    expect(tx.domainOutboxEvent.createMany).not.toHaveBeenCalled();
  });

  it('fails resolve when the expected sequence is stale', async () => {
    tx.supportConversation.findUnique.mockResolvedValue(
      conversation({ assigneeId: 'admin-1', lastMessageSequence: 3n }),
    );

    await expect(
      service.resolve(
        { id: 'admin-1', role: 'SUPER_ADMIN' },
        'conversation-1',
        { expectedLastMessageSequence: '2' },
      ),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(tx.supportConversation.update).not.toHaveBeenCalled();
  });

  it('keeps disabled-by-default access fail-closed', async () => {
    process.env.SUPPORT_CHAT_ENABLED = 'false';

    await expect(
      service.getRequesterConversation(
        { id: 'requester-1', role: 'USER' },
        { limit: 30 },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects oversized text before opening a transaction', async () => {
    await expect(
      service.sendRequesterText(
        { id: 'requester-1', role: 'USER' },
        { clientMessageId: 'client-1', text: 'a'.repeat(16 * 1024 + 1) },
      ),
    ).rejects.toThrow('4.000 ký tự');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('orders unassigned oldest-first and resolved by latest resolution', async () => {
    await service.listAdminConversations(
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      { bucket: 'UNASSIGNED', limit: 30 },
    );
    expect(prisma.supportConversation.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({
        orderBy: [{ unassignedSince: 'asc' }, { id: 'asc' }],
      }),
    );

    await service.listAdminConversations(
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      { bucket: 'RESOLVED', limit: 30 },
    );
    expect(prisma.supportConversation.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({
        orderBy: [{ resolvedAt: 'desc' }, { id: 'desc' }],
      }),
    );
  });
});
