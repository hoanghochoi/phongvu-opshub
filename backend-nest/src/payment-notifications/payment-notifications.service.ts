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
import {
  CreateAppLogDto,
  ListPaymentNotificationsQueryDto,
  PaymentNotificationAckDto,
} from './payment-notifications.dto';
import { vietnameseAmountWords } from './vietnamese-amount-words';

const PAYMENT_NOTIFICATION_CHANNEL = 'PAYMENT_NOTIFICATION_READY';
const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';
const DEFAULT_AUDIO_RETENTION_DAYS = 7;
const DEFAULT_LOG_RETENTION_DAYS = 30;
const DEFAULT_TRANSACTION_RETENTION_DAYS = 90;
const DEFAULT_TTS_VOICE_ID = 'piper:vi-vais1000';
const DEFAULT_TTS_SPEED = 0.98;
const DEFAULT_TTS_PITCH = 1.0;

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
  ) {}

  async createForTransaction(transaction: StoredTransaction) {
    if (!transaction.id || !transaction.storeCode || transaction.amount <= 0) {
      return null;
    }

    const existing = await this.prisma.paymentNotification.findUnique({
      where: { transactionId: transaction.id },
    });
    if (existing) return existing;

    const text = `Phong Vũ đã nhận: ${vietnameseAmountWords(transaction.amount)} đồng`;
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
      throw new ForbiddenException('Thiáº¿u mÃ£ thiáº¿t bá»‹');
    }
    const storeCode = await this.resolveNotificationStore(
      user,
      query.storeCode,
    );
    const limit = Math.min(Math.max(Number(query.limit) || 10, 1), 20);
    const afterCreatedAt = query.afterCreatedAt
      ? this.parseDate(query.afterCreatedAt, 'afterCreatedAt')
      : null;
    const candidates = await this.prisma.paymentNotification.findMany({
      where: {
        storeCode,
        audioStatus: 'READY',
        audioPath: { not: null },
        expiresAt: { gt: new Date() },
        ...(afterCreatedAt ? { createdAt: { gt: afterCreatedAt } } : {}),
      },
      orderBy: { createdAt: 'asc' },
      take: limit * 3,
    });

    const ready: Array<Record<string, unknown>> = [];
    for (const notification of candidates) {
      const played = await this.prisma.paymentNotificationDeliveryLog.findFirst(
        {
          where: {
            notificationId: notification.id,
            clientId,
            event: { in: ['PLAYED', 'SILENCED', 'FAILED'] },
          },
          select: { id: true },
        },
      );
      if (played) continue;
      ready.push({
        notificationId: notification.id,
        transactionId: notification.transactionId,
        storeCode: notification.storeCode,
        amount: notification.amount,
        audioStatus: notification.audioStatus,
        audioUrl: `/payment-notifications/${notification.id}/audio`,
        createdAt: notification.createdAt.toISOString(),
      });
      if (ready.length >= limit) break;
    }

    return { list: ready };
  }

  async getAudioForUser(user: any, notificationId: string) {
    const notification = await this.prisma.paymentNotification.findUnique({
      where: { id: notificationId },
    });
    if (!notification) throw new NotFoundException('Không tìm thấy thông báo');
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

  private async assertUserCanAccessStore(user: any, storeCode: string) {
    if (user?.role === SUPER_ADMIN_ROLE) return;
    const userStoreCode = await this.userStoreCode(user);
    if (!userStoreCode || userStoreCode !== storeCode) {
      throw new ForbiddenException('Không có quyền truy cập showroom này');
    }
  }

  private async resolveNotificationStore(user: any, requested?: string) {
    const normalized = requested?.trim().toUpperCase();
    if (user?.role === SUPER_ADMIN_ROLE) {
      if (!normalized) {
        throw new ForbiddenException('SUPER_ADMIN cáº§n chá»n showroom');
      }
      return normalized;
    }
    const userStoreCode = await this.userStoreCode(user);
    if (!userStoreCode || (normalized && normalized !== userStoreCode)) {
      throw new ForbiddenException(
        'KhÃ´ng cÃ³ quyá»n truy cáº­p showroom nÃ y',
      );
    }
    return userStoreCode;
  }

  private async resolveAllowedLogStore(user: any, requested?: string) {
    const normalized = requested?.trim().toUpperCase();
    if (user?.role === SUPER_ADMIN_ROLE) return normalized || null;
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
      throw new BadRequestException(`${field} khong hop le`);
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
}
