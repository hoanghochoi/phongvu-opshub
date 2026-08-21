import { ConflictException, PayloadTooLargeException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'crypto';
import { BidvH2hIngressService } from './bidv-h2h-ingress.service';

const ENV_KEYS = [
  'BIDV_H2H_ENVIRONMENT',
  'BIDV_H2H_PUBLIC_BASE_URL',
  'BIDV_H2H_INGEST_ENABLED',
  'BIDV_H2H_PROJECTION_ENABLED',
  'BIDV_H2H_KEK_BASE64',
  'BIDV_H2H_MAX_ENCODED_BODY_BYTES',
] as const;

describe('BidvH2hIngressService', () => {
  const originalEnv = Object.fromEntries(
    ENV_KEYS.map((key) => [key, process.env[key]]),
  );

  beforeEach(() => {
    process.env.BIDV_H2H_ENVIRONMENT = 'local';
    process.env.BIDV_H2H_PUBLIC_BASE_URL = 'http://localhost:3000';
    process.env.BIDV_H2H_INGEST_ENABLED = 'true';
    process.env.BIDV_H2H_PROJECTION_ENABLED = 'false';
    process.env.BIDV_H2H_KEK_BASE64 = Buffer.alloc(32, 7).toString('base64');
    process.env.BIDV_H2H_MAX_ENCODED_BODY_BYTES = '1048576';
  });

  afterAll(() => {
    for (const key of ENV_KEYS) {
      const value = originalEnv[key];
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  it('rejects an oversized encrypted body before any database or crypto work', async () => {
    process.env.BIDV_H2H_MAX_ENCODED_BODY_BYTES = '4';
    const prisma = {
      bankConnectionControl: { findUnique: jest.fn() },
    };
    const crypto = { decryptPayload: jest.fn() };
    const service = new BidvH2hIngressService(
      prisma as any,
      crypto as any,
      { parsePayload: jest.fn() } as any,
      policy() as any,
    );

    await expect(
      service.ingest(principal(), 'request-1', 'BIDV', '12345'),
    ).rejects.toBeInstanceOf(PayloadTooLargeException);
    expect(prisma.bankConnectionControl.findUnique).not.toHaveBeenCalled();
    expect(crypto.decryptPayload).not.toHaveBeenCalled();
  });

  it('rejects a reused REQUESTID with different content before decrypting', async () => {
    const encryptedData = 'ciphertext-new';
    const prisma = {
      bankConnectionControl: {
        findUnique: jest.fn().mockResolvedValue({ ingressEnabled: true }),
      },
      bankIngressReceipt: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'receipt-1',
          requestHash: createHash('sha256')
            .update('BIDV|ciphertext-old')
            .digest('hex'),
        }),
      },
    };
    const crypto = { decryptPayload: jest.fn() };
    const service = new BidvH2hIngressService(
      prisma as any,
      crypto as any,
      { parsePayload: jest.fn() } as any,
      policy() as any,
    );

    await expect(
      service.ingest(principal(), 'request-1', 'BIDV', encryptedData),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(crypto.decryptPayload).not.toHaveBeenCalled();
  });

  it('locks distinct transaction identities in stable order before writes', async () => {
    const executeRaw = jest.fn().mockResolvedValue(1);
    const tx = {
      $executeRaw: executeRaw,
      bankIngressReceipt: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'receipt-1' }),
        update: jest.fn().mockResolvedValue({ id: 'receipt-1' }),
      },
      bankTransaction: {
        findMany: jest.fn().mockResolvedValue([]),
        create: jest
          .fn()
          .mockResolvedValueOnce({ id: 'transaction-1' })
          .mockResolvedValueOnce({ id: 'transaction-2' })
          .mockResolvedValueOnce({ id: 'transaction-3' }),
        updateMany: jest.fn(),
      },
      domainOutboxEvent: { create: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      bankConnectionControl: {
        findUnique: jest.fn().mockResolvedValue({ ingressEnabled: true }),
      },
      bankIngressReceipt: { findUnique: jest.fn().mockResolvedValue(null) },
      bankPgpKey: {
        findMany: jest
          .fn()
          .mockResolvedValue([{ privateKeyCipher: 'encrypted-key' }]),
      },
      $transaction: jest.fn(async (callback: (client: any) => unknown) =>
        callback(tx),
      ),
    };
    const rows = [
      row('identity-b', 'payload-1'),
      row('identity-a', 'payload-2'),
      row('identity-b', 'payload-3'),
    ];
    const service = new BidvH2hIngressService(
      prisma as any,
      {
        decryptPayload: jest.fn().mockResolvedValue('cleartext'),
        sensitiveHash: jest.fn((value: string) => `hash:${value}`),
        maskAccount: jest.fn((value?: string) => value ?? null),
      } as any,
      { parsePayload: jest.fn().mockReturnValue(rows) } as any,
      policy(true) as any,
    );

    await expect(
      service.ingest(principal(), 'request-1', 'BIDV', 'ciphertext'),
    ).resolves.toEqual({ errorCode: '000', errorDesc: 'Success' });

    expect(executeRaw).toHaveBeenCalledTimes(4);
    expect(executeRaw.mock.calls[2][1]).toBe('bidv-identity:identity-a');
    expect(executeRaw.mock.calls[3][1]).toBe('bidv-identity:identity-b');
    expect(
      tx.bankIngressReceipt.create.mock.invocationCallOrder[0],
    ).toBeGreaterThan(executeRaw.mock.invocationCallOrder[3]);
  });
});

function principal() {
  return {
    id: 'client-ref-1',
    clientId: 'client-1',
    bankCode: 'BIDV',
    scope: 'balance-changes:write',
  };
}

function policy(lock = false) {
  return {
    assertIngress: jest.fn().mockResolvedValue({
      effectiveMode: 'UAT_INGEST_ONLY',
    }),
    lock: jest.fn((tx: any) =>
      lock ? tx.$executeRaw(['control-lock'] as any) : undefined,
    ),
  };
}

function row(identityHash: string, payloadHash: string) {
  return {
    identityHash,
    payloadHash,
    accountNo: '123456789',
    amount: new Prisma.Decimal('1000'),
    currency: 'VND',
    transactionDateValue: new Date('2026-07-30T00:00:00.000Z'),
    transTime: '120000',
    paidAt: new Date('2026-07-30T05:00:00.000Z'),
    dorc: 'C',
    seq: '1',
    refNo: 'REF-1',
    remark: 'CP01',
    businessDateValue: new Date('2026-07-30T00:00:00.000Z'),
    extensions: {},
  } as any;
}
