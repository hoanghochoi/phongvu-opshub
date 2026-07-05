import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  Logger,
} from '@nestjs/common';
import Redis from 'ioredis';
import { randomUUID } from 'node:crypto';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private redisClient: Redis;
  private readonly logger = new Logger(RedisService.name);

  onModuleInit() {
    this.redisClient = new Redis({
      host: process.env.REDIS_HOST || 'localhost',
      port: Number(process.env.REDIS_PORT) || 6379,
    });

    this.redisClient.on('connect', () => {
      this.logger.log('Connected to Redis');
    });

    this.redisClient.on('error', (err) => {
      this.logger.error('Redis connection error', err);
    });
  }

  onModuleDestroy() {
    this.redisClient.quit();
  }

  async publishMessage(channel: string, message: any) {
    try {
      await this.publishMessageOrThrow(channel, message);
    } catch (error) {
      this.logger.error(`Error publishing to channel: ${channel}`, error);
    }
  }

  async publishMessageOrThrow(channel: string, message: any) {
    await this.redisClient.publish(channel, JSON.stringify(message));
    this.logger.log(`Message published to channel: ${channel}`);
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
}
