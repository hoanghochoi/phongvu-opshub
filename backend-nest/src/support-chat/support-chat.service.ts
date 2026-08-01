import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';
import { safeLogError } from '../common/log-sanitizer';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import {
  PRIVATE_MEDIA_OWNER,
  PrivateMediaService,
} from '../upload/private-media.service';
import {
  SUPPORT_CHAT_IMAGE_AGGREGATE_MAX_BYTES,
  SUPPORT_CHAT_IMAGE_MAX_BYTES,
  SUPPORT_CHAT_IMAGE_MAX_FILES,
} from '../upload/image-upload.options';
import {
  ListSupportConversationsQueryDto,
  ResolveSupportConversationDto,
  SendSupportImageMessageDto,
  SendSupportTextMessageDto,
  SupportMessagePageQueryDto,
} from './support-chat.dto';
import { isSupportChatEnabled } from './support-chat.config';

const SUPPORT_CHAT_EVENT = 'SUPPORT_CHAT_UPDATED';
const SUPPORT_CHAT_AGGREGATE = 'SUPPORT_CONVERSATION';
const SUPPORT_CHAT_RETENTION_DAYS = 180;

type Principal = { id?: unknown; role?: unknown };
type AppendInput = {
  actorId: string;
  actorRole: 'REQUESTER' | 'SUPER_ADMIN';
  conversationId?: string;
  requesterId?: string;
  clientMessageId: string;
  contentType: 'TEXT' | 'IMAGE';
  text?: string;
  mediaIds?: string[];
  messageId?: string;
};

@Injectable()
export class SupportChatService {
  private readonly logger = new Logger(SupportChatService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly privateMedia: PrivateMediaService,
  ) {}

  isEnabled() {
    return isSupportChatEnabled();
  }

  async getRequesterConversation(
    principal: Principal,
    query: SupportMessagePageQueryDto,
  ) {
    return this.logged('requester_history', principal, async () => {
      this.requireEnabled();
      const requesterId = this.principalId(principal);
      const conversation = await this.prisma.supportConversation.findUnique({
        where: { requesterId },
        include: this.conversationInclude(),
      });
      if (!conversation) {
        return { conversation: null, messages: [], hasMore: false };
      }
      return this.conversationPage(conversation, query);
    });
  }

  async sendRequesterText(
    principal: Principal,
    body: SendSupportTextMessageDto,
  ) {
    return this.logged('requester_text_send', principal, async () => {
      this.requireEnabled();
      const requesterId = this.principalId(principal);
      const text = this.validText(body.text);
      return this.appendMessage({
        actorId: requesterId,
        actorRole: 'REQUESTER',
        requesterId,
        clientMessageId: body.clientMessageId,
        contentType: 'TEXT',
        text,
      });
    });
  }

  assertImageUploadAllowed(principal: Principal, admin: boolean) {
    this.requireEnabled();
    if (admin) this.requireSuperAdmin(principal);
    else this.principalId(principal);
  }

  async sendRequesterImages(
    principal: Principal,
    body: SendSupportImageMessageDto,
    files: Express.Multer.File[],
  ) {
    return this.logged('requester_image_send', principal, async () => {
      this.requireEnabled();
      const requesterId = this.principalId(principal);
      const existingConversation =
        await this.prisma.supportConversation.findUnique({
          where: { requesterId },
          select: { id: true },
        });
      return this.sendImages({
        principal,
        files,
        clientMessageId: body.clientMessageId,
        requesterId,
        conversationId: existingConversation?.id,
        actorRole: 'REQUESTER',
      });
    });
  }

  async markRequesterRead(principal: Principal) {
    return this.logged('requester_read', principal, async () => {
      this.requireEnabled();
      const requesterId = this.principalId(principal);
      const conversation = await this.prisma.supportConversation.findUnique({
        where: { requesterId },
        select: { id: true },
      });
      if (!conversation) return { conversation: null };
      return this.markRead(principal, conversation.id, false);
    });
  }

