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
import {
  copyFile,
  link,
  mkdir,
  readFile,
  readdir,
  rename,
  stat,
  unlink,
  utimes,
  writeFile,
} from 'fs/promises';
import { basename, dirname, extname, join, resolve } from 'path';
import { createHash, randomUUID } from 'crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import {
  CreateAppLogDto,
  ListPaymentNotificationsQueryDto,
  PaymentNotificationDeliveryMetricsQueryDto,
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
const DEFAULT_PAYMENT_CUE_GAIN = 0.8;
const DEFAULT_AMOUNT_AUDIO_CACHE_RETENTION_DAYS = 90;
const DEFAULT_DELIVERY_CLAIM_TTL_SECONDS = 120;
const DEFAULT_DELIVERY_METRICS_WINDOW_HOURS = 24;
const DELIVERY_CLAIM_EVENT = 'DELIVERED';
const TERMINAL_DELIVERY_EVENTS = ['PLAYED', 'SILENCED', 'FAILED'];
const PAYMENT_SPEAKER_FORBIDDEN_MESSAGE = 'Không có quyền Đọc loa tiền vào';
const PAYMENT_TTS_PREFIX_TEXT = 'Phong Vũ đã nhận:';

type PaymentTtsAudioMode = 'full_text' | 'amount_only_with_prefix';

type PaymentAmountAudioCacheEntry = {
  cacheKey: string;
  cachePath: string;
  bytes: number;
  mimeType: string;
  source: 'hit' | 'generated' | 'waited';
};

type StoredTransaction = {
  id: string;
  storeCode: string;
  amount: number;
};

type Pcm16Wav = {
  channels: number;
  sampleRate: number;
  byteRate: number;
  blockAlign: number;
  bitsPerSample: number;
  data: Buffer;
};

type PaymentDeliveryMetricTrend = 'up' | 'down' | 'flat' | 'unknown';

type PaymentDeliveryMetricRow = {
  count?: number | bigint | string | null;
  averageMs?: unknown;
};

