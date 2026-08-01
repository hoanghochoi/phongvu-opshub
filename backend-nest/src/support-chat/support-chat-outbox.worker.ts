import { Injectable, Logger } from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import type { Prisma } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';
import { safeLogError } from '../common/log-sanitizer';
import { buildRealtimeRedisEnvelope } from '../common/realtime-event';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { isSupportChatEnabled } from './support-chat.config';

const SUPPORT_CHAT_CHANNEL = 'SUPPORT_CHAT_UPDATED';
const SUPPORT_CHAT_EVENT = 'SUPPORT_CHAT_UPDATED';
const MAX_ATTEMPTS = 8;
const BATCH_SIZE = 50;
const LEASE_SECONDS = 30;

type ClaimedEvent = {
  id: string;
  aggregateId: string;
  payload: Prisma.JsonValue;
  occurredAt: Date;
  attempts: number;
};

@Injectable()
export class SupportChatOutboxWorker {
  private readonly logger = new Logger(SupportChatOutboxWorker.name);
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  @Interval(1_000)
  async drain() {
    if (this.running || !isSupportChatEnabled()) return;
    this.running = true;
    const startedAt = Date.now();
    const claimToken = randomUUID();
    try {
      const events = await this.prisma.$queryRaw<ClaimedEvent[]>`
        WITH candidates AS (
          SELECT id
          FROM "DomainOutboxEvent"
          WHERE "eventType" = ${SUPPORT_CHAT_EVENT}
            AND "publishedAt" IS NULL
            AND "deadLetteredAt" IS NULL
            AND "availableAt" <= CURRENT_TIMESTAMP
            AND ("leaseExpiresAt" IS NULL OR "leaseExpiresAt" < CURRENT_TIMESTAMP)
          ORDER BY "occurredAt", id
          FOR UPDATE SKIP LOCKED
          LIMIT ${BATCH_SIZE}
        )
        UPDATE "DomainOutboxEvent" event
        SET "claimedAt" = CURRENT_TIMESTAMP,
            "claimToken" = ${claimToken},
            "leaseExpiresAt" = CURRENT_TIMESTAMP + (${LEASE_SECONDS} * INTERVAL '1 second'),
            attempts = attempts + 1,
            "updatedAt" = CURRENT_TIMESTAMP
        FROM candidates
        WHERE event.id = candidates.id
        RETURNING event.id, event."aggregateId", event.payload,
                  event."occurredAt", event.attempts
      `;
      if (events.length === 0) return;
      this.logger.log(
        `Support chat outbox batch started: count=${events.length}`,
      );
      let published = 0;
      let failed = 0;
      for (const event of events) {
        try {
          const envelope = this.envelope(event);
          await this.redis.publishMessageOrThrow(
            SUPPORT_CHAT_CHANNEL,
            envelope,
          );
          await this.prisma.domainOutboxEvent.updateMany({
            where: { id: event.id, claimToken, publishedAt: null },
            data: {
              publishedAt: new Date(),
              claimedAt: null,
              claimToken: null,
              leaseExpiresAt: null,
              lastError: null,
            },
          });
          published += 1;
        } catch (error) {
          failed += 1;
          await this.retryOrDeadLetter(event, claimToken, error);
        }
      }
      this.logger.log(
        `Support chat outbox batch finished: count=${events.length} published=${published} failed=${failed} durationMs=${Date.now() - startedAt}`,
      );
    } catch (error) {
      this.logger.error(
        `Support chat outbox batch failed: durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
    } finally {
      this.running = false;
    }
  }

  private envelope(event: ClaimedEvent) {
    const payload = this.object(event.payload);
    const scope = this.string(payload.scope);
    const changeType = this.string(payload.changeType);
    const revision = this.decimal(payload.revision);
    if (!scope || !changeType || !revision) throw new Error('invalid_payload');

    if (scope === 'QUEUE') {
      return buildRealtimeRedisEnvelope({
        type: 'SUPPORT_CHAT_INVALIDATED',
        eventId: event.id,
        occurredAt: event.occurredAt,
        audience: { roles: ['SUPER_ADMIN'] },
        payload: { scope, changeType, revision },
      });
    }
    if (scope !== 'THREAD') throw new Error('invalid_scope');
    const conversationId = this.string(payload.conversationId);
    const lastSequence = this.decimal(payload.lastSequence);
    const recipients = [payload.requesterId, payload.currentAssigneeId]
      .map((value) => this.string(value))
      .filter((value): value is string => Boolean(value));
    if (
      !conversationId ||
      conversationId !== event.aggregateId ||
      !lastSequence ||
      recipients.length === 0
    ) {
      throw new Error('invalid_thread_payload');
    }
    return buildRealtimeRedisEnvelope({
      type: 'SUPPORT_CHAT_INVALIDATED',
      eventId: event.id,
      occurredAt: event.occurredAt,
      audience: { recipientUserIds: recipients },
      payload: {
        scope,
        conversationId,
        revision,
        lastSequence,
        changeType,
      },
    });
  }

  private async retryOrDeadLetter(
    event: ClaimedEvent,
    claimToken: string,
    error: unknown,
  ) {
    const terminal = event.attempts >= MAX_ATTEMPTS;
    const delaySeconds = Math.min(300, 2 ** Math.min(event.attempts, 8));
    await this.prisma.domainOutboxEvent.updateMany({
      where: { id: event.id, claimToken, publishedAt: null },
      data: {
        claimedAt: null,
        claimToken: null,
        leaseExpiresAt: null,
        lastError: safeLogError(error).slice(0, 240),
        ...(terminal
          ? { deadLetteredAt: new Date() }
          : { availableAt: new Date(Date.now() + delaySeconds * 1_000) }),
      },
    });
    this.logger.warn(
      `Support chat outbox publish failed: eventIdHash=${this.logId(event.id)} attempt=${event.attempts} deadLetter=${terminal} retryDelaySeconds=${terminal ? 0 : delaySeconds} error=${safeLogError(error)}`,
    );
  }

  private object(value: Prisma.JsonValue): Record<string, Prisma.JsonValue> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('invalid_payload');
    }
    return value as Record<string, Prisma.JsonValue>;
  }

  private string(value: unknown) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }

  private decimal(value: unknown) {
    const text = this.string(value);
    return text && /^(0|[1-9][0-9]{0,18})$/.test(text) ? text : null;
  }

  private logId(value: string) {
    return createHash('sha256').update(value).digest('hex').slice(0, 12);
  }
}