  async listAdminConversations(
    principal: Principal,
    query: ListSupportConversationsQueryDto,
  ) {
    return this.logged('admin_inbox_list', principal, async () => {
      this.requireEnabled();
      const adminId = this.requireSuperAdmin(principal);
      const cursor = query.cursor ? this.decodeCursor(query.cursor) : null;
      const search = query.query?.trim();
      const bucketWhere: Prisma.SupportConversationWhereInput =
        query.bucket === 'UNASSIGNED'
          ? { status: 'OPEN', assigneeId: null }
          : query.bucket === 'MINE'
            ? { status: 'OPEN', assigneeId: adminId }
            : query.bucket === 'ACTIVE'
              ? { status: 'OPEN', assigneeId: { not: null } }
              : { status: 'RESOLVED' };
      const rows = await this.prisma.supportConversation.findMany({
        where: {
          ...bucketWhere,
          ...(search
            ? {
                requester: {
                  OR: [
                    { firstName: { contains: search, mode: 'insensitive' } },
                    { lastName: { contains: search, mode: 'insensitive' } },
                    { email: { contains: search, mode: 'insensitive' } },
                  ],
                },
              }
            : {}),
          ...(cursor ? this.queueCursorWhere(query.bucket, cursor) : {}),
        },
        orderBy: this.queueOrderBy(query.bucket),
        take: query.limit + 1,
        include: {
          requester: { select: { id: true, firstName: true, lastName: true } },
          assignee: { select: { id: true, firstName: true, lastName: true } },
          messages: { orderBy: { sequence: 'desc' }, take: 1 },
          readReceipts: { where: { readerId: adminId }, take: 1 },
        },
      });
      const hasMore = rows.length > query.limit;
      const items = rows.slice(0, query.limit);
      const last = items.at(-1);
      return {
        bucket: query.bucket,
        items: items.map((row) => this.serializeConversation(row, false)),
        nextCursor:
          hasMore && last
            ? this.encodeCursor(this.queueSortAt(query.bucket, last), last.id)
            : null,
        hasMore,
      };
    });
  }

  async getAdminConversation(
    principal: Principal,
    conversationId: string,
    query: SupportMessagePageQueryDto,
  ) {
    return this.logged(
      'admin_thread_load',
      principal,
      async () => {
        this.requireEnabled();
        this.requireSuperAdmin(principal);
        const conversation = await this.prisma.supportConversation.findUnique({
          where: { id: conversationId },
          include: this.conversationInclude(),
        });
        if (!conversation) throw this.notFound();
        return this.conversationPage(conversation, query);
      },
      conversationId,
    );
  }

  claim(principal: Principal, conversationId: string) {
    return this.mutateAssignment(principal, conversationId, 'CLAIM');
  }

  release(principal: Principal, conversationId: string) {
    return this.mutateAssignment(principal, conversationId, 'RELEASE');
  }

  takeover(principal: Principal, conversationId: string) {
    return this.mutateAssignment(principal, conversationId, 'TAKEOVER');
  }

  async resolve(
    principal: Principal,
    conversationId: string,
    body: ResolveSupportConversationDto,
  ) {
    return this.logged(
      'admin_resolve',
      principal,
      async () => {
        this.requireEnabled();
        const adminId = this.requireSuperAdmin(principal);
        const expectedSequence = BigInt(body.expectedLastMessageSequence);
        return this.prisma.$transaction(async (tx) => {
          const conversation = await this.lockConversation(tx, conversationId);
          if (!conversation) throw this.notFound();
          if (conversation.assigneeId !== adminId) {
            throw new ForbiddenException(
              'Bạn cần tiếp nhận cuộc trò chuyện trước khi đánh dấu đã xử lý.',
            );
          }
          if (conversation.lastMessageSequence !== expectedSequence) {
            throw new ConflictException(
              'Cuộc trò chuyện vừa có tin nhắn mới. Vui lòng tải lại rồi thử lại.',
            );
          }
          if (conversation.status === 'RESOLVED') {
            return this.loadConversation(tx, conversationId);
          }
          const revision = conversation.revision + 1n;
          await tx.supportConversation.update({
            where: { id: conversationId },
            data: {
              status: 'RESOLVED',
              resolvedAt: new Date(),
              unassignedSince: null,
              revision,
            },
          });
          await this.audit(tx, {
            conversationId,
            actorId: adminId,
            action: 'RESOLVED',
            previousStatus: conversation.status,
            nextStatus: 'RESOLVED',
            messageSequence: conversation.lastMessageSequence,
          });
          await this.enqueueInvalidations(tx, conversation, {
            revision,
            changeType: 'RESOLVED',
            currentAssigneeId: adminId,
          });
          return this.loadConversation(tx, conversationId);
        });
      },
      conversationId,
    );
  }

