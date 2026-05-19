import {
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { VietQrService } from './vietqr.service';

describe('VietQrService', () => {
  const originalEnv = process.env;
  let service: VietQrService;
  let prisma: { store: { findUnique: jest.Mock } };

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      VIETQR_BANK_BIN: '970436',
      VIETQR_ACCOUNT_NUMBER: '123456789',
      VIETQR_ACCOUNT_NAME: 'Phong Vu',
      VIETQR_MERCHANT_CITY: 'Ho Chi Minh',
    };
    prisma = { store: { findUnique: jest.fn().mockResolvedValue(null) } };
    service = new VietQrService(prisma as any);
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('creates a VietQR EMV payload with transfer content and crc', async () => {
    const result = await service.create({
      amount: 150000,
      orderCode: 'DH-001',
      storeCode: 'HCM01',
    });

    expect(result).toMatchObject({
      bankBin: '970436',
      bankName: 'Vietcombank',
      accountNumber: '123456789',
      accountName: 'PHONG VU',
      amount: 150000,
      transferContent: 'DH-001 HCM01 BOT',
    });
    expect(result.qrPayload).toContain('0010A000000727');
    expect(result.qrPayload).toContain('0208QRIBFTTA');
    expect(result.qrPayload).toContain('5406150000');
    expect(result.qrPayload).toContain('0816DH-001 HCM01 BOT');
    expect(result.qrPayload).toMatch(/6304[0-9A-F]{4}$/);
  });

  it('rejects invalid amount', async () => {
    await expect(
      service.create({ amount: 0, orderCode: 'DH-001', storeCode: 'HCM01' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('fails clearly when backend VietQR config is missing', async () => {
    delete process.env.VIETQR_BANK_BIN;

    await expect(
      service.create({
        amount: 150000,
        orderCode: 'DH-001',
        storeCode: 'HCM01',
      }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('uses store transfer account when configured', async () => {
    prisma.store.findUnique.mockResolvedValue({
      transferAccountNumber: '999999',
      transferAccountName: 'Store Account',
      transferBankName: 'VietinBank',
      transferBankBin: null,
    });

    const result = await service.create({
      amount: 150000,
      orderCode: 'DH-001',
      storeCode: 'HCM01',
    });

    expect(result.accountNumber).toBe('999999');
    expect(result.accountName).toBe('STORE ACCOUNT');
    expect(result.bankBin).toBe('970415');
    expect(result.bankName).toBe('VietinBank');
  });

  it('resolves VietinBank BIN from store bank name when env fallback is missing', async () => {
    delete process.env.VIETQR_BANK_BIN;
    prisma.store.findUnique.mockResolvedValue({
      transferAccountNumber: '18PVICU',
      transferAccountName: 'Phong Vu',
      transferBankName: 'VietinBank',
      transferBankBin: null,
    });

    const result = await service.create({
      amount: 150000,
      orderCode: 'DH-001',
      storeCode: 'CP62',
    });

    expect(result.bankBin).toBe('970415');
    expect(result.bankName).toBe('VietinBank');
    expect(result.accountNumber).toBe('18PVICU');
  });
});
