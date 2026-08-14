import { BadGatewayException, Injectable, Logger } from '@nestjs/common';
import {
  HttpResponseTooLargeError,
  readBoundedHttpResponse,
} from '../common/bounded-http-response';

const DEFAULT_PROVIDER_TIMEOUT_MS = 30_000;
const DEFAULT_PROVIDER_RESPONSE_MAX_BYTES = 10 * 1024 * 1024;
const DEFAULT_MAP_RATE_LIMIT_BACKOFF_BASE_MS = 30 * 1000;
const DEFAULT_MAP_RATE_LIMIT_BACKOFF_MAX_MS = 2 * 60 * 1000;
const DEFAULT_MAP_FORBIDDEN_BACKOFF_MS = 5 * 60 * 1000;
const MAP_PROVIDER_BACKOFF_JITTER_MAX_MS = 5 * 1000;
const MAP_PROVIDER_RETRY_AFTER_MAX_MS = 15 * 60 * 1000;

export type MapSession = {
  accessToken: string;
  merchantId: string;
};

export type EfastSession = {
  username: string;
  cifno: string;
  sessionId: string;
};

export class BankProviderHttpException extends BadGatewayException {
  constructor(
    readonly providerStatus: number,
    providerLabel: string,
    providerMessage: string,
    readonly retryAfterMs?: number,
  ) {
    super(`${providerLabel} trả lỗi ${providerStatus}: ${providerMessage}`);
  }
}

@Injectable()
export class MapVietinProviderRuntime {
  private readonly logger = new Logger(MapVietinProviderRuntime.name);
  private mapProviderBackoffUntilValue = 0;
  private mapProviderBackoffAttemptValue = 0;
  private globalSessionCache?: {
    username: string;
    session: MapSession;
    expiresAt: number;
  };
  private efastSessionCache?: {
    username: string;
    cifno: string;
    session: EfastSession;
    expiresAt: number;
  };

  get mapProviderBackoffUntil() {
    return this.mapProviderBackoffUntilValue;
  }

  get mapProviderBackoffAttempt() {
    return this.mapProviderBackoffAttemptValue;
  }

  isMapProviderBackedOff(now = Date.now()) {
    return this.mapProviderBackoffUntilValue > now;
  }

  resetBackoff() {
    this.mapProviderBackoffAttemptValue = 0;
    this.mapProviderBackoffUntilValue = 0;
  }

  async getGlobalSession(
    username: string,
    ttlSeconds: number,
    forceRefresh: boolean,
    login: () => Promise<MapSession>,
  ) {
    const now = Date.now();
    if (
      !forceRefresh &&
      this.globalSessionCache?.username === username &&
      this.globalSessionCache.expiresAt > now
    ) {
      return this.globalSessionCache.session;
    }

    const session = await login();
    this.globalSessionCache = {
      username,
      session,
      expiresAt: now + ttlSeconds * 1000,
    };
    return session;
  }

  async getEfastSession(
    username: string,
    cifno: string,
    ttlSeconds: number,
    forceRefresh: boolean,
    login: () => Promise<EfastSession>,
  ) {
    const now = Date.now();
    if (
      !forceRefresh &&
      this.efastSessionCache?.username === username &&
      this.efastSessionCache.cifno === cifno &&
      this.efastSessionCache.expiresAt > now
    ) {
      return this.efastSessionCache.session;
    }

    const session = await login();
    this.efastSessionCache = {
      username,
      cifno,
      session,
      expiresAt: now + ttlSeconds * 1000,
    };
    return session;
  }