  markAdminRead(principal: Principal, conversationId: string) {
    return this.markRead(principal, conversationId, true);
  }

  async sendAdminText(
    principal: Principal,
    conversationId: string,
    body: SendSupportTextMessageDto,
  ) {
    return this.logged(
      'admin_text_send',
      principal,
      async () => {
        this.requireEnabled();
        const adminId = this.requireSuperAdmin(principal);
        return this.appendMessage({
          actorId: adminId,
          actorRole: 'SUPER_ADMIN',
          conversationId,
          clientMessageId: body.clientMessageId,
          contentType: 'TEXT',
          text: this.validText(body.text),
        });
      },
      conversationId,
    );
  }

  async sendAdminImages(
    principal: Principal,
    conversationId: string,
    body: SendSupportImageMessageDto,
    files: Express.Multer.File[],
  ) {
    return this.logged(
      'admin_image_send',
      principal,
      async () => {
        this.requireEnabled();
        this.requireSuperAdmin(principal);
        return this.sendImages({
          principal,
          files,
          clientMessageId: body.clientMessageId,
          conversationId,
          actorRole: 'SUPER_ADMIN',
        });
      },
      conversationId,
    );
  }

  async notificationSummary(principal: Principal) {
    if (!this.isEnabled()) return null;
    const userId = this.principalId(principal);
    if (isSuperAdminRole(principal.role)) {
      const [counts] = await this.prisma.$queryRaw<
        Array<{ unread: bigint; unassigned: bigint }>
      >`
        SELECT
          COUNT(*) FILTER (
            WHERE conversation.status = 'OPEN'
              AND (conversation."assigneeId" IS NULL OR conversation."assigneeId" = ${userId})
              AND EXISTS (
              SELECT 1 FROM "SupportMessage" message
              WHERE message."conversationId" = conversation.id
                AND message."senderId" IS DISTINCT FROM ${userId}
                AND message.sequence > COALESCE(receipt."lastReadSequence", 0)
            )
          )::bigint AS unread,
          COUNT(*) FILTER (
            WHERE conversation.status = 'OPEN' AND conversation."assigneeId" IS NULL
          )::bigint AS unassigned
        FROM "SupportConversation" conversation
        LEFT JOIN "SupportReadReceipt" receipt
          ON receipt."conversationId" = conversation.id
         AND receipt."readerId" = ${userId}
      `;
      return {
        enabled: true,
        unreadCount: Number(counts?.unread ?? 0n),
        unassignedCount: Number(counts?.unassigned ?? 0n),
      };
    }
    const conversation = await this.prisma.supportConversation.findUnique({
      where: { requesterId: userId },
      include: { readReceipts: { where: { readerId: userId }, take: 1 } },
    });
    if (!conversation) {
      return { enabled: true, unreadCount: 0, conversationId: null };
    }
    const lastRead = conversation.readReceipts[0]?.lastReadSequence ?? 0n;
    const unreadCount = await this.prisma.supportMessage.count({
      where: {
        conversationId: conversation.id,
        senderId: { not: userId },
        sequence: { gt: lastRead },
      },
    });
    return {
      enabled: true,
      unreadCount,
      conversationId: conversation.id,
      status: conversation.status,
    };
  }

