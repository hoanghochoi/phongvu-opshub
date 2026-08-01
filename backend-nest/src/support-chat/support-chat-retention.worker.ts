import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { safeLogError } from '../common/log-sanitizer';
import { PrismaService } from '../prisma/prisma.service';
import {
  PRIVATE_MEDIA_OWNER,
  PrivateMediaService,
} from '../upload/private-media.service';
import { SUPPORT_CHAT_RETENTION_WINDOW_DAYS } from './support-chat.service';

const RETENTION_BATCH = 100;
const RETENTION_LOCK_KEY = 8_604_000_180;

@Injectable()
export class SupportChatRetentionWorker {
  private readonly logger = new Logger(SupportChatRetentionWorker.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly privateMedia: PrivateMediaService,
  ) {}

  @Cron('0 3 * * *', { timeZone: 'Asia/Ho_Chi_Minh' })
  async purgeExpired() {
    const startedAt = Date.now();
    try {
      const result = await this.prisma.$transaction(async (tx) => {
        const [lock] = await tx.$queryRaw<Array<{ acquired: boolean }>>`
          SELECT pg_try_advisory_xact_lock(${RETENTION_LOCK_KEY}) AS acquired
        `;
        if (!lock?.acquired) return null;
        const cutoff = new Date(
          Date.now() -
            SUPPORT_CHAT_RETENTION_WINDOW_DAYS * 24 * 60 * 60 * 1_000,
        );
        const messages = await tx.supportMessage.findMany({
          where: { createdAt: { lt: cutoff } },
          orderBy: { createdAt: 'asc' },
          take: RETENTION_BATCH,
          select: { id: true, mediaIds: true },
        });
        if (messages.length > 0) {
          await tx.supportMessage.deleteMany({
            where: { id: { in: messages.map((message) => message.id) } },
          });
        }
        const audits = await tx.supportAuditEvent.findMany({
          where: { createdAt: { lt: cutoff } },
          orderBy: { createdAt: 'asc' },
          take: RETENTION_BATCH,
          select: { id: true },
        });
        if (audits.length > 0) {
          await tx.supportAuditEvent.deleteMany({
            where: { id: { in: audits.map((audit) => audit.id) } },
          });
        }
        const publishedOutbox = await tx.domainOutboxEvent.findMany({
          where: {
            eventType: 'SUPPORT_CHAT_UPDATED',
            publishedAt: {
              lt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1_000),
            },
          },
          orderBy: { publishedAt: 'asc' },
          take: RETENTION_BATCH,
          select: { id: true },
        });
        if (publishedOutbox.length > 0) {
          await tx.domainOutboxEvent.deleteMany({
            where: { id: { in: publishedOutbox.map((event) => event.id) } },
          });
        }
        const orphanConversations = await tx.supportConversation.findMany({
          where: {
            requesterId: null,
            updatedAt: { lt: cutoff },
            messages: { none: {} },
            auditEvents: { none: {} },
          },
          orderBy: { updatedAt: 'asc' },
          take: RETENTION_BATCH,
          select: { id: true },
        });
        if (orphanConversations.length > 0) {
          await tx.supportConversation.deleteMany({
            where: {
              id: {
                in: orphanConversations.map((conversation) => conversation.id),
              },
            },
          });
        }
        const orphans = await tx.$queryRaw<Array<{ id: string }>>`
          SELECT media.id
          FROM "MediaObject" media
          LEFT JOIN "SupportMessage" message ON message.id = media."ownerRecordId"
          WHERE media."ownerFeature" = ${PRIVATE_MEDIA_OWNER.SUPPORT_CHAT}
            AND media."deletedAt" IS NULL
            AND message.id IS NULL
            AND media."createdAt" < CURRENT_TIMESTAMP - INTERVAL '1 hour'
          ORDER BY media."createdAt"
          LIMIT ${RETENTION_BATCH}
        `;
        return {
          messageCount: messages.length,
          auditCount: audits.length,
          outboxCount: publishedOutbox.length,
          conversationCount: orphanConversations.length,
          mediaIds: [
            ...messages.flatMap((message) => message.mediaIds),
            ...orphans.map((orphan) => orphan.id),
          ],
        };
      });
      if (!result) return null;
      await this.privateMedia.discardUrlsStrict(
        [...new Set(result.mediaIds)].map((id) =>
          this.privateMedia.publicUrl(id),
        ),
      );
      this.logger.log(
        `Support chat retention succeeded: messages=${result.messageCount} audits=${result.auditCount} outbox=${result.outboxCount} conversations=${result.conversationCount} media=${result.mediaIds.length} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `Support chat retention failed: durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }
}
