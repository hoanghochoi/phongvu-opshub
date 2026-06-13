import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  StreamableFile,
} from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import { createReadStream } from 'fs';
import { mkdir, unlink, writeFile } from 'fs/promises';
import { basename, join, resolve } from 'path';
import { randomUUID } from 'crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import {
  CreateAppLogDto,
  ListPaymentNotificationsQueryDto,
  PaymentNotificationAckDto,
} from './payment-notifications.dto';
import { vietnameseAmountWords } from './vietnamese-amount-words';

const PAYMENT_NOTIFICATION_CHANNEL = 'PAYMENT_NOTIFICATION_READY';
const DEFAULT_AUDIO_RETENTION_DAYS = 7;
const DEFAULT_LOG_RETENTION_DAYS = 30;
const DEFAULT_TRANSACTION_RETENTION_DAYS = 90;
const DEFAULT_TTS_VOICE_ID = 'piper:vi-vais1000';
const DEFAULT_TTS_SPEED = 0.9;
const DEFAULT_TTS_PITCH = 1.0;
const DEFAULT_DELIVERY_CLAIM_TTL_SECONDS = 120;
const DELIVERY_CLAIM_EVENT = 'DELIVERED';
const TERMINAL_DELIVERY_EVENTS = ['PLAYED', 'SILENCED', 'FAILED'];
const PAYMENT_SPEAKER_ORG_TYPE = 'LV5_POSITION';
const PAYMENT_SPEAKER_POSITION_CODES = new Set(['STORE_MANAGER', 'CASH']);
const PAYMENT_SPEAKER_FORBIDDEN_MESSAGE =
  'Chỉ vị trí STORE_MANAGER hoặc CASH mới được dùng đọc loa tiền vào';

type StoredTransaction = {
  id: string;
  storeCode: string;
  amount: number;
};

