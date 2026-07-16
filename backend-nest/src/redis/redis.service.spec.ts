import { Test, TestingModule } from '@nestjs/testing';
import { RedisService, redisConnectionOptions } from './redis.service';

describe('RedisService', () => {
  let service: RedisService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [RedisService],
    }).compile();

    service = module.get<RedisService>(RedisService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  it('builds authenticated TLS options without logging credentials', () => {
    expect(
      redisConnectionOptions({
        REDIS_HOST: 'redis.internal',
        REDIS_PORT: '6380',
        REDIS_USERNAME: 'opshub-api',
        REDIS_PASSWORD: 'test-password-not-a-real-secret',
        REDIS_TLS: 'true',
        REDIS_TLS_SERVERNAME: 'redis.internal',
      }),
    ).toEqual({
      host: 'redis.internal',
      port: 6380,
      username: 'opshub-api',
      password: 'test-password-not-a-real-secret',
      tls: {
        rejectUnauthorized: true,
        servername: 'redis.internal',
      },
    });
  });

  it('stores JSON with a bounded Redis TTL', async () => {
    const set = jest.fn().mockResolvedValue('OK');
    (service as any).redisClient = { set };

    await service.setJsonWithTtl(
      'realtime:ticket:hash',
      { userId: 'user-1' },
      45,
    );

    expect(set).toHaveBeenCalledWith(
      'realtime:ticket:hash',
      JSON.stringify({ userId: 'user-1' }),
      'EX',
      45,
    );
    await expect(service.setJsonWithTtl('key', {}, 0)).rejects.toThrow(
      'Redis TTL',
    );
  });

  it('reads JSON values without exposing raw Redis payloads to callers', async () => {
    const get = jest
      .fn()
      .mockResolvedValue(JSON.stringify({ userId: 'user-1' }));
    (service as any).redisClient = { get };

    await expect(service.getJson('auth-context:key')).resolves.toEqual({
      userId: 'user-1',
    });
    expect(get).toHaveBeenCalledWith('auth-context:key');
  });
});