  private async sendImages(input: {
    principal: Principal;
    files: Express.Multer.File[];
    clientMessageId: string;
    requesterId?: string;
    conversationId?: string;
    actorRole: 'REQUESTER' | 'SUPER_ADMIN';
  }) {
    const actorId = this.principalId(input.principal);
    if (
      input.files.length < 1 ||
      input.files.length > SUPPORT_CHAT_IMAGE_MAX_FILES
    ) {
      await this.privateMedia.discardTemporaryFiles(input.files);
      throw new BadRequestException('Vui lòng chọn từ 1 đến 4 ảnh để gửi.');
    }
    const existing = input.conversationId
      ? await this.prisma.supportMessage.findUnique({
          where: {
            conversationId_senderId_clientMessageId: {
              conversationId: input.conversationId,
              senderId: actorId,
              clientMessageId: input.clientMessageId,
            },
          },
        })
      : null;
    if (existing) {
      await this.privateMedia.discardTemporaryFiles(input.files);
      return { message: this.serializeMessage(existing), idempotent: true };
    }

    const messageId = randomUUID();
    const urls = await this.privateMedia.saveImages({
      ownerFeature: PRIVATE_MEDIA_OWNER.SUPPORT_CHAT,
      ownerRecordId: messageId,
      uploaderId: actorId,
      files: input.files,
      maxBytesPerFile: SUPPORT_CHAT_IMAGE_MAX_BYTES,
      maxAggregateBytes: SUPPORT_CHAT_IMAGE_AGGREGATE_MAX_BYTES,
      retainOriginalName: false,
    });
    const mediaIds = urls.map((url) => this.mediaId(url));
    try {
      const result = await this.appendMessage({
        actorId,
        actorRole: input.actorRole,
        conversationId: input.conversationId,
        requesterId: input.requesterId,
        clientMessageId: input.clientMessageId,
        contentType: 'IMAGE',
        mediaIds,
        messageId,
      });
      if (result.idempotent) await this.privateMedia.discardUrls(urls);
      return result;
    } catch (error) {
      await this.privateMedia.discardUrls(urls);
      throw error;
    }
  }

  private async appendMessage(input: AppendInput) {
    return this.prisma.$transaction(async (tx) => {
      let conversationId = input.conversationId;
      if (!conversationId) {
        if (!input.requesterId) throw this.notFound();
        const created = await tx.supportConversation.upsert({
          where: { requesterId: input.requesterId },
          update: {},
          create: {
            requesterId: input.requesterId,
            unassignedSince: new Date(),
          },
          select: { id: true },
        });
        conversationId = created.id;
      }
      const conversation = await this.lockConversation(tx, conversationId);
      if (!conversation) throw this.notFound();
      if (
        input.actorRole === 'REQUESTER' &&
        conversation.requesterId !== input.actorId
      ) {
        throw this.notFound();
      }
      if (
        input.actorRole === 'SUPER_ADMIN' &&
        conversation.assigneeId !== input.actorId
      ) {
        throw new ForbiddenException(
          'Bạn cần tiếp nhận cuộc trò chuyện trước khi gửi phản hồi.',
        );
      }
      const existing = await tx.supportMessage.findUnique({
        where: {
          conversationId_senderId_clientMessageId: {
            conversationId,
            senderId: input.actorId,
            clientMessageId: input.clientMessageId,
          },
        },
      });
      if (existing) {
        this.logger.log(
          `Support chat idempotent retry: conversationIdHash=${this.logId(conversationId)} actorIdHash=${this.logId(input.actorId)}`,
        );
        return { message: this.serializeMessage(existing), idempotent: true };
      }

      const sequence = conversation.lastMessageSequence + 1n;
      const reopening =
        input.actorRole === 'REQUESTER' && conversation.status === 'RESOLVED';
      const previousAssigneeId = conversation.assigneeId;
      const revision = conversation.revision + 1n;
      const message = await tx.supportMessage.create({
        data: {
          id: input.messageId,
          conversationId,
          senderId: input.actorId,
          senderRole: input.actorRole,
          sequence,
          clientMessageId: input.clientMessageId,
          contentType: input.contentType,
          text: input.text,
          mediaIds: input.mediaIds ?? [],
        },
      });
      await tx.supportConversation.update({
        where: { id: conversationId },
        data: {
          lastMessageSequence: sequence,
          lastMessageAt: message.createdAt,
          revision,
          ...(reopening
            ? {
                status: 'OPEN',
                assigneeId: null,
                unassignedSince: new Date(),
                resolvedAt: null,
              }
            : {}),
        },
      });
      await this.audit(tx, {
        conversationId,
        actorId: input.actorId,
        action: reopening ? 'REOPENED_BY_REQUESTER' : 'MESSAGE_SENT',
        previousAssigneeId: reopening ? previousAssigneeId : undefined,
        nextAssigneeId: reopening ? null : undefined,
        previousStatus: reopening ? conversation.status : undefined,
        nextStatus: reopening ? 'OPEN' : undefined,
        messageSequence: sequence,
      });
      await this.enqueueInvalidations(tx, conversation, {
        revision,
        lastSequence: sequence,
        changeType: reopening ? 'REOPENED' : 'MESSAGE_CREATED',
        currentAssigneeId: reopening ? null : conversation.assigneeId,
      });
      if (reopening) {
        this.logger.log(
          `Support chat reopened by requester: conversationIdHash=${this.logId(conversationId)} revision=${revision}`,
        );
      }
      return { message: this.serializeMessage(message), idempotent: false };
    });
  }

