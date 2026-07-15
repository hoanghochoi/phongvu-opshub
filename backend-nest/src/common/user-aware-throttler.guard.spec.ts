import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { ThrottlerModuleOptions, ThrottlerStorage } from '@nestjs/throttler';
import { createHash } from 'crypto';
import { GLOBAL_API_THROTTLER_OPTIONS } from '../app.module';
import { UserAwareThrottlerGuard } from './user-aware-throttler.guard';

class TestableUserAwareThrottlerGuard extends UserAwareThrottlerGuard {
  principalTrackerFor(req: Record<string, any>) {
    return this.getPrincipalTracker(req);
  }

  throwRateLimitFor(
    context: ExecutionContext,
    detail: Record<string, unknown>,
  ) {
    return this.throwThrottlingException(context, detail as any);
  }

  storageKeyFor(
    req: Record<string, any>,
    suffix = 'principal:user:user-1:ip:trusted-ip-hash',
  ) {
    const context = {
      switchToHttp: () => ({
        getRequest: () => req,
        getResponse: () => ({}),
      }),
    } as unknown as ExecutionContext;
    return this.generateKey(context, suffix, 'principal');
  }
}

describe('UserAwareThrottlerGuard', () => {
  const options: ThrottlerModuleOptions = [{ ttl: 60_000, limit: 120 }];
  const storage = { increment: jest.fn() } as unknown as ThrottlerStorage;
  const jwtService = new JwtService({ secret: 'rate-limit-test-secret' });
  const guard = new TestableUserAwareThrottlerGuard(
    options,
    storage,
    new Reflector(),
    jwtService,
  );
  const trackerHash = (value: string) =>
    createHash('sha256').update(value).digest('hex');
  const emailTracker = (value: string) =>
    `principal:email:${trackerHash(value)}`;
  const userIpTracker = (userId: string, ip: string) =>
    `principal:user:${userId}:ip:${trackerHash(ip)}`;
  const ipTracker = (ip: string) => `principal:ip:${trackerHash(ip)}`;

  it('configures only the principal global bucket', () => {
    expect(GLOBAL_API_THROTTLER_OPTIONS.throttlers).toEqual([
      { name: 'principal', ttl: 60_000, limit: 120 },
    ]);
  });

  it('uses the signed JWT subject and trusted IP so the same user and IP share one bucket', async () => {
    const windowsToken = jwtService.sign({
      sub: 'user-1',
      platform: 'windows',
    });
    const androidToken = jwtService.sign({
      sub: 'user-1',
      platform: 'android',
    });

    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: `Bearer ${windowsToken}` },
      }),
    ).resolves.toBe(userIpTracker('user-1', '172.20.0.3'));
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: `Bearer ${androidToken}` },
      }),
    ).resolves.toBe(userIpTracker('user-1', '172.20.0.3'));
  });

  it('separates different signed users behind the same trusted IP', async () => {
    const firstToken = jwtService.sign({ sub: 'user-1' });
    const secondToken = jwtService.sign({ sub: 'user-2' });

    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: `Bearer ${firstToken}` },
      }),
    ).resolves.toBe(userIpTracker('user-1', '172.20.0.3'));
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: `Bearer ${secondToken}` },
      }),
    ).resolves.toBe(userIpTracker('user-2', '172.20.0.3'));
  });

  it('separates the same signed user when the trusted IP changes', async () => {
    const token = jwtService.sign({ sub: 'user-1' });

    await expect(
      guard.principalTrackerFor({
        ip: '203.0.113.20',
        headers: { authorization: `Bearer ${token}` },
      }),
    ).resolves.toBe(userIpTracker('user-1', '203.0.113.20'));
    await expect(
      guard.principalTrackerFor({
        ip: '203.0.113.21',
        headers: { authorization: `Bearer ${token}` },
      }),
    ).resolves.toBe(userIpTracker('user-1', '203.0.113.21'));
  });

  it('uses the signed JWT subject before any supplied client identifier', async () => {
    const token = jwtService.sign({ sub: 'user-1' });

    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: {
          authorization: `Bearer ${token}`,
          'x-opshub-client-id': 'pc-1779876132645257',
        },
        query: { clientId: 'pc-1779876132645258' },
        body: { deviceId: 'device-123456' },
      }),
    ).resolves.toBe(userIpTracker('user-1', '172.20.0.3'));
  });

  it('does not trust caller-supplied client or device identifiers', async () => {
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { 'x-opshub-client-id': 'pc-1779876132645257' },
      }),
    ).resolves.toBe(ipTracker('172.20.0.3'));
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: {},
        query: { clientId: 'pc-1779876132645258' },
      }),
    ).resolves.toBe(ipTracker('172.20.0.3'));
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: 'Bearer invalid-token' },
        body: { deviceId: 'device-123456' },
      }),
    ).resolves.toBe(ipTracker('172.20.0.3'));
  });

  it('uses a hashed email bucket for public auth requests without a client id', async () => {
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: {},
        query: { email: 'rotated-query@attacker.invalid' },
        body: { email: ' Staff@PhongVu-Shop.vn ' },
      }),
    ).resolves.toBe(emailTracker('staff@phongvu-shop.vn'));
  });

  it('isolates storage by exact HTTP method and route path without query data', () => {
    const suffix = 'principal:user:user-1:ip:trusted-ip-hash';
    const first = guard.storageKeyFor(
      {
        method: 'GET',
        route: { path: '/home/summary' },
        originalUrl: '/home/summary?startDate=2026-07-15',
      },
      suffix,
    );
    const sameEndpoint = guard.storageKeyFor(
      {
        method: 'GET',
        route: { path: '/home/summary' },
        originalUrl: '/home/summary?startDate=2026-07-14',
      },
      suffix,
    );
    const otherMethod = guard.storageKeyFor(
      { method: 'POST', route: { path: '/home/summary' } },
      suffix,
    );
    const otherPath = guard.storageKeyFor(
      { method: 'GET', route: { path: '/home/summary/scopes' } },
      suffix,
    );

    expect(first).toBe(trackerHash(`principal:GET:/home/summary:${suffix}`));
    expect(sameEndpoint).toBe(first);
    expect(otherMethod).not.toBe(first);
    expect(otherPath).not.toBe(first);
  });

  it('falls back from an invalid JWT to the normalized email bucket', async () => {
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: 'Bearer expired-or-invalid' },
        query: { email: ' USER@PhongVu.vn ' },
      }),
    ).resolves.toBe(emailTracker('user@phongvu.vn'));
  });

  it('falls back to a hashed trusted IP without a usable user or email', async () => {
    await expect(
      guard.principalTrackerFor({ ip: '203.0.113.10', headers: {} }),
    ).resolves.toBe(ipTracker('203.0.113.10'));
    await expect(
      guard.principalTrackerFor({
        ip: '203.0.113.11',
        headers: { authorization: 'Bearer invalid-token' },
      }),
    ).resolves.toBe(ipTracker('203.0.113.11'));
  });

  it('does not trust an unsigned JWT subject', async () => {
    const forgedToken = new JwtService({ secret: 'wrong-secret' }).sign({
      sub: 'forged-user',
    });

    await expect(
      guard.principalTrackerFor({
        ip: '203.0.113.12',
        headers: { authorization: `Bearer ${forgedToken}` },
      }),
    ).resolves.toBe(ipTracker('203.0.113.12'));
  });

  it('moves an expired signed JWT back to the IP bucket', async () => {
    const expiredToken = jwtService.sign(
      { sub: 'expired-user' },
      { expiresIn: -1 },
    );

    await expect(
      guard.principalTrackerFor({
        ip: '203.0.113.13',
        headers: { authorization: `Bearer ${expiredToken}` },
      }),
    ).resolves.toBe(ipTracker('203.0.113.13'));
  });

  it('never exposes the raw trusted IP in a tracker key', async () => {
    const rawIp = '198.51.100.45';
    const tracker = await guard.principalTrackerFor({
      ip: rawIp,
      headers: {},
    });

    expect(tracker).toBe(ipTracker(rawIp));
    expect(tracker).not.toContain(rawIp);
  });

  it('returns a standard Retry-After header so clients can stop polling', async () => {
    const header = jest.fn();
    const context = {
      switchToHttp: () => ({
        getRequest: () => ({
          method: 'GET',
          route: { path: '/home/summary' },
        }),
        getResponse: () => ({ header }),
      }),
    } as unknown as ExecutionContext;

    await expect(
      guard.throwRateLimitFor(context, {
        limit: 120,
        ttl: 60_000,
        key: 'rate-key',
        tracker: 'principal:user:user-1',
        totalHits: 121,
        timeToExpire: 2_500,
        isBlocked: true,
        timeToBlockExpire: 2_500,
      }),
    ).rejects.toMatchObject({ status: 429 });

    expect(header).toHaveBeenCalledWith('Retry-After', '3');
    expect(header).toHaveBeenCalledWith('Cache-Control', 'no-store');
  });
});
