import { ForbiddenException } from '@nestjs/common';
import { BidvH2hAdminService } from './bidv-h2h-admin.service';

describe('BidvH2hAdminService', () => {
  it('denies credential metadata to non-super-admin users', async () => {
    const service = new BidvH2hAdminService({} as any, {} as any);

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
    };
    const service = new BidvH2hAdminService(prisma as any, {} as any);

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
});