  private async mutateAssignment(
    principal: Principal,
    conversationId: string,
    operation: 'CLAIM' | 'RELEASE' | 'TAKEOVER',
  ) {
    return this.logged(
      `admin_${operation.toLowerCase()}`,
      principal,
      async () => {
        this.requireEnabled();
        const adminId = this.requireSuperAdmin(principal);
        return this.prisma.$transaction(async (tx) => {
          const conversation = await this.lockConversation(tx, conversationId);
          if (!conversation) throw this.notFound();
          if (conversation.status !== 'OPEN') {
            throw new ConflictException(
              'Cuộc trò chuyện đã được xử lý. Vui lòng tải lại danh sách.',
            );
          }
          const previousAssigneeId = conversation.assigneeId;
          let nextAssigneeId: string | null;
          if (operation === 'CLAIM') {
            if (previousAssigneeId === adminId) {
              return this.loadConversation(tx, conversationId);
            }
            if (previousAssigneeId) {
              throw new ConflictException(
                'Cuộc trò chuyện đã được người khác tiếp nhận. Vui lòng tải lại danh sách.',
              );
            }
            const claimed = await tx.supportConversation.updateMany({
              where: { id: conversationId, status: 'OPEN', assigneeId: null },
              data: { assigneeId: adminId },
            });
            if (claimed.count !== 1) {
              throw new ConflictException(
                'Cuộc trò chuyện vừa được người khác tiếp nhận. Vui lòng tải lại danh sách.',
              );
            }
            nextAssigneeId = adminId;
          } else if (operation === 'RELEASE') {
            if (previousAssigneeId !== adminId) {
              throw new ForbiddenException(
                'Bạn chỉ có thể trả lại cuộc trò chuyện đang do mình phụ trách.',
              );
            }
            nextAssigneeId = null;
          } else {
            if (previousAssigneeId === adminId) {
              return this.loadConversation(tx, conversationId);
            }
            nextAssigneeId = adminId;
          }
          const revision = conversation.revision + 1n;
          await tx.supportConversation.update({
            where: { id: conversationId },
            data: {
              assigneeId: nextAssigneeId,
              unassignedSince: nextAssigneeId === null ? new Date() : null,
              revision,
            },
          });
          await this.audit(tx, {
            conversationId,
            actorId: adminId,
            action:
              operation === 'RELEASE'
                ? 'RELEASED'
                : operation === 'TAKEOVER'
                  ? 'TAKEN_OVER'
                  : 'CLAIMED',
            previousAssigneeId,
            nextAssigneeId,
          });
          await this.enqueueInvalidations(tx, conversation, {
            revision,
            changeType:
              operation === 'RELEASE'
                ? 'RELEASED'
                : operation === 'TAKEOVER'
                  ? 'TAKEN_OVER'
                  : 'CLAIMED',
            currentAssigneeId: nextAssigneeId,
          });
          return this.loadConversation(tx, conversationId);
        });
      },
      conversationId,
    );
  }

