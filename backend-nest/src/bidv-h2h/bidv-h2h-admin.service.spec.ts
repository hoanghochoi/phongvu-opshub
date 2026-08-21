import { ForbiddenException } from '@nestjs/common';
import { BidvH2hAdminService } from './bidv-h2h-admin.service';

describe('BidvH2hAdminService', () => {
  it('denies credential metadata to non-super-admin users', async () => {
    const service = new BidvH2hAdminService({} as any, {} as any, {} as any);

    await expect(
      service.snapshot({ id: 'admin-1', role: 'ADMIN' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('returns metadata without secret hashes, private armor or ciphertext', async () => {
    const prisma = {
      bankApiClient: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'client-1',
            displayName: 'BIDV UAT',
            clientId: 'bidv_client',
            secretHash: 'must-not-leak',
            scope: 'balance-changes:write',
            status: 'ACTIVE',
            version: 1,
          },
        ]),
      },
      bankPgpKey: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'key-1',
            displayName: 'BIDV UAT',
            fingerprint: 'ABC123',
            algorithm: 'ed25519',
            publicKeyArmor: 'public-armor-not-listed',
            privateKeyCipher: 'private-cipher-must-not-leak',
            status: 'ACTIVE',
            version: 1,
          },
        ]),
      },
      bankConnectionControl: {
        upsert: jest.fn().mockResolvedValue({
          ingressEnabled: false,
          projectionEnabled: false,
          version: 1,
        }),
      },
      bankConnectionAudit: { findMany: jest.fn().mockResolvedValue([]) },
      bankTransaction: { count: jest.fn().mockResolvedValue(3) },
    };
    const service = new BidvH2hAdminService(
      prisma as any,
      {} as any,
      {
        evaluate: jest.fn().mockResolvedValue({
          operatingMode: 'STOPPED',
          effectiveMode: 'STOPPED',
          readiness: {
            infrastructure: false,
            kek: false,
            client: true,
            openPgpKey: false,
          },
          blockers: ['Hạ tầng kết nối chưa sẵn sàng.'],
        }),
      } as any,
    );

    const snapshot = await service.snapshot({
      id: 'super-1',
      role: 'SUPER_ADMIN',
    });
    const serialized = JSON.stringify(snapshot);

    expect(serialized).not.toContain('must-not-leak');
    expect(serialized).not.toContain('private-cipher');
    expect(serialized).not.toContain('public-armor');
    expect(snapshot.clients[0].clientId).toBe('bidv_client');
    expect(snapshot.keys[0].fingerprint).toBe('ABC123');
  });

  it('maps the legacy control payload to STOPPED under the advisory lock', async () => {
    const update = jest.fn().mockResolvedValue({
      operatingMode: 'STOPPED',
      ingressEnabled: false,
      projectionEnabled: false,
      version: 8,
    });
    const tx = {
      $executeRaw: jest.fn(),
      bankConnectionControl: {
        upsert: jest.fn().mockResolvedValue({
          operatingMode: 'LIVE',
          ingressEnabled: true,
          projectionEnabled: true,
          version: 7,
        }),
        update,
      },
      bankConnectionAudit: { create: jest.fn() },
    };
    const prisma = {
      $transaction: jest.fn((callback: (value: any) => unknown) =>
        callback(tx),
      ),
    };
    const service = new BidvH2hAdminService(
      prisma as any,
      {} as any,
      {
        lock: (value: any) => value.$executeRaw(),
      } as any,
    );
    jest.spyOn(service, 'snapshot').mockResolvedValue({ ok: true } as any);

    await expect(
      service.updateControl(
        { id: 'super-1', role: 'SUPER_ADMIN' },
        {
          ingressEnabled: false,
          projectionEnabled: false,
          expectedVersion: 7,
        },
      ),
    ).resolves.toEqual({ ok: true });
    expect(tx.$executeRaw).toHaveBeenCalledTimes(1);
    expect(update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          operatingMode: 'STOPPED',
          ingressEnabled: false,
          projectionEnabled: false,
        }),
      }),
    );
  });

  it('rejects a stale optimistic version before changing mode', async () => {
    const update = jest.fn();
    const tx = {
      $executeRaw: jest.fn(),
      bankConnectionControl: {
        upsert: jest.fn().mockResolvedValue({
          operatingMode: 'STOPPED',
          version: 4,
        }),
        update,
      },
    };
    const service = new BidvH2hAdminService(
      {
        $transaction: (callback: (value: any) => unknown) => callback(tx),
      } as any,
      {} as any,
      { lock: (value: any) => value.$executeRaw() } as any,
    );

    await expect(
      service.updateControl(
        { id: 'super-1', role: 'SUPER_ADMIN' },
        { operatingMode: 'STOPPED', expectedVersion: 3 },
      ),
    ).rejects.toMatchObject({ status: 409 });
    expect(update).not.toHaveBeenCalled();
  });

  it('requires expectedVersion for the new operating-mode payload', async () => {
    const service = new BidvH2hAdminService({} as any, {} as any, {} as any);
    await expect(
      service.updateControl(
        { id: 'super-1', role: 'SUPER_ADMIN' },
        { operatingMode: 'UAT_INGEST_ONLY' },
      ),
    ).rejects.toMatchObject({ status: 400 });
  });

  it('rejects an ambiguous mixed mode and legacy payload', async () => {
    const service = new BidvH2hAdminService({} as any, {} as any, {} as any);
    await expect(
      service.updateControl(
        { id: 'super-1', role: 'SUPER_ADMIN' },
        {
          operatingMode: 'STOPPED',
          ingressEnabled: false,
          projectionEnabled: false,
          expectedVersion: 1,
        },
      ),
    ).rejects.toMatchObject({ status: 400 });
  });
});