@Injectable()
export class PaymentNotificationsService {
  private readonly logger = new Logger(PaymentNotificationsService.name);
  private readonly audioDir = resolve(
    process.env.PAYMENT_AUDIO_DIR ||
      join(process.cwd(), 'storage', 'payment-audio'),
  );

  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
    private policyService: PolicyService,
  ) {}

  async createForTransaction(transaction: StoredTransaction) {
    if (!transaction.id || !transaction.storeCode || transaction.amount <= 0) {
      return null;
    }

    const existing = await this.prisma.paymentNotification.findUnique({
      where: { transactionId: transaction.id },
    });
    if (existing) return existing;

    const text = `Phong Vũ đã nhận: ${vietnameseAmountWords(transaction.amount)} đồng.`;
    const expiresAt = this.daysFromNow(this.audioRetentionDays());
    let notification = await this.prisma.paymentNotification.create({
      data: {
        storeCode: transaction.storeCode,
        transactionId: transaction.id,
        amount: transaction.amount,
        text,
        audioStatus: 'PENDING',
        expiresAt,
      },
    });

    notification = await this.generateAudio(notification.id, text);
    await this.publishReadyEvent(notification);
    await this.logDeliveryEvent({
      notificationId: notification.id,
      transactionId: notification.transactionId,
      storeCode: notification.storeCode,
      event: `SERVER_${notification.audioStatus}`,
      error: notification.audioError ?? undefined,
    });

    return notification;
  }

  async listReadyForClient(user: any, query: ListPaymentNotificationsQueryDto) {
    const clientId = query.clientId?.trim();
    if (!clientId) {
      throw new ForbiddenException('Thiếu mã thiết bị');
    }
    if (!(await this.userCanUsePaymentSpeaker(user, 'ready'))) {
      return { list: [] };
    }
    const storeCode = await this.resolveNotificationStore(
      user,
      query.storeCode,
    );
    const limit = Math.min(Math.max(Number(query.limit) || 10, 1), 20);
    const afterCreatedAt = query.afterCreatedAt
      ? this.parseDate(query.afterCreatedAt, 'afterCreatedAt')
      : null;
    const claimCutoff = new Date(
      Date.now() - this.deliveryClaimTtlSeconds() * 1000,
    );
    const candidates = await this.prisma.$transaction(async (tx) => {
      await this.lockReadyNotificationClient(tx, clientId, storeCode);
      const blockedDeliveries =
        await tx.paymentNotificationDeliveryLog.findMany({
          where: {
            clientId,
            storeCode,
            ...(afterCreatedAt ? { createdAt: { gt: afterCreatedAt } } : {}),
            OR: [
              { event: { in: TERMINAL_DELIVERY_EVENTS } },
              {
                event: DELIVERY_CLAIM_EVENT,
                createdAt: { gt: claimCutoff },
              },
            ],
          },
          select: { notificationId: true },
          distinct: ['notificationId'],
        });
      const blockedNotificationIds = blockedDeliveries
        .map((row) => row.notificationId)
        .filter(Boolean);

      const readyNotifications = await tx.paymentNotification.findMany({
        where: {
          storeCode,
          audioStatus: 'READY',
          audioPath: { not: null },
          expiresAt: { gt: new Date() },
          ...(afterCreatedAt ? { createdAt: { gt: afterCreatedAt } } : {}),
          ...(blockedNotificationIds.length > 0
            ? { id: { notIn: blockedNotificationIds } }
            : {}),
        },
        orderBy: { createdAt: 'asc' },
        take: limit,
      });

      if (readyNotifications.length > 0) {
        await tx.paymentNotificationDeliveryLog.createMany({
          data: readyNotifications.map((notification) => ({
            notificationId: notification.id,
            transactionId: notification.transactionId,
            storeCode: notification.storeCode,
            clientId,
            event: DELIVERY_CLAIM_EVENT,
          })),
        });
      }

      return {
        readyNotifications,
        blockedCount: blockedNotificationIds.length,
      };
    });

    if (candidates.blockedCount >= limit * 3) {
      this.logger.debug(
        `Payment ready query excluded ${candidates.blockedCount} delivered or terminal notifications for store=${storeCode} client=${this.safeClientLabel(clientId)}`,
      );
    }

    const ready: Array<Record<string, unknown>> =
      candidates.readyNotifications.map((notification) => ({
        notificationId: notification.id,
        transactionId: notification.transactionId,
        storeCode: notification.storeCode,
        amount: notification.amount,
        audioStatus: notification.audioStatus,
        audioUrl: `/payment-notifications/${notification.id}/audio`,
        createdAt: notification.createdAt.toISOString(),
      }));

    return { list: ready };
  }

  async getAudioForUser(user: any, notificationId: string) {
    const notification = await this.prisma.paymentNotification.findUnique({
      where: { id: notificationId },
    });
    if (!notification) throw new NotFoundException('Không tìm thấy thông báo');
    await this.assertUserCanUsePaymentSpeaker(user, 'audio');
    await this.assertUserCanAccessStore(user, notification.storeCode);
    if (notification.audioStatus !== 'READY' || !notification.audioPath) {
      throw new NotFoundException('Audio chưa sẵn sàng');
    }

    return {
      fileName: basename(notification.audioPath),
      mimeType: notification.audioMime || 'audio/mpeg',
      stream: new StreamableFile(createReadStream(notification.audioPath)),
    };
  }

  async acknowledge(
    user: any,
    notificationId: string,
    input: PaymentNotificationAckDto,
  ) {
    const notification = await this.prisma.paymentNotification.findUnique({
      where: { id: notificationId },
    });
    if (!notification) throw new NotFoundException('Không tìm thấy thông báo');
    await this.assertUserCanUsePaymentSpeaker(user, 'ack');
    await this.assertUserCanAccessStore(user, notification.storeCode);
    await this.logDeliveryEvent({
      notificationId,
      transactionId: notification.transactionId,
      storeCode: notification.storeCode,
      userId: user?.id,
      clientId: input.clientId,
      event: input.event,
      error: input.error,
    });
    return { ok: true };
  }

  async createAppLog(user: any, input: CreateAppLogDto) {
    const storeCode = await this.resolveAllowedLogStore(user, input.storeCode);
    await this.prisma.appLog.create({
      data: {
        level: input.level,
        source: input.source,
        message: this.scrub(input.message).slice(0, 1000),
        userId: user?.id,
        clientId: input.clientId,
        storeCode,
        context: input.context
          ? (this.scrubJson(input.context) as Prisma.InputJsonObject)
          : undefined,
      },
    });
    return { ok: true };
  }

  @Interval(60 * 60 * 1000)
  async cleanupExpiredData() {
    const now = new Date();
    const expiredAudio = await this.prisma.paymentNotification.findMany({
      where: {
        expiresAt: { lt: now },
        audioPath: { not: null },
      },
      select: { id: true, audioPath: true },
      take: 200,
    });

    for (const notification of expiredAudio) {
      if (notification.audioPath) {
        await unlink(notification.audioPath).catch(() => undefined);
      }
      await this.prisma.paymentNotification.update({
        where: { id: notification.id },
        data: {
          audioPath: null,
          audioMime: null,
          audioStatus: 'EXPIRED',
        },
      });
    }

    const logCutoff = this.daysAgo(this.logRetentionDays());
    await this.prisma.paymentNotificationDeliveryLog.deleteMany({
      where: { createdAt: { lt: logCutoff } },
    });
    await this.prisma.appLog.deleteMany({
      where: { createdAt: { lt: logCutoff } },
    });

    const transactionCutoff = this.daysAgo(this.transactionRetentionDays());
    await this.prisma.mapVietinTransaction.deleteMany({
      where: { firstSeenAt: { lt: transactionCutoff } },
    });
  }

  private async generateAudio(notificationId: string, text: string) {
    const serviceUrl = process.env.TTS_SERVICE_URL?.trim();
    if (!serviceUrl) {
      return this.markAudioFailed(
        notificationId,
        'TTS_SERVICE_URL is not configured',
      );
    }

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), this.ttsTimeoutMs());
      const response = await fetch(
        `${serviceUrl.replace(/\/$/, '')}/synthesize`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text,
            format: 'mp3',
            voice_id: this.ttsVoiceId(),
            speed: this.ttsSpeed(),
            pitch: this.ttsPitch(),
          }),
          signal: controller.signal,
        },
      ).finally(() => clearTimeout(timeout));

      if (!response.ok) {
        return this.markAudioFailed(
          notificationId,
          `TTS returned HTTP ${response.status}`,
        );
      }

      const mimeType = response.headers.get('content-type') || 'audio/mpeg';
      const extension = mimeType.includes('wav') ? 'wav' : 'mp3';
      await mkdir(this.audioDir, { recursive: true });
      const audioPath = join(
        this.audioDir,
        `${notificationId}-${randomUUID()}.${extension}`,
      );
      const buffer = Buffer.from(await response.arrayBuffer());
      await writeFile(audioPath, buffer);

      return this.prisma.paymentNotification.update({
        where: { id: notificationId },
        data: {
          audioStatus: 'READY',
          audioPath,
          audioMime: mimeType,
          audioError: null,
        },
      });
    } catch (error) {
      return this.markAudioFailed(notificationId, this.safeError(error));
    }
  }

  private async markAudioFailed(notificationId: string, error: string) {
    const safe = this.scrub(error).slice(0, 500);
    this.logger.warn(`Payment notification TTS failed: ${safe}`);
    return this.prisma.paymentNotification.update({
      where: { id: notificationId },
      data: { audioStatus: 'FAILED', audioError: safe },
    });
  }

  private async publishReadyEvent(notification: {
    id: string;
    storeCode: string;
    transactionId: string;
    amount: number;
    audioStatus: string;
  }) {
    const audioUrl =
      notification.audioStatus === 'READY'
        ? `/payment-notifications/${notification.id}/audio`
        : null;
    await this.redisService.publishMessage(PAYMENT_NOTIFICATION_CHANNEL, {
      notificationId: notification.id,
      transactionId: notification.transactionId,
      storeCode: notification.storeCode,
      amount: notification.amount,
      audioStatus: notification.audioStatus,
      audioUrl,
      createdAt: new Date().toISOString(),
    });
  }

  private async logDeliveryEvent(input: {
    notificationId: string;
    transactionId?: string;
    storeCode: string;
    userId?: string;
    clientId?: string;
    event: string;
    error?: string;
  }) {
    await this.prisma.paymentNotificationDeliveryLog.create({
      data: {
        notificationId: input.notificationId,
        transactionId: input.transactionId,
        storeCode: input.storeCode,
        userId: input.userId,
        clientId: input.clientId,
        event: input.event,
        error: input.error ? this.scrub(input.error).slice(0, 500) : undefined,
      },
    });
  }

  private async assertUserCanUsePaymentSpeaker(user: any, source: string) {
    if (await this.userCanUsePaymentSpeaker(user, source)) return;
    throw new ForbiddenException(PAYMENT_SPEAKER_FORBIDDEN_MESSAGE);
  }

  private async userCanUsePaymentSpeaker(user: any, source: string) {
    const organizationNodeId =
      typeof user?.organizationNodeId === 'string'
        ? user.organizationNodeId.trim()
        : '';
    if (!organizationNodeId) {
      this.logger.debug(
        `Payment speaker denied source=${source} user=${this.safeUserLabel(user)} reason=missing_org_node`,
      );
      return false;
    }

    const organizationNode = await this.prisma.organizationNode.findUnique({
      where: { id: organizationNodeId },
      select: {
        id: true,
        type: true,
        businessCode: true,
        code: true,
        isActive: true,
      },
    });
    const positionCode = this.normalizeSpeakerPositionCode(
      organizationNode?.businessCode || organizationNode?.code,
    );
    const allowed =
      organizationNode?.isActive === true &&
      organizationNode.type === PAYMENT_SPEAKER_ORG_TYPE &&
      PAYMENT_SPEAKER_POSITION_CODES.has(positionCode);

    this.logger.debug(
      `Payment speaker ${allowed ? 'allowed' : 'denied'} source=${source} user=${this.safeUserLabel(user)} orgNode=${organizationNode?.id ?? 'none'} type=${organizationNode?.type ?? 'none'} position=${positionCode || 'none'}`,
    );
    return allowed;
  }

  private normalizeSpeakerPositionCode(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase();
  }

  private async assertUserCanAccessStore(user: any, storeCode: string) {
    if (
      await this.policyService.canAccessPolicy(
        user,
        ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
      )
    )
      return;
    const userStoreCode = await this.userStoreCode(user);
    if (!userStoreCode || userStoreCode !== storeCode) {
      throw new ForbiddenException('Không có quyền truy cập showroom này');
    }
  }

  private async resolveNotificationStore(user: any, requested?: string) {
    const normalized = requested?.trim().toUpperCase();
    if (
      await this.policyService.canAccessPolicy(
        user,
        ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
      )
    ) {
      if (!normalized) {
        throw new ForbiddenException('Vui lòng chọn showroom');
      }
      return normalized;
    }
    const userStoreCode = await this.userStoreCode(user);
    if (!userStoreCode || (normalized && normalized !== userStoreCode)) {
      throw new ForbiddenException('Không có quyền truy cập showroom này');
    }
    return userStoreCode;
  }

  private async resolveAllowedLogStore(user: any, requested?: string) {
    const normalized = requested?.trim().toUpperCase();
    if (
      await this.policyService.canAccessPolicy(
        user,
        ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
      )
    )
      return normalized || null;
    const userStoreCode = await this.userStoreCode(user);
    if (normalized && normalized !== userStoreCode) {
      throw new ForbiddenException('Không có quyền ghi log showroom này');
    }
    return normalized || userStoreCode || null;
  }

  private async userStoreCode(user: any) {
    if (!user?.storeId) return null;
    const store = await this.prisma.store.findUnique({
      where: { id: user.storeId },
      select: { storeId: true },
    });
    return store?.storeId ?? null;
  }

  private audioRetentionDays() {
    return this.readPositiveInt(
      'PAYMENT_AUDIO_RETENTION_DAYS',
      DEFAULT_AUDIO_RETENTION_DAYS,
    );
  }

  private logRetentionDays() {
    return this.readPositiveInt(
      'APP_LOG_RETENTION_DAYS',
      DEFAULT_LOG_RETENTION_DAYS,
    );
  }

  private transactionRetentionDays() {
    return this.readPositiveInt(
      'MAP_TRANSACTION_RETENTION_DAYS',
      DEFAULT_TRANSACTION_RETENTION_DAYS,
    );
  }

  private ttsTimeoutMs() {
    return this.readPositiveInt('TTS_TIMEOUT_MS', 20_000);
  }

  private deliveryClaimTtlSeconds() {
    return this.readPositiveInt(
      'PAYMENT_NOTIFICATION_CLAIM_TTL_SECONDS',
      DEFAULT_DELIVERY_CLAIM_TTL_SECONDS,
    );
  }

  private async lockReadyNotificationClient(
    tx: Prisma.TransactionClient,
    clientId: string,
    storeCode: string,
  ) {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${clientId}), hashtext(${storeCode}))`;
  }

  private ttsVoiceId() {
    return process.env.TTS_VOICE_ID?.trim() || DEFAULT_TTS_VOICE_ID;
  }

  private ttsSpeed() {
    return this.readPositiveNumber('TTS_SPEED', DEFAULT_TTS_SPEED);
  }

  private ttsPitch() {
    return this.readPositiveNumber('TTS_PITCH', DEFAULT_TTS_PITCH);
  }

  private readPositiveInt(key: string, fallback: number) {
    const parsed = Number(process.env[key]);
    return Number.isFinite(parsed) && parsed > 0
      ? Math.trunc(parsed)
      : fallback;
  }

  private readPositiveNumber(key: string, fallback: number) {
    const parsed = Number(process.env[key]);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
  }

  private daysFromNow(days: number) {
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  }

  private daysAgo(days: number) {
    return new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  }

  private parseDate(value: string, field: string) {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException(`${field} không hợp lệ`);
    }
    return parsed;
  }

  private scrubJson(value: unknown): unknown {
    if (Array.isArray(value)) return value.map((item) => this.scrubJson(item));
    if (!value || typeof value !== 'object') {
      return typeof value === 'string' ? this.scrub(value) : value;
    }
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, item]) => {
        if (/token|password|secret|authorization/i.test(key)) {
          return [key, '[redacted]'];
        }
        return [key, this.scrubJson(item)];
      }),
    );
  }

  private scrub(value: string) {
    return String(value).replace(
      /(Bearer\s+)[A-Za-z0-9._-]+|("?(?:password|token|secret|authorization)"?\s*[:=]\s*)("[^"]+"|[^\s,}]+)/gi,
      '$1[redacted]',
    );
  }

  private safeError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }

  private safeClientLabel(clientId: string) {
    const normalized = clientId.trim();
    if (normalized.length <= 12) return normalized;
    return `${normalized.slice(0, 8)}...${normalized.slice(-4)}`;
  }

  private safeUserLabel(user: any) {
    const raw = String(user?.id || user?.email || 'unknown').trim();
    if (raw.length <= 16) return raw;
    return `${raw.slice(0, 8)}...${raw.slice(-4)}`;
  }
}