  private async markRead(
    principal: Principal,
    conversationId: string,
    admin: boolean,
  ) {
    return this.logged(
      admin ? 'admin_read' : 'requester_read',
      principal,
      async () => {
        this.requireEnabled();
        const readerId = admin
          ? this.requireSuperAdmin(principal)
          : this.principalId(principal);
        return this.prisma.$transaction(async (tx) => {
          const conversation = await this.lockConversation(tx, conversationId);
          if (!conversation) throw this.notFound();
          if (!admin && conversation.requesterId !== readerId) {
            throw this.notFound();
          }
          const receipt = await tx.supportReadReceipt.upsert({
            where: {
              conversationId_readerId: { conversationId, readerId },
            },
            create: {
              conversationId,
              readerId,
              lastReadSequence: conversation.lastMessageSequence,
            },
            update: { lastReadSequence: conversation.lastMessageSequence },
          });
          await this.enqueueThreadInvalidation(tx, conversation, {
            revision: conversation.revision,
            lastSequence: conversation.lastMessageSequence,
            changeType: 'READ_UPDATED',
            currentAssigneeId: conversation.assigneeId,
          });
          return {
            conversationId,
            lastReadSequence: receipt.lastReadSequence.toString(),
          };
        });
      },
      conversationId,
    );
  }

  private async conversationPage(
    conversation: any,
    query: SupportMessagePageQueryDto,
  ) {
    const before = query.beforeSequence ? BigInt(query.beforeSequence) : null;
    const rows = await this.prisma.supportMessage.findMany({
      where: {
        conversationId: conversation.id,
        ...(before !== null ? { sequence: { lt: before } } : {}),
      },
      orderBy: { sequence: 'desc' },
      take: query.limit + 1,
    });
    const hasMore = rows.length > query.limit;
    return {
      conversation: this.serializeConversation(conversation, true),
      messages: rows
        .slice(0, query.limit)
        .reverse()
        .map((message) => this.serializeMessage(message)),
      hasMore,
      nextBeforeSequence:
        hasMore && rows[Math.min(query.limit - 1, rows.length - 1)]
          ? rows[Math.min(query.limit - 1, rows.length - 1)].sequence.toString()
          : null,
    };
  }

