import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { ThrottlerModuleOptions, ThrottlerStorage } from '@nestjs/throttler';
import { createHash } from 'crypto';
import { UserAwareThrottlerGuard } from './user-aware-throttler.guard';

class TestableUserAwareThrottlerGuard extends UserAwareThrottlerGuard {
  principalTrackerFor(req: Record<string, any>) {
    return this.getPrincipalTracker(req);
  }

  ipTrackerFor(req: Record<string, any>) {
    return this.getIpTracker(req);
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
    createHash('sha256').update(value).digest('hex').slice(0, 32);
  const emailTracker = (value: string) =>
    `principal:email:${trackerHash(value)}`;

  it('uses the signed JWT subject so the same user shares one bucket', async () => {
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
    ).resolves.toBe('principal:user:user-1');
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: `Bearer ${androidToken}` },
      }),
    ).resolves.toBe('principal:user:user-1');
  });

  it('gives different signed users independent buckets behind one proxy', async () => {
    const firstToken = jwtService.sign({ sub: 'user-1' });
    const secondToken = jwtService.sign({ sub: 'user-2' });

    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: `Bearer ${firstToken}` },
      }),
    ).resolves.toBe('principal:user:user-1');
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: `Bearer ${secondToken}` },
      }),
    ).resolves.toBe('principal:user:user-2');
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
    ).resolves.toBe('principal:user:user-1');
  });

  it('does not trust caller-supplied client or device identifiers', async () => {
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { 'x-opshub-client-id': 'pc-1779876132645257' },
      }),
    ).resolves.toBe('principal:ip:172.20.0.3');
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: {},
        query: { clientId: 'pc-1779876132645258' },
      }),
    ).resolves.toBe('principal:ip:172.20.0.3');
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: { authorization: 'Bearer invalid-token' },
        body: { deviceId: 'device-123456' },
      }),
    ).resolves.toBe('principal:ip:172.20.0.3');
  });

  it('uses a hashed email bucket for public auth requests without a client id', async () => {
    await expect(
      guard.principalTrackerFor({
        ip: '172.20.0.3',
        headers: {},
        body: { email: ' Staff@PhongVu-Shop.vn ' },
      }),
    ).resolves.toBe(emailTracker('staff@phongvu-shop.vn'));
  });

  it('falls back to the client IP only without a usable user or client identifier', async () => {
    await expect(
      guard.principalTrackerFor({ ip: '203.0.113.10', headers: {} }),
    ).resolves.toBe('principal:ip:203.0.113.10');
    await expect(
      guard.principalTrackerFor({
        ip: '203.0.113.11',
        headers: { authorization: 'Bearer invalid-token' },
      }),
    ).resolves.toBe('principal:ip:203.0.113.11');
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
    ).resolves.toBe('principal:ip:203.0.113.12');
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
    ).resolves.toBe('principal:ip:203.0.113.13');
  });

  it('always produces an independent IP bucket', async () => {
    await expect(
      guard.ipTrackerFor({
        ip: '203.0.113.14',
        headers: { 'x-client-id': 'attacker-controlled' },
        body: { email: 'one@phongvu-shop.vn' },
      }),
    ).resolves.toBe('ip:203.0.113.14');
  });
});