@Injectable()
export class PaymentNotificationsService {
  private readonly logger = new Logger(PaymentNotificationsService.name);
  private readonly audioDir = resolve(
    process.env.PAYMENT_AUDIO_DIR ||
      join(process.cwd(), 'storage', 'payment-audio'),
  );
  private readonly amountAudioCacheDir = resolve(
    process.env.PAYMENT_AMOUNT_AUDIO_CACHE_DIR ||
      join(this.audioDir, 'amount-cache'),
  );
  private readonly amountAudioCacheInflight = new Map<
    string,
    Promise<PaymentAmountAudioCacheEntry>
  >();
  private readonly cueAudioPath = resolve(
    process.env.PAYMENT_CUE_WAV_PATH ||
      join(__dirname, 'assets', 'payment-cue.wav'),
  );
  private readonly prefixAudioPath = resolve(
    process.env.PAYMENT_PREFIX_WAV_PATH ||
      join(__dirname, 'assets', 'payment-prefix.wav'),
  );
  private readonly cuePrefixAudioPath = resolve(
    process.env.PAYMENT_CUE_PREFIX_WAV_PATH ||
      join(__dirname, 'assets', 'payment-cue-prefix.wav'),
  );

  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
    private policyService: PolicyService,
    private featureService: FeatureService,
  ) {}

  async createForTransaction(transaction: StoredTransaction) {
    if (!transaction.id || !transaction.storeCode || transaction.amount <= 0) {
      return null;
    }

    const existing = await this.prisma.paymentNotification.findUnique({
      where: { transactionId: transaction.id },
    });
    if (existing) return existing;

    const amountText = `${vietnameseAmountWords(transaction.amount)} đồng.`;
    const text = `${PAYMENT_TTS_PREFIX_TEXT} ${amountText}`;
    const audioMode = await this.resolvePaymentTtsAudioMode();
    const ttsText = audioMode === 'amount_only_with_prefix' ? amountText : text;
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

    notification = await this.generateAudio(
      notification.id,
      ttsText,
      audioMode,
    );
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

  async getAudioForUser(
    user: any,
    notificationId: string,
    options: { includeCue?: boolean; rawAmount?: boolean } = {},
  ) {
    const notification = await this.prisma.paymentNotification.findUnique({
      where: { id: notificationId },
    });
    if (!notification) throw new NotFoundException('Không tìm thấy thông báo');
    await this.assertUserCanUsePaymentSpeaker(user, 'audio');
    await this.assertUserCanAccessStore(user, notification.storeCode);
    if (notification.audioStatus !== 'READY' || !notification.audioPath) {
      throw new NotFoundException('Audio chưa sẵn sàng');
    }

    if (options.rawAmount) {
      if (!this.isAmountOnlyAudioPath(notification.audioPath)) {
        this.logger.warn(
          `Payment raw amount audio unavailable for notification=${notificationId}: source audio is not amount-only`,
        );
        throw new BadRequestException('Audio số tiền chưa sẵn sàng');
      }
      return {
        fileName: basename(notification.audioPath),
        mimeType: notification.audioMime || 'audio/wav',
        stream: new StreamableFile(createReadStream(notification.audioPath)),
      };
    }

    if (options.includeCue) {
      const combinedPath = await this.ensureCombinedPaymentAudio(
        notification.audioPath,
        notificationId,
        { includeCue: true },
      );
      return {
        fileName: basename(combinedPath),
        mimeType: 'audio/wav',
        stream: new StreamableFile(createReadStream(combinedPath)),
      };
    }

    if (this.isAmountOnlyAudioPath(notification.audioPath)) {
      const combinedPath = await this.ensureCombinedPaymentAudio(
        notification.audioPath,
        notificationId,
        { includeCue: false },
      );
      return {
        fileName: basename(combinedPath),
        mimeType: 'audio/wav',
        stream: new StreamableFile(createReadStream(combinedPath)),
      };
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
    const deliveryLog = await this.logDeliveryEvent({
      notificationId,
      transactionId: notification.transactionId,
      storeCode: notification.storeCode,
      userId: user?.id,
      clientId: input.clientId,
      event: input.event,
      error: input.error,
    });
    if (input.event === 'PLAYED') {
      await this.logPlaybackAckLatency(
        notification,
        deliveryLog?.createdAt,
        input.clientId,
      );
    }
    return { ok: true };
  }

  async getDeliveryMetrics(
    user: any,
    query: PaymentNotificationDeliveryMetricsQueryDto = {},
  ) {
    this.assertSuperAdmin(user, 'delivery_metrics');
    const startedAt = Date.now();
    const windowHours = this.parseDeliveryMetricWindowHours(query.windowHours);
    const sampledAt = new Date();
    const currentFrom = new Date(
      sampledAt.getTime() - windowHours * 60 * 60 * 1000,
    );
    const previousFrom = new Date(
      currentFrom.getTime() - windowHours * 60 * 60 * 1000,
    );

    this.logger.log(
      `Payment delivery metrics requested user=${this.safeUserLabel(user)} windowHours=${windowHours}`,
    );

    try {
      const [current, previous] = await Promise.all([
        this.readDeliveryMetricBucket(currentFrom, sampledAt),
        this.readDeliveryMetricBucket(previousFrom, currentFrom),
      ]);
      const deltaMs =
        current.averageMs == null || previous.averageMs == null
          ? null
          : current.averageMs - previous.averageMs;
      const deltaPercent =
        deltaMs == null || previous.averageMs == null || previous.averageMs <= 0
          ? null
          : Math.round((deltaMs / previous.averageMs) * 1000) / 10;
      const trend = this.deliveryMetricTrend(
        current.averageMs,
        previous.averageMs,
      );

      this.logger.log(
        `Payment delivery metrics computed user=${this.safeUserLabel(user)} windowHours=${windowHours} currentCount=${current.count} previousCount=${previous.count} currentAverageMs=${current.averageMs ?? 'null'} previousAverageMs=${previous.averageMs ?? 'null'} trend=${trend} durationMs=${Date.now() - startedAt}`,
      );

      return {
        sampledAt: sampledAt.toISOString(),
        windowHours,
        current: {
          ...current,
          from: currentFrom.toISOString(),
          to: sampledAt.toISOString(),
        },
        previous: {
          ...previous,
          from: previousFrom.toISOString(),
          to: currentFrom.toISOString(),
        },
        deltaMs,
        deltaPercent,
        trend,
      };
    } catch (error) {
      this.logger.warn(
        `Payment delivery metrics failed user=${this.safeUserLabel(user)} windowHours=${windowHours} durationMs=${Date.now() - startedAt}: ${this.safeError(error)}`,
      );
      throw error;
    }
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
        await this.deleteCombinedPaymentAudioFiles(notification.audioPath);
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
    await this.pruneAmountAudioCache();

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

  private async generateAudio(
    notificationId: string,
    text: string,
    audioMode: PaymentTtsAudioMode,
  ) {
    if (audioMode === 'amount_only_with_prefix') {
      return this.generateAmountOnlyAudio(notificationId, text);
    }

    const serviceUrl = process.env.TTS_SERVICE_URL?.trim();
    if (!serviceUrl) {
      return this.markAudioFailed(
        notificationId,
        'TTS_SERVICE_URL is not configured',
      );
    }

    const startedAt = Date.now();
    const requestedFormat = 'mp3';
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
            format: requestedFormat,
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
        `${notificationId}-full-${randomUUID()}.${extension}`,
      );
      const buffer = Buffer.from(await response.arrayBuffer());
      await writeFile(audioPath, buffer);
      this.logger.log(
        `Payment notification TTS generated notification=${notificationId} mode=${audioMode} chars=${text.length} bytes=${buffer.length} durationMs=${Date.now() - startedAt} mime=${mimeType}`,
      );

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
      this.logger.warn(
        `Payment notification TTS request failed notification=${notificationId} mode=${audioMode} durationMs=${Date.now() - startedAt}: ${this.safeError(error)}`,
      );
      return this.markAudioFailed(notificationId, this.safeError(error));
    }
  }

  private async generateAmountOnlyAudio(notificationId: string, text: string) {
    const startedAt = Date.now();
    try {
      const cacheEntry = await this.ensureAmountAudioCache(text);
      const materialized = await this.materializeAmountAudioForNotification(
        notificationId,
        cacheEntry,
      );
      this.logger.log(
        `Payment amount audio ready notification=${notificationId} cache=${cacheEntry.source} key=${cacheEntry.cacheKey.slice(0, 12)} bytes=${cacheEntry.bytes} materialize=${materialized.method} durationMs=${Date.now() - startedAt}`,
      );

      return this.prisma.paymentNotification.update({
        where: { id: notificationId },
        data: {
          audioStatus: 'READY',
          audioPath: materialized.audioPath,
          audioMime: cacheEntry.mimeType,
          audioError: null,
        },
      });
    } catch (error) {
      this.logger.warn(
        `Payment amount audio failed notification=${notificationId} durationMs=${Date.now() - startedAt}: ${this.safeError(error)}`,
      );
      return this.markAudioFailed(notificationId, this.safeError(error));
    }
  }

  private async ensureAmountAudioCache(
    text: string,
  ): Promise<PaymentAmountAudioCacheEntry> {
    const descriptor = this.amountAudioCacheDescriptor(text);
    const existing = await this.readAmountAudioCacheFile(descriptor);
    if (existing) return { ...existing, source: 'hit' };

    const inflight = this.amountAudioCacheInflight.get(descriptor.cacheKey);
    if (inflight) {
      const entry = await inflight;
      return { ...entry, source: 'waited' };
    }

    const promise = this.generateAmountAudioCache(text, descriptor);
    this.amountAudioCacheInflight.set(descriptor.cacheKey, promise);
    try {
      return await promise;
    } finally {
      if (this.amountAudioCacheInflight.get(descriptor.cacheKey) === promise) {
        this.amountAudioCacheInflight.delete(descriptor.cacheKey);
      }
    }
  }

  private async generateAmountAudioCache(
    text: string,
    descriptor: ReturnType<
      PaymentNotificationsService['amountAudioCacheDescriptor']
    >,
  ): Promise<PaymentAmountAudioCacheEntry> {
    const serviceUrl = process.env.TTS_SERVICE_URL?.trim();
    if (!serviceUrl) {
      throw new Error('TTS_SERVICE_URL is not configured');
    }

    const startedAt = Date.now();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.ttsTimeoutMs());
    const response = await fetch(
      `${serviceUrl.replace(/\/$/, '')}/synthesize`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text,
          format: descriptor.format,
          voice_id: descriptor.voiceId,
          speed: descriptor.speed,
          pitch: descriptor.pitch,
        }),
        signal: controller.signal,
      },
    ).finally(() => clearTimeout(timeout));

    if (!response.ok) {
      throw new Error(`TTS returned HTTP ${response.status}`);
    }

    const mimeType = response.headers.get('content-type') || 'audio/wav';
    if (!mimeType.includes('wav')) {
      throw new Error(
        'PAYMENT_TTS_AUDIO_MODE=amount_only_with_prefix requires audio/wav from TTS',
      );
    }

    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length === 0) {
      throw new Error('TTS returned empty audio');
    }

    await mkdir(this.amountAudioCacheDir, { recursive: true });
    const tmpPath = `${descriptor.cachePath}.${process.pid}.${randomUUID()}.tmp`;
    await writeFile(tmpPath, buffer);
    let source: PaymentAmountAudioCacheEntry['source'] = 'generated';
    await rename(tmpPath, descriptor.cachePath).catch(async (error: any) => {
      await unlink(tmpPath).catch(() => undefined);
      if (await this.fileExists(descriptor.cachePath)) {
        source = 'waited';
        return;
      }
      throw error;
    });

    const entry =
      (await this.readAmountAudioCacheFile(descriptor)) ??
      ({
        cacheKey: descriptor.cacheKey,
        cachePath: descriptor.cachePath,
        bytes: buffer.length,
        mimeType: 'audio/wav',
        source,
      } satisfies PaymentAmountAudioCacheEntry);
    this.logger.log(
      `Payment amount TTS cache ${source} key=${descriptor.cacheKey.slice(0, 12)} chars=${text.length} bytes=${entry.bytes} durationMs=${Date.now() - startedAt} mime=${mimeType}`,
    );
    return { ...entry, source };
  }

  private async readAmountAudioCacheFile(
    descriptor: ReturnType<
      PaymentNotificationsService['amountAudioCacheDescriptor']
    >,
  ): Promise<Omit<PaymentAmountAudioCacheEntry, 'source'> | null> {
    const info = await stat(descriptor.cachePath).catch(() => null);
    if (!info?.isFile() || info.size <= 0) return null;
    const now = new Date();
    await utimes(descriptor.cachePath, now, now).catch(() => undefined);
    return {
      cacheKey: descriptor.cacheKey,
      cachePath: descriptor.cachePath,
      bytes: info.size,
      mimeType: 'audio/wav',
    };
  }

  private async materializeAmountAudioForNotification(
    notificationId: string,
    cacheEntry: PaymentAmountAudioCacheEntry,
  ) {
    await mkdir(this.audioDir, { recursive: true });
    const audioPath = join(
      this.audioDir,
      `${notificationId}-amount-only-cache-${cacheEntry.cacheKey.slice(
        0,
        12,
      )}.wav`,
    );
    await unlink(audioPath).catch(() => undefined);
    try {
      await link(cacheEntry.cachePath, audioPath);
      return { audioPath, method: 'hardlink' };
    } catch {
      await copyFile(cacheEntry.cachePath, audioPath);
      return { audioPath, method: 'copy' };
    }
  }

  private amountAudioCacheDescriptor(text: string) {
    const voiceId = this.ttsVoiceId();
    const speed = this.ttsSpeed();
    const pitch = this.ttsPitch();
    const format = 'wav';
    const cacheKey = createHash('sha256')
      .update(
        JSON.stringify({ version: 1, text, format, voiceId, speed, pitch }),
      )
      .digest('hex');
    return {
      cacheKey,
      cachePath: join(this.amountAudioCacheDir, `${cacheKey}.wav`),
      voiceId,
      speed,
      pitch,
      format,
    };
  }

  private async ensureCombinedPaymentAudio(
    audioPath: string,
    notificationId: string,
    options: { includeCue: boolean },
  ) {
    if (extname(audioPath).toLowerCase() !== '.wav') {
      this.logger.warn(
        `Payment combined audio unavailable for notification=${notificationId}: source audio is not wav`,
      );
      throw new BadRequestException(
        'Audio hiện tại chưa hỗ trợ ghép đoạn cố định',
      );
    }

    const includePrefix = this.isAmountOnlyAudioPath(audioPath);
    const cueGain = this.paymentCueGain();
    const combinedPath = this.combinedPaymentAudioPath(audioPath, {
      includeCue: options.includeCue,
      includePrefix,
      cueGain,
    });
    if (await this.fileExists(combinedPath)) {
      this.logger.debug(
        `Payment combined audio cache hit notification=${notificationId} includeCue=${options.includeCue} includePrefix=${includePrefix} cueGain=${cueGain.toFixed(2)}`,
      );
      return combinedPath;
    }

    try {
      const cuePrefixPath =
        options.includeCue &&
        includePrefix &&
        (await this.fileExists(this.cuePrefixAudioPath))
          ? this.cuePrefixAudioPath
          : null;
      const [cueBuffer, prefixBuffer, cuePrefixBuffer, voiceBuffer] =
        await Promise.all([
          options.includeCue && !cuePrefixPath
            ? readFile(this.cueAudioPath)
            : Promise.resolve(null),
          includePrefix && !cuePrefixPath
            ? readFile(this.prefixAudioPath)
            : Promise.resolve(null),
          cuePrefixPath ? readFile(cuePrefixPath) : Promise.resolve(null),
          readFile(audioPath),
        ]);
      const voice = this.parsePcm16Wav(voiceBuffer, 'payment voice');
      let format = voice;
      const chunks: Buffer[] = [];
      let cueDataBytes = 0;
      let prefixDataBytes = 0;
      let cuePrefixDataBytes = 0;
      if (cuePrefixBuffer) {
        const cuePrefix = this.parsePcm16Wav(
          cuePrefixBuffer,
          'payment cue-prefix',
        );
        this.assertCompatibleWav(
          cuePrefix,
          voice,
          'payment cue-prefix',
          'payment voice',
        );
        format = cuePrefix;
        cuePrefixDataBytes = cuePrefix.data.length;
        chunks.push(cuePrefix.data);
      }
      if (cueBuffer) {
        const cue = this.parsePcm16Wav(cueBuffer, 'payment cue');
        this.assertCompatibleWav(cue, voice, 'payment cue', 'payment voice');
        format = cue;
        const adjustedCueData = this.applyPcm16Gain(cue.data, cueGain);
        cueDataBytes = adjustedCueData.length;
        chunks.push(adjustedCueData);
      }
      if (prefixBuffer) {
        const prefix = this.parsePcm16Wav(prefixBuffer, 'payment prefix');
        this.assertCompatibleWav(
          format,
          prefix,
          cueBuffer ? 'payment cue' : 'payment voice',
          'payment prefix',
        );
        prefixDataBytes = prefix.data.length;
        chunks.push(prefix.data);
      }
      chunks.push(voice.data);
      const combined = this.buildPcm16Wav(format, chunks);
      const tmpPath = `${combinedPath}.${process.pid}.${randomUUID()}.tmp`;
      await writeFile(tmpPath, combined);
      await rename(tmpPath, combinedPath).catch(async (error: any) => {
        await unlink(tmpPath).catch(() => undefined);
        if (await this.fileExists(combinedPath)) return;
        throw error;
      });
      this.logger.log(
        `Payment combined audio generated notification=${notificationId} bytes=${combined.length} includeCue=${options.includeCue} includePrefix=${includePrefix} cueGain=${cueGain.toFixed(2)} cueDataBytes=${cueDataBytes} prefixDataBytes=${prefixDataBytes} cuePrefixDataBytes=${cuePrefixDataBytes} voiceDataBytes=${voice.data.length}`,
      );
      return combinedPath;
    } catch (error) {
      const safe = this.safeError(error);
      this.logger.warn(
        `Payment combined audio generation failed notification=${notificationId}: ${safe}`,
      );
      throw new BadRequestException(`Chưa ghép được audio thanh toán: ${safe}`);
    }
  }

  private combinedPaymentAudioPath(
    audioPath: string,
    options: {
      includeCue: boolean;
      includePrefix: boolean;
      cueGain: number;
    },
  ) {
    const extension = extname(audioPath);
    const tags: string[] = [];
    if (options.includeCue) {
      const gainTag = Math.round(options.cueGain * 1000)
        .toString()
        .padStart(4, '0');
      tags.push(`cue-g${gainTag}`);
    }
    if (options.includePrefix) tags.push('prefix');
    const suffix = tags.length > 0 ? tags.join('-') : 'audio';
    return join(
      dirname(audioPath),
      `${basename(audioPath, extension)}-with-${suffix}.wav`,
    );
  }

  private isAmountOnlyAudioPath(audioPath: string) {
    return basename(audioPath).includes('-amount-only-');
  }

  private async deleteCombinedPaymentAudioFiles(audioPath: string) {
    const extension = extname(audioPath);
    const directory = dirname(audioPath);
    const prefix = `${basename(audioPath, extension)}-with-`;
    const entries = await readdir(directory).catch(() => [] as string[]);
    await Promise.all(
      entries
        .filter((entry) => entry.startsWith(prefix) && entry.endsWith('.wav'))
        .map((entry) => unlink(join(directory, entry)).catch(() => undefined)),
    );
  }

  private async pruneAmountAudioCache() {
    const cutoff = this.daysAgo(this.amountAudioCacheRetentionDays()).getTime();
    const entries = await readdir(this.amountAudioCacheDir).catch(
      () => [] as string[],
    );
    await Promise.all(
      entries
        .filter((entry) => entry.endsWith('.wav'))
        .map(async (entry) => {
          const path = join(this.amountAudioCacheDir, entry);
          const info = await stat(path).catch(() => null);
          if (!info?.isFile() || info.mtimeMs >= cutoff) return;
          await unlink(path).catch(() => undefined);
        }),
    );
  }

  private async resolvePaymentTtsAudioMode(): Promise<PaymentTtsAudioMode> {
    const mode = this.paymentTtsAudioMode();
    if (mode !== 'amount_only_with_prefix') return mode;
    if (await this.fileExists(this.prefixAudioPath)) return mode;
    this.logger.warn(
      `Payment amount-only TTS requested but prefix WAV is unavailable path=${this.prefixAudioPath}; falling back to full_text`,
    );
    return 'full_text';
  }

  private paymentTtsAudioMode(): PaymentTtsAudioMode {
    const rawMode = String(process.env.PAYMENT_TTS_AUDIO_MODE || '')
      .trim()
      .toLowerCase();
    const rawFlag = String(process.env.PAYMENT_TTS_AMOUNT_ONLY || '')
      .trim()
      .toLowerCase();
    const amountOnlyModes = new Set([
      'amount_only_with_prefix',
      'amount-only-with-prefix',
      'amount_only',
      'split_prefix',
    ]);
    if (
      amountOnlyModes.has(rawMode) ||
      ['1', 'true', 'yes', 'on'].includes(rawFlag)
    ) {
      return 'amount_only_with_prefix';
    }
    return 'full_text';
  }

  private assertCompatibleWav(
    reference: Pcm16Wav,
    candidate: Pcm16Wav,
    referenceLabel = 'reference',
    candidateLabel = 'candidate',
  ) {
    if (
      reference.channels !== candidate.channels ||
      reference.sampleRate !== candidate.sampleRate ||
      reference.bitsPerSample !== candidate.bitsPerSample ||
      reference.blockAlign !== candidate.blockAlign
    ) {
      throw new Error(
        `${referenceLabel}/${candidateLabel} WAV mismatch ${reference.channels}ch/${reference.sampleRate}Hz/${reference.bitsPerSample}bit vs ${candidate.channels}ch/${candidate.sampleRate}Hz/${candidate.bitsPerSample}bit`,
      );
    }
  }

  private async fileExists(path: string) {
    try {
      const info = await stat(path);
      return info.isFile() && info.size > 0;
    } catch {
      return false;
    }
  }

  private parsePcm16Wav(buffer: Buffer, label: string): Pcm16Wav {
    if (
      buffer.length < 44 ||
      buffer.toString('ascii', 0, 4) !== 'RIFF' ||
      buffer.toString('ascii', 8, 12) !== 'WAVE'
    ) {
      throw new Error(`${label} is not a RIFF/WAVE file`);
    }

    let offset = 12;
    let fmt: {
      audioFormat: number;
      channels: number;
      sampleRate: number;
      byteRate: number;
      blockAlign: number;
      bitsPerSample: number;
    } | null = null;
    let data: Buffer | null = null;

    while (offset + 8 <= buffer.length) {
      const chunkId = buffer.toString('ascii', offset, offset + 4);
      const chunkSize = buffer.readUInt32LE(offset + 4);
      const chunkStart = offset + 8;
      const chunkEnd = chunkStart + chunkSize;
      if (chunkEnd > buffer.length) break;

      if (chunkId === 'fmt ') {
        if (chunkSize < 16) throw new Error(`${label} fmt chunk is invalid`);
        fmt = {
          audioFormat: buffer.readUInt16LE(chunkStart),
          channels: buffer.readUInt16LE(chunkStart + 2),
          sampleRate: buffer.readUInt32LE(chunkStart + 4),
          byteRate: buffer.readUInt32LE(chunkStart + 8),
          blockAlign: buffer.readUInt16LE(chunkStart + 12),
          bitsPerSample: buffer.readUInt16LE(chunkStart + 14),
        };
      } else if (chunkId === 'data') {
        data = buffer.subarray(chunkStart, chunkEnd);
      }

      offset = chunkEnd + (chunkSize % 2);
    }

    if (!fmt) throw new Error(`${label} is missing fmt chunk`);
    if (!data) throw new Error(`${label} is missing data chunk`);
    if (fmt.audioFormat !== 1 || fmt.bitsPerSample !== 16) {
      throw new Error(
        `${label} must be PCM 16-bit WAV; format=${fmt.audioFormat} bits=${fmt.bitsPerSample}`,
      );
    }

    return {
      channels: fmt.channels,
      sampleRate: fmt.sampleRate,
      byteRate: fmt.byteRate,
      blockAlign: fmt.blockAlign,
      bitsPerSample: fmt.bitsPerSample,
      data,
    };
  }

  private buildPcm16Wav(format: Pcm16Wav, chunks: Buffer[]) {
    const dataSize = chunks.reduce((total, chunk) => total + chunk.length, 0);
    const output = Buffer.alloc(44 + dataSize);
    output.write('RIFF', 0, 'ascii');
    output.writeUInt32LE(36 + dataSize, 4);
    output.write('WAVE', 8, 'ascii');
    output.write('fmt ', 12, 'ascii');
    output.writeUInt32LE(16, 16);
    output.writeUInt16LE(1, 20);
    output.writeUInt16LE(format.channels, 22);
    output.writeUInt32LE(format.sampleRate, 24);
    output.writeUInt32LE(format.byteRate, 28);
    output.writeUInt16LE(format.blockAlign, 32);
    output.writeUInt16LE(format.bitsPerSample, 34);
    output.write('data', 36, 'ascii');
    output.writeUInt32LE(dataSize, 40);
    let offset = 44;
    for (const chunk of chunks) {
      chunk.copy(output, offset);
      offset += chunk.length;
    }
    return output;
  }

  private applyPcm16Gain(data: Buffer, gain: number) {
    const output = Buffer.allocUnsafe(data.length);
    for (let offset = 0; offset < data.length; offset += 2) {
      const sample = data.readInt16LE(offset);
      const adjusted = Math.round(sample * gain);
      output.writeInt16LE(Math.max(-32768, Math.min(32767, adjusted)), offset);
    }
    return output;
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

  private async readDeliveryMetricBucket(from: Date, to: Date) {
    const rows = await this.prisma.$queryRaw<PaymentDeliveryMetricRow[]>`
      SELECT
        COUNT(*)::int AS "count",
        AVG(EXTRACT(EPOCH FROM (played."playedAt" - txn."firstSeenAt")) * 1000)::float AS "averageMs"
      FROM (
        SELECT "notificationId", MAX("createdAt") AS "playedAt"
        FROM "PaymentNotificationDeliveryLog"
        WHERE "event" = 'PLAYED'
          AND "createdAt" >= ${from}
          AND "createdAt" < ${to}
        GROUP BY "notificationId"
      ) played
      JOIN "PaymentNotification" note ON note."id" = played."notificationId"
      JOIN "MapVietinTransaction" txn ON txn."id" = note."transactionId"
      WHERE played."playedAt" >= txn."firstSeenAt"
    `;
    const row = rows[0] ?? {};
    return {
      count: this.numberFromUnknown(row.count),
      averageMs: this.roundMetricMs(row.averageMs),
    };
  }

  private deliveryMetricTrend(
    currentAverageMs: number | null,
    previousAverageMs: number | null,
  ): PaymentDeliveryMetricTrend {
    if (currentAverageMs == null || previousAverageMs == null) {
      return 'unknown';
    }
    const deltaMs = currentAverageMs - previousAverageMs;
    if (Math.abs(deltaMs) < 100) return 'flat';
    return deltaMs > 0 ? 'up' : 'down';
  }

  private async logPlaybackAckLatency(
    notification: {
      id: string;
      transactionId: string;
      storeCode: string;
      createdAt?: Date;
    },
    ackAt: Date | undefined,
    clientId?: string,
  ) {
    try {
      const completedAt = ackAt instanceof Date ? ackAt : new Date();
      const transaction = await this.prisma.mapVietinTransaction.findUnique({
        where: { id: notification.transactionId },
        select: { firstSeenAt: true, paidAt: true },
      });
      if (!transaction?.firstSeenAt) {
        this.logger.warn(
          `Payment notification ack latency unavailable notification=${notification.id} transaction=${notification.transactionId} store=${notification.storeCode} client=${clientId ? this.safeClientLabel(clientId) : 'unknown'} reason=missing_transaction_first_seen`,
        );
        return;
      }
      const firstSeenToAckMs = this.durationMs(
        transaction.firstSeenAt,
        completedAt,
      );
      const paidToAckMs = transaction.paidAt
        ? this.durationMs(transaction.paidAt, completedAt)
        : null;
      const notificationToAckMs =
        notification.createdAt instanceof Date
          ? this.durationMs(notification.createdAt, completedAt)
          : null;
      this.logger.log(
        `Payment notification ack completed notification=${notification.id} transaction=${notification.transactionId} store=${notification.storeCode} client=${clientId ? this.safeClientLabel(clientId) : 'unknown'} firstSeenToAckMs=${firstSeenToAckMs} notificationToAckMs=${notificationToAckMs ?? 'null'} paidToAckMs=${paidToAckMs ?? 'null'}`,
      );
    } catch (error) {
      this.logger.warn(
        `Payment notification ack latency log failed notification=${notification.id} transaction=${notification.transactionId} store=${notification.storeCode}: ${this.safeError(error)}`,
      );
    }
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
    return this.prisma.paymentNotificationDeliveryLog.create({
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

  private assertSuperAdmin(user: any, source: string) {
    if (isSuperAdminRole(user?.role)) return;
    this.logger.warn(
      `Payment delivery metrics denied source=${source} user=${this.safeUserLabel(user)} role=${user?.role ?? 'unknown'}`,
    );
    throw new ForbiddenException(
      'Chỉ quản trị viên toàn hệ thống mới xem được tốc độ đọc loa',
    );
  }

  private async assertUserCanUsePaymentSpeaker(user: any, source: string) {
    if (await this.userCanUsePaymentSpeaker(user, source)) return;
    throw new ForbiddenException(PAYMENT_SPEAKER_FORBIDDEN_MESSAGE);
  }

  private async userCanUsePaymentSpeaker(user: any, source: string) {
    const allowed = await this.featureService.canAccessFeature(
      user,
      FEATURE_KEYS.PAYMENT_SPEAKER,
    );
    this.logger.debug(
      `Payment speaker ${allowed ? 'allowed' : 'denied'} source=${source} user=${this.safeUserLabel(user)} feature=${FEATURE_KEYS.PAYMENT_SPEAKER}`,
    );
    return allowed;
  }

  private async assertUserCanAccessStore(user: any, storeCode: string) {
    if (
      await this.policyService.canAccessPolicy(
        user,
        ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
      )
    )
      return;
    const userStoreCodes = await this.userStoreCodes(user);
    if (!userStoreCodes.includes(storeCode)) {
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
    const userStoreCodes = await this.userStoreCodes(user);
    if (normalized) {
      if (!userStoreCodes.includes(normalized)) {
        throw new ForbiddenException('Không có quyền truy cập showroom này');
      }
      return normalized;
    }
    if (userStoreCodes.length !== 1) {
      throw new ForbiddenException('Vui lòng chọn showroom');
    }
    return userStoreCodes[0];
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
    const userStoreCodes = await this.userStoreCodes(user);
    if (normalized && !userStoreCodes.includes(normalized)) {
      throw new ForbiddenException('Không có quyền ghi log showroom này');
    }
    if (normalized) return normalized;
    return userStoreCodes.length === 1 ? userStoreCodes[0] : null;
  }

  private async userStoreCodes(user: any) {
    const storesByCode = new Map<string, string>();
    const pushStoreCode = (value: unknown) => {
      const code = String(value || '')
        .trim()
        .toUpperCase();
      if (code) storesByCode.set(code, code);
    };

    const userModel = (this.prisma as any).user;
    if (user?.id && userModel?.findUnique) {
      const savedUser = await userModel.findUnique({
        where: { id: user.id },
        include: {
          store: { select: { storeId: true } },
          organizationAssignments: {
            where: { isActive: true },
            orderBy: [
              { isPrimary: Prisma.SortOrder.desc },
              { createdAt: Prisma.SortOrder.asc },
            ],
            include: {
              organizationNode: {
                include: organizationNodeStoreTreeInclude(),
              },
            },
          },
        },
      });
      pushStoreCode(savedUser?.store?.storeId);
      for (const assignment of savedUser?.organizationAssignments ?? []) {
        for (const store of storesForOrganizationNodeTree(
          assignment.organizationNode,
        )) {
          pushStoreCode(store.storeId);
        }
      }
    }

    if (storesByCode.size === 0 && user?.storeId) {
      const store = await this.prisma.store.findUnique({
        where: { id: user.storeId },
        select: { storeId: true },
      });
      pushStoreCode(store?.storeId);
    }

    return Array.from(storesByCode.values());
  }

  private audioRetentionDays() {
    return this.readPositiveInt(
      'PAYMENT_AUDIO_RETENTION_DAYS',
      DEFAULT_AUDIO_RETENTION_DAYS,
    );
  }

  private amountAudioCacheRetentionDays() {
    return this.readPositiveInt(
      'PAYMENT_AMOUNT_AUDIO_CACHE_RETENTION_DAYS',
      DEFAULT_AMOUNT_AUDIO_CACHE_RETENTION_DAYS,
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

  private parseDeliveryMetricWindowHours(value?: string) {
    if (value == null || value.trim().length === 0) {
      return DEFAULT_DELIVERY_METRICS_WINDOW_HOURS;
    }
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0 && parsed <= 168) {
      return Math.trunc(parsed);
    }
    throw new BadRequestException('Khoảng thời gian đo không hợp lệ');
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

  private paymentCueGain() {
    const parsed = Number(process.env.PAYMENT_CUE_GAIN);
    if (Number.isFinite(parsed) && parsed >= 0 && parsed <= 1) {
      return parsed;
    }
    return DEFAULT_PAYMENT_CUE_GAIN;
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

  private numberFromUnknown(value: unknown) {
    if (typeof value === 'bigint') return Number(value);
    const parsed = Number(value ?? 0);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private roundMetricMs(value: unknown) {
    if (value == null) return null;
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return null;
    return Math.max(0, Math.round(parsed));
  }

  private durationMs(from: Date, to: Date) {
    return Math.max(0, Math.round(to.getTime() - from.getTime()));
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
