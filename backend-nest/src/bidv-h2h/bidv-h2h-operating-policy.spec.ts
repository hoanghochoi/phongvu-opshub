import { BidvH2hOperatingPolicy } from './bidv-h2h-operating-policy';

describe('BidvH2hOperatingPolicy', () => {
  beforeEach(() => {
    process.env.BIDV_H2H_ENVIRONMENT = 'local';
    process.env.BIDV_H2H_PUBLIC_BASE_URL = 'http://localhost:3000';
    process.env.BIDV_H2H_KEK_BASE64 = Buffer.alloc(32, 5).toString('base64');
    delete process.env.BIDV_H2H_EMERGENCY_DISABLED;
  });

  it('uses the same complete readiness policy for effective ingress', async () => {
    const service = new BidvH2hOperatingPolicy(
      prisma({ operatingMode: 'UAT_INGEST_ONLY' }) as any,
      { decryptPrivateKey: jest.fn().mockReturnValue('private armor') } as any,
    );
    await expect(service.assertIngress()).resolves.toMatchObject({
      effectiveMode: 'UAT_INGEST_ONLY',
      ready: true,
    });
  });

  it('fails public traffic closed when the active key disappears', async () => {
    const db = prisma({ operatingMode: 'LIVE' });
    db.bankPgpKey.findFirst.mockResolvedValue(null);
    const service = new BidvH2hOperatingPolicy(db as any, {} as any);
    await expect(service.assertIngress()).rejects.toMatchObject({
      status: 503,
    });
    await expect(service.evaluate()).resolves.toMatchObject({
      effectiveMode: 'STOPPED',
      readiness: { openPgpKey: false },
    });
  });

  it('fails closed when the mounted KEK cannot decrypt the active key', async () => {
    const service = new BidvH2hOperatingPolicy(
      prisma({ operatingMode: 'LIVE' }) as any,
      {
        decryptPrivateKey: jest.fn(() => {
          throw new Error('mismatch');
        }),
      } as any,
    );
    await expect(service.assertLive()).rejects.toMatchObject({ status: 503 });
  });
});

function prisma(control: any) {
  return {
    bankConnectionControl: { findUnique: jest.fn().mockResolvedValue(control) },
    bankApiClient: {
      findFirst: jest.fn().mockResolvedValue({ id: 'client-1' }),
    },
    bankPgpKey: {
      findFirst: jest.fn().mockResolvedValue({
        id: 'key-1',
        privateKeyCipher: 'cipher',
      }),
    },
  };
}
