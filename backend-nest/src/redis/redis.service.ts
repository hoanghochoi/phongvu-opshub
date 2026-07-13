import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  Logger,
} from '@nestjs/common';
import Redis from 'ioredis';
import type { RedisOptions } from 'ioredis';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { safeLogError } from '../common/log-sanitizer';

type RedisEnv = Record<string, string | undefined>;

export function redisConnectionOptions(
  env: RedisEnv = process.env,
): RedisOptions {
  const tlsEnabled = env.REDIS_TLS?.trim().toLowerCase() === 'true';
  const tlsCaFile = env.REDIS_TLS_CA_FILE?.trim();
  return {
    host: env.REDIS_HOST?.trim() || 'localhost',
    port: Number(env.REDIS_PORT) || 6379,
    ...(env.REDIS_USERNAME?.trim()
      ? { username: env.REDIS_USERNAME.trim() }
      : {}),
    ...(env.REDIS_PASSWORD ? { password: env.REDIS_PASSWORD } : {}),
    ...(tlsEnabled
      ? {
          tls: {
            rejectUnauthorized:
              env.REDIS_TLS_REJECT_UNAUTHORIZED?.trim().toLowerCase() !==
              'false',
            ...(env.REDIS_TLS_SERVERNAME?.trim()
              ? { servername: env.REDIS_TLS_SERVERNAME.trim() }
              : {}),
            ...(tlsCaFile
              ? { ca: readFileSync(tlsCaFile, { encoding: 'utf8' }) }
              : {}),
          },
        }
      : {}),
  };
}

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private redisClient: Redis;
  private readonly logger = new Logger(RedisService.name);

  onModuleInit() {
    this.redisClient = new Redis(redisConnectionOptions());

    this.redisClient.on('connect', () => {
      this.logger.log('Connected to Redis');
    });

    this.redisClient.on('error', (err) => {
      this.logger.error(`Redis connection error: ${this.safeError(err)}`);
    });
  }

  async onModuleDestroy() {
    if (this.redisClient) await this.redisClient.quit();
  }

  async publishMessage(channel: string, message: any) {
    try {
      await this.publishMessageOrThrow(channel, message);
    } catch (error) {
      this.logger.error(
        `Redis publish failed: channel=${channel} error=${safeLogError(error)}`,
      );
    }
  }

  async publishMessageOrThrow(channel: string, message: any) {
    await this.redisClient.publish(channel, JSON.stringify(message));
    this.logger.log(`Message published to channel: ${channel}`);
  }

  async setJsonWithTtl(key: string, value: unknown, ttlSeconds: number) {
    const normalizedKey = key.trim();
    if (!normalizedKey || normalizedKey.length > 240) {
      throw new Error('Redis key must contain between 1 and 240 characters');
    }
    if (
      !Number.isInteger(ttlSeconds) ||
      ttlSeconds < 1 ||
      ttlSeconds > 86_400
    ) {
      throw new Error('Redis TTL must contain between 1 and 86400 seconds');
    }
    await this.redisClient.set(
      normalizedKey,
      JSON.stringify(value),
      'EX',
      ttlSeconds,
    );
  }

  async tryAcquireLease(key: string, ttlMs: number) {
    const token = randomUUID();
    const result = await this.redisClient.set(
      key,
      token,
      'PX',
      Math.max(1000, ttlMs),
      'NX',
    );
    return result === 'OK' ? token : null;
  }

  async releaseLease(key: string, token: string) {
    await this.redisClient.eval(
      "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end",
      1,
      key,
      token,
    );
  }

  private safeError(error: unknown) {
    return safeLogError(error);
  }
}
