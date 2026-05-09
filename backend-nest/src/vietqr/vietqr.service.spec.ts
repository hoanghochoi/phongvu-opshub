import {
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { VietQrService } from './vietqr.service';

describe('VietQrService', () => {
  const originalEnv = process.env;
  let service: VietQrService;

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      VIETQR_BANK_BIN: '970436',
      VIETQR_ACCOUNT_NUMBER: '123456789',
      VIETQR_ACCOUNT_NAME: 'Phong Vu',
      VIETQR_MERCHANT_CITY: 'Ho Chi Minh',
    };
    service = new VietQrService();
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('creates a VietQR EMV payload with transfer content and crc', () => {
    const result = service.create({
      amount: 150000,
      orderCode: 'DH-001',
      storeCode: 'HCM01',
    });

    expect(result).toMatchObject({
      bankBin: '970436',
      accountNumber: '123456789',
      accountName: 'PHONG VU',
      amount: 150000,
      transferContent: 'HCM01-DH-001',
    });
    expect(result.qrPayload).toContain('0010A000000727');
    expect(result.qrPayload).toContain('0208QRIBFTTA');
    expect(result.qrPayload).toContain('5406150000');
    expect(result.qrPayload).toContain('0812HCM01-DH-001');
    expect(result.qrPayload).toMatch(/6304[0-9A-F]{4}$/);
  });

  it('rejects invalid amount', () => {
    expect(() =>
      service.create({ amount: 0, orderCode: 'DH-001', storeCode: 'HCM01' }),
    ).toThrow(BadRequestException);
  });

  it('fails clearly when backend VietQR config is missing', () => {
    delete process.env.VIETQR_BANK_BIN;

    expect(() =>
      service.create({
        amount: 150000,
        orderCode: 'DH-001',
        storeCode: 'HCM01',
      }),
    ).toThrow(ServiceUnavailableException);
  });
});