  async postJson<T>(
    url: string,
    body: Record<string, unknown>,
    headers: Record<string, string>,
    providerLabel = 'MAP',
  ): Promise<T> {
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      this.providerTimeoutMs(),
    );
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        body: JSON.stringify(body),
        redirect: 'manual',
        signal: controller.signal,
      });

      if (response.status >= 300 && response.status < 400) {
        throw new BadGatewayException(
          `${providerLabel} chuyển hướng ngoài dự kiến`,
        );
      }

      let responseBuffer: Buffer;
      try {
        responseBuffer = await readBoundedHttpResponse(
          response,
          this.providerResponseMaxBytes(),
        );
      } catch (error) {
        if (error instanceof HttpResponseTooLargeError) {
          throw new BadGatewayException(
            `${providerLabel} trả dữ liệu vượt giới hạn an toàn`,
          );
        }
        throw error;
      }
      const text = responseBuffer.toString('utf8');
      const json = text ? this.parseJson(text, providerLabel) : {};

      if (!response.ok) {
        throw new BankProviderHttpException(
          response.status,
          providerLabel,
          this.safeProviderMessage(json),
          this.retryAfterMs(response.headers?.get?.('retry-after')),
        );
      }
      return json as T;
    } finally {
      clearTimeout(timeout);
    }
  }

  registerMapProviderBackoff(
    providerStatus: 403 | 429,
    providerRetryAfterMs?: number,
  ) {
    this.mapProviderBackoffAttemptValue += 1;
    const jitterMs = Math.floor(
      Math.random() * (MAP_PROVIDER_BACKOFF_JITTER_MAX_MS + 1),
    );
    let delayMs: number;
    if (providerStatus === 403) {
      delayMs =
        Math.max(
          DEFAULT_MAP_FORBIDDEN_BACKOFF_MS,
          this.readPositiveInt(
            'MAP_VIETIN_FORBIDDEN_BACKOFF_MS',
            DEFAULT_MAP_FORBIDDEN_BACKOFF_MS,
          ),
        ) + jitterMs;
    } else {
      const baseMs = Math.max(
        DEFAULT_MAP_RATE_LIMIT_BACKOFF_BASE_MS,
        this.readPositiveInt(
          'MAP_VIETIN_RATE_LIMIT_BACKOFF_BASE_MS',
          DEFAULT_MAP_RATE_LIMIT_BACKOFF_BASE_MS,
        ),
      );
      const maxMs = Math.max(
        baseMs,
        this.readPositiveInt(
          'MAP_VIETIN_RATE_LIMIT_BACKOFF_MAX_MS',
          DEFAULT_MAP_RATE_LIMIT_BACKOFF_MAX_MS,
        ),
      );
      const exponent = Math.min(this.mapProviderBackoffAttemptValue - 1, 10);
      delayMs = Math.min(maxMs, baseMs * 2 ** exponent) + jitterMs;
    }
    const safeProviderRetryAfterMs = Math.min(
      MAP_PROVIDER_RETRY_AFTER_MAX_MS,
      Math.max(0, providerRetryAfterMs ?? 0),
    );
    delayMs = Math.max(delayMs, safeProviderRetryAfterMs);
    this.mapProviderBackoffUntilValue = Date.now() + delayMs;
    this.logger.warn(
      `MAP provider backoff activated status=${providerStatus} attempt=${this.mapProviderBackoffAttemptValue} delayMs=${delayMs} retryAt=${new Date(this.mapProviderBackoffUntilValue).toISOString()}`,
    );
  }

  clearMapProviderBackoff() {
    if (this.mapProviderBackoffAttemptValue > 0) {
      this.logger.log(
        `MAP provider recovered after backoff attempts=${this.mapProviderBackoffAttemptValue}`,
      );
    }
    this.resetBackoff();
  }

  retryAfterMs(value?: string | null) {
    const normalized = String(value || '').trim();
    if (!normalized) return undefined;
    const seconds = Number(normalized);
    if (Number.isFinite(seconds) && seconds >= 0) {
      return Math.round(seconds * 1000);
    }
    const retryAt = Date.parse(normalized);
    if (!Number.isFinite(retryAt)) return undefined;
    return Math.max(0, retryAt - Date.now());
  }

  private providerTimeoutMs() {
    return this.readPositiveInt(
      'BANK_PROVIDER_TIMEOUT_MS',
      DEFAULT_PROVIDER_TIMEOUT_MS,
    );
  }

  private providerResponseMaxBytes() {
    return this.readPositiveInt(
      'BANK_PROVIDER_RESPONSE_MAX_BYTES',
      DEFAULT_PROVIDER_RESPONSE_MAX_BYTES,
    );
  }

  private readPositiveInt(name: string, fallback: number) {
    const parsed = Number(process.env[name]);
    return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
  }

  private parseJson(text: string, providerLabel = 'MAP') {
    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw new BadGatewayException(
        `${providerLabel} trả dữ liệu không phải JSON`,
      );
    }
  }

  private safeProviderMessage(value: unknown) {
    if (!value || typeof value !== 'object') return 'Không rõ lỗi';
    const record = value as Record<string, unknown>;
    const status =
      record.status && typeof record.status === 'object'
        ? (record.status as Record<string, unknown>)
        : {};
    return String(
      status.message ||
        status.subCode ||
        record.message ||
        record.error_desc ||
        record.error ||
        'Không rõ lỗi',
    ).slice(0, 180);
  }
}