  private async lockConversation(
    tx: Prisma.TransactionClient,
    conversationId: string,
  ) {
    const locked = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "SupportConversation" WHERE id = ${conversationId} FOR UPDATE
    `;
    if (locked.length === 0) return null;
    return tx.supportConversation.findUnique({ where: { id: conversationId } });
  }

  private async loadConversation(
    tx: Prisma.TransactionClient,
    conversationId: string,
  ) {
    const conversation = await tx.supportConversation.findUnique({
      where: { id: conversationId },
      include: this.conversationInclude(),
    });
    return conversation ? this.serializeConversation(conversation, true) : null;
  }

  private conversationInclude() {
    return {
      requester: { select: { id: true, firstName: true, lastName: true } },
      assignee: { select: { id: true, firstName: true, lastName: true } },
      readReceipts: {
        select: { readerId: true, lastReadSequence: true, updatedAt: true },
      },
    } as const;
  }

  private async audit(
    tx: Prisma.TransactionClient,
    data: {
      conversationId: string;
      actorId: string;
      action: string;
      previousAssigneeId?: string | null;
      nextAssigneeId?: string | null;
      previousStatus?: string;
      nextStatus?: string;
      messageSequence?: bigint;
    },
  ) {
    await tx.supportAuditEvent.create({ data });
  }

  private async enqueueInvalidations(
    tx: Prisma.TransactionClient,
    conversation: any,
    change: {
      revision: bigint;
      lastSequence?: bigint;
      changeType: string;
      currentAssigneeId?: string | null;
    },
  ) {
    await tx.domainOutboxEvent.createMany({
      data: [
        {
          id: randomUUID(),
          eventType: SUPPORT_CHAT_EVENT,
          aggregateType: SUPPORT_CHAT_AGGREGATE,
          aggregateId: conversation.id,
          dedupeKey: `support-chat:${conversation.id}:${change.revision}:queue`,
          schemaVersion: 1,
          payload: {
            scope: 'QUEUE',
            changeType: change.changeType,
            revision: change.revision.toString(),
          },
        },
        {
          id: randomUUID(),
          eventType: SUPPORT_CHAT_EVENT,
          aggregateType: SUPPORT_CHAT_AGGREGATE,
          aggregateId: conversation.id,
          dedupeKey: `support-chat:${conversation.id}:${change.revision}:thread`,
          schemaVersion: 1,
          payload: {
            scope: 'THREAD',
            conversationId: conversation.id,
            requesterId: conversation.requesterId,
            currentAssigneeId: change.currentAssigneeId ?? null,
            revision: change.revision.toString(),
            lastSequence: (
              change.lastSequence ?? conversation.lastMessageSequence
            ).toString(),
            changeType: change.changeType,
          },
        },
      ],
    });
  }

  private async enqueueThreadInvalidation(
    tx: Prisma.TransactionClient,
    conversation: any,
    change: {
      revision: bigint;
      lastSequence: bigint;
      changeType: string;
      currentAssigneeId: string | null;
    },
  ) {
    await tx.domainOutboxEvent.create({
      data: {
        id: randomUUID(),
        eventType: SUPPORT_CHAT_EVENT,
        aggregateType: SUPPORT_CHAT_AGGREGATE,
        aggregateId: conversation.id,
        schemaVersion: 1,
        payload: {
          scope: 'THREAD',
          conversationId: conversation.id,
          requesterId: conversation.requesterId,
          currentAssigneeId: change.currentAssigneeId,
          revision: change.revision.toString(),
          lastSequence: change.lastSequence.toString(),
          changeType: change.changeType,
        },
      },
    });
  }

  private serializeConversation(conversation: any, includeReceipts: boolean) {
    return {
      id: conversation.id,
      requester: this.person(conversation.requester),
      assignee: this.person(conversation.assignee),
      status: conversation.status,
      revision: conversation.revision.toString(),
      lastMessageSequence: conversation.lastMessageSequence.toString(),
      unassignedSince: conversation.unassignedSince?.toISOString() ?? null,
      lastMessageAt: conversation.lastMessageAt?.toISOString() ?? null,
      resolvedAt: conversation.resolvedAt?.toISOString() ?? null,
      createdAt: conversation.createdAt.toISOString(),
      requesterId:
        conversation.requester?.id ?? conversation.requesterId ?? null,
      requesterDisplayName:
        this.person(conversation.requester)?.displayName ?? null,
      assigneeId: conversation.assignee?.id ?? conversation.assigneeId ?? null,
      ...(includeReceipts
        ? {
            readReceipts: (conversation.readReceipts ?? []).map(
              (receipt: any) => ({
                readerId: receipt.readerId,
                lastReadSequence: receipt.lastReadSequence.toString(),
                updatedAt: receipt.updatedAt.toISOString(),
              }),
            ),
          }
        : {
            lastMessage: conversation.messages?.[0]
              ? this.serializeMessage(conversation.messages[0])
              : null,
            myLastReadSequence: (
              conversation.readReceipts?.[0]?.lastReadSequence ?? 0n
            ).toString(),
            unreadCount: Number(
              conversation.lastMessageSequence -
                (conversation.readReceipts?.[0]?.lastReadSequence ?? 0n),
            ),
          }),
    };
  }

  private serializeMessage(message: any) {
    return {
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      senderRole: message.senderRole,
      senderKind: message.senderRole,
      sequence: message.sequence.toString(),
      clientMessageId: message.clientMessageId,
      contentType: message.contentType,
      type: message.contentType,
      text: message.text,
      media: (message.mediaIds ?? []).map((id: string) => ({
        id,
        url: this.privateMedia.publicUrl(id),
      })),
      attachments: (message.mediaIds ?? []).map((id: string) => ({
        id,
        url: this.privateMedia.publicUrl(id),
      })),
      createdAt: message.createdAt.toISOString(),
    };
  }

  private person(person: any) {
    if (!person) return null;
    return {
      id: person.id,
      displayName:
        [person.lastName, person.firstName].filter(Boolean).join(' ').trim() ||
        'Nhân viên OpsHub',
    };
  }

  private validText(value: string) {
    const text = String(value ?? '');
    const characters = Array.from(text).length;
    const bytes = Buffer.byteLength(text, 'utf8');
    if (!text.trim() || characters > 4_000 || bytes > 16 * 1024) {
      throw new BadRequestException(
        'Tin nhắn cần có nội dung và không dài quá 4.000 ký tự.',
      );
    }
    return text;
  }

  private principalId(principal: Principal) {
    const id = String(principal?.id ?? '').trim();
    if (!id) {
      throw new ForbiddenException(
        'Phiên làm việc không còn hợp lệ. Vui lòng đăng nhập lại.',
      );
    }
    return id;
  }

  private requireSuperAdmin(principal: Principal) {
    const id = this.principalId(principal);
    if (!isSuperAdminRole(principal.role)) {
      throw new ForbiddenException(
        'Bạn không có quyền truy cập hộp thư hỗ trợ nhân viên.',
      );
    }
    return id;
  }

  private requireEnabled() {
    if (!this.isEnabled()) {
      throw new NotFoundException(
        'Hỗ trợ trong ứng dụng chưa sẵn sàng. Vui lòng dùng kênh hỗ trợ hiện tại.',
      );
    }
  }

  private queueOrderBy(bucket: ListSupportConversationsQueryDto['bucket']) {
    if (bucket === 'UNASSIGNED') {
      return [{ unassignedSince: 'asc' as const }, { id: 'asc' as const }];
    }
    if (bucket === 'RESOLVED') {
      return [{ resolvedAt: 'desc' as const }, { id: 'desc' as const }];
    }
    return [{ lastMessageAt: 'desc' as const }, { id: 'desc' as const }];
  }

  private queueSortAt(
    bucket: ListSupportConversationsQueryDto['bucket'],
    conversation: any,
  ) {
    const value =
      bucket === 'UNASSIGNED'
        ? conversation.unassignedSince
        : bucket === 'RESOLVED'
          ? conversation.resolvedAt
          : conversation.lastMessageAt;
    return value ?? conversation.createdAt;
  }

  private queueCursorWhere(
    bucket: ListSupportConversationsQueryDto['bucket'],
    cursor: { sortAt: Date; id: string },
  ): Prisma.SupportConversationWhereInput {
    if (bucket === 'UNASSIGNED') {
      return {
        OR: [
          { unassignedSince: { gt: cursor.sortAt } },
          { unassignedSince: cursor.sortAt, id: { gt: cursor.id } },
        ],
      };
    }
    const field = bucket === 'RESOLVED' ? 'resolvedAt' : 'lastMessageAt';
    return {
      OR: [
        { [field]: { lt: cursor.sortAt } },
        { [field]: cursor.sortAt, id: { lt: cursor.id } },
      ],
    };
  }

  private encodeCursor(sortAt: Date, id: string) {
    return Buffer.from(
      JSON.stringify({ sortAt: sortAt.toISOString(), id }),
      'utf8',
    ).toString('base64url');
  }

  private decodeCursor(value: string) {
    try {
      const parsed = JSON.parse(
        Buffer.from(value, 'base64url').toString('utf8'),
      ) as { sortAt?: unknown; id?: unknown };
      const date = new Date(String(parsed.sortAt ?? ''));
      const id = String(parsed.id ?? '').trim();
      if (Number.isNaN(date.getTime()) || !id) throw new Error('invalid');
      return { sortAt: date, id };
    } catch {
      throw new BadRequestException(
        'Trang danh sách không còn hợp lệ. Vui lòng tải lại.',
      );
    }
  }

  private mediaId(url: string) {
    const id = new URL(url).pathname.split('/').filter(Boolean).at(-1);
    if (!id) throw new Error('Support Chat media id is missing');
    return id;
  }

  private notFound() {
    return new NotFoundException(
      'Không tìm thấy cuộc trò chuyện hoặc bạn không có quyền xem.',
    );
  }

  private async logged<T>(
    operation: string,
    principal: Principal,
    execute: () => Promise<T>,
    conversationId?: string,
  ): Promise<T> {
    const startedAt = Date.now();
    const userIdHash = this.logId(principal?.id);
    const conversation = conversationId
      ? ` conversationIdHash=${this.logId(conversationId)}`
      : '';
    this.logger.log(
      `Support chat started: operation=${operation} userIdHash=${userIdHash}${conversation}`,
    );
    try {
      const result = await execute();
      this.logger.log(
        `Support chat succeeded: operation=${operation} userIdHash=${userIdHash}${conversation} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `Support chat failed: operation=${operation} userIdHash=${userIdHash}${conversation} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }

  private logId(value: unknown) {
    return createHash('sha256')
      .update(String(value ?? 'missing'))
      .digest('hex')
      .slice(0, 12);
  }
}

export const SUPPORT_CHAT_RETENTION_WINDOW_DAYS = SUPPORT_CHAT_RETENTION_DAYS;
