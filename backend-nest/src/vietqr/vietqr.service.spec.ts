import {
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import jsQR from 'jsqr';
import { PNG } from 'pngjs';
import { VietQrService } from './vietqr.service';

describe('VietQrService', () => {
  const originalEnv = process.env;
  let service: VietQrService;
  let prisma: {
    store: { findUnique: jest.Mock };
    vietQrPaymentIntent: {
      create: jest.Mock;
      findUnique: jest.Mock;
      findMany: jest.Mock;
      update: jest.Mock;
      updateMany: jest.Mock;
    };
    mapVietinTransaction: {
      findMany: jest.Mock;
    };
  };
  let mapVietinService: { searchTransactionsForStoreCode: jest.Mock };

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      VIETQR_BANK_BIN: '970436',
      VIETQR_ACCOUNT_NUMBER: '123456789',
      VIETQR_ACCOUNT_NAME: 'Phong Vu',
      VIETQR_MERCHANT_CITY: 'Ho Chi Minh',
    };
    prisma = {
      store: { findUnique: jest.fn().mockResolvedValue(null) },
      vietQrPaymentIntent: {
        create: jest.fn(async ({ data }) => ({
          id: 'payment-1',
          status: 'PENDING',
          createdAt: new Date('2026-05-20T10:00:00.000Z'),
          ...data,
        })),
        findUnique: jest.fn(),
        findMany: jest.fn().mockResolvedValue([]),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      mapVietinTransaction: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    mapVietinService = { searchTransactionsForStoreCode: jest.fn() };
    service = new VietQrService(prisma as any, mapVietinService as any);
  });

  afterEach(() => {
    jest.restoreAllMocks();
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
      id: 'payment-1',
      status: 'PENDING',
      qrBrand: {
        key: 'phongvu',
        title: 'Phong Vũ',
        logoKey: 'phongvu',
      },
    });
    expect(result.qrPayload).toContain('0010A000000727');
    expect(result.qrPayload).toContain('0208QRIBFTTA');
    expect(result.qrPayload).toContain('5406150000');
    expect(result.qrPayload).toContain('0816DH-001 HCM01 BOT');
    expect(hasValidCrc(result.qrPayload)).toBe(true);
    expect(result.qrPayload).toMatch(/6304[0-9A-F]{4}$/);
  });

  it('creates an editable QR when amount and transfer content are blank', async () => {
    const result = await service.create({
      amount: null,
      orderCode: '',
      storeCode: 'HCM01',
    });

    expect(result.amount).toBeNull();
    expect(result.transferContent).toBe('');
    expect(prisma.vietQrPaymentIntent.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          amount: null,
          orderCode: null,
          transferContent: '',
        }),
      }),
    );
    expect(readTopLevelEmvTags(result.qrPayload)).not.toHaveProperty('54');
    expect(readTopLevelEmvTags(result.qrPayload)).not.toHaveProperty('62');
  });

  it('accepts arbitrary transfer content instead of only order numbers', async () => {
    const result = await service.create({
      amount: 150000,
      orderCode: 'Cọc bảo hành máy A',
      storeCode: 'HCM01',
    });

    expect(result.transferContent).toBe('COC BAO HANH MAY A HCM01 BOT');
    expect(result.qrPayload).toContain('0828COC BAO HANH MAY A HCM01 BOT');
  });

  it('creates an n8n-ready image response with exact addInfo transfer content', async () => {
    prisma.store.findUnique.mockResolvedValueOnce({
      area: {
        regionCode: 'ACARETEK',
        region: {
          code: 'ACARETEK',
          displayName: 'ACareTek',
          abbreviation: 'ACareTek',
        },
      },
    });

    const result = await service.createExternal({
      amount: 150000,
      addInfo: 'DH-001 CP62 BOT',
      storeCode: 'CP62',
      source: 'n8n-test',
    });

    expect(result).toMatchObject({
      paymentId: 'payment-1',
      bankBin: '970436',
      bankName: 'Vietcombank',
      accountNumber: '123456789',
      accountName: 'PHONG VU',
      amount: 150000,
      transferContent: 'DH-001 CP62 BOT',
      qrBrand: {
        key: 'acaretek',
        title: 'ACareTek',
        logoKey: 'acare',
      },
      imageMimeType: 'image/png',
      imageFileName: 'vietqr_DH-001_CP62_BOT.png',
    });
    expect(result.imageDataUrl.startsWith('data:image/png;base64,')).toBe(true);
    expect(result.imageBuffer.subarray(0, 4)).toEqual(
      Buffer.from([0x89, 0x50, 0x4e, 0x47]),
    );
    expect(decodeQrFromPng(result.imageBuffer)).toBe(result.qrPayload);
    expect(result.imageSizeBytes).toBeGreaterThan(1000);
  }, 15000);

  it('uses the ACareTek QR brand for stores in the ACareTek region', async () => {
    prisma.store.findUnique.mockResolvedValue({
      area: {
        regionCode: 'ACARETEK',
        region: {
          code: 'ACARETEK',
          displayName: 'ACareTek',
          abbreviation: 'ACareTek',
        },
      },
    });

    const result = await service.create({
      amount: 150000,
      orderCode: 'DH-001',
      storeCode: 'AC001',
    });

    expect(result.qrBrand).toMatchObject({
      key: 'acaretek',
      title: 'ACareTek',
      logoKey: 'acare',
      logoAsset: 'assets/icon/acare_logo.png',
    });
  });

  it('returns external payment status without running MAP check', async () => {
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      qrPayload: 'payload',
      status: 'PENDING',
      matchedTransactionNumber: null,
      matchedAmount: null,
      matchedTranTime: null,
      matchedPayerName: null,
      matchedPayerAccount: null,
      matchedTransactionContent: null,
      confirmedAt: null,
      lastCheckedAt: null,
      lastCheckResult: null,
      createdAt: new Date('2026-05-20T10:00:00.000Z'),
      updatedAt: new Date('2026-05-20T10:00:00.000Z'),
    });

    await expect(service.getExternalStatus('payment-1')).resolves.toMatchObject(
      {
        paymentId: 'payment-1',
        status: 'PENDING',
        confirmed: false,
        amount: 150000,
        transferContent: 'DH-001 CP62 BOT',
      },
    );
    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
  });

  it('checks external payment status and updates matching stored payment', async () => {
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-05-20T10:06:00.000Z').getTime());
    const createdAt = new Date('2026-05-20T10:00:00.000Z');
    const updatedAt = new Date('2026-05-20T10:05:00.000Z');
    const pendingIntent = {
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      qrPayload: 'payload',
      status: 'PENDING',
      createdAt,
      updatedAt: createdAt,
    };
    const paidIntent = {
      ...pendingIntent,
      status: 'PAID',
      matchedTransactionNumber: 'txn-1',
      matchedAmount: 150000,
      matchedTranTime: updatedAt,
      matchedPayerName: 'Nguyen Van A',
      matchedPayerAccount: '123456789',
      matchedTransactionContent: 'IBFT DH-001 CP62 BOT',
      confirmedAt: updatedAt,
      lastCheckedAt: updatedAt,
      lastCheckResult: { reason: 'MATCHED_STORED', matchedCandidates: 1 },
      updatedAt,
    };
    prisma.vietQrPaymentIntent.findUnique
      .mockResolvedValueOnce(pendingIntent)
      .mockResolvedValueOnce(paidIntent);
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'map-id-1',
        transactionNumber: 'txn-1',
        amount: 150000,
        paidAt: updatedAt,
        payerName: 'Nguyen Van A',
        payerAccount: '123456789',
        content: 'IBFT DH-001 CP62 BOT',
      },
    ]);
    await expect(
      service.checkExternalStatus('payment-1'),
    ).resolves.toMatchObject({
      paymentId: 'payment-1',
      status: 'PAID',
      confirmed: true,
      matchedTransactionNumber: 'txn-1',
      checkResult: { reason: 'MATCHED_STORED', confirmed: true },
    });
    expect(prisma.vietQrPaymentIntent.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'payment-1', status: 'PENDING' },
        data: expect.objectContaining({
          status: 'PAID',
          matchedTransactionId: 'map-id-1',
          matchedTransactionNumber: 'txn-1',
        }),
      }),
    );
    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
  });

  it('keeps external status pending when no stored MAP transaction matches', async () => {
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-05-20T10:06:00.000Z').getTime());
    const createdAt = new Date('2026-05-20T10:00:00.000Z');
    const pendingIntent = {
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      qrPayload: 'payload',
      status: 'PENDING',
      matchedTransactionNumber: null,
      matchedAmount: null,
      matchedTranTime: null,
      matchedPayerName: null,
      matchedPayerAccount: null,
      matchedTransactionContent: null,
      confirmedAt: null,
      lastCheckedAt: null,
      lastCheckResult: null,
      createdAt,
      updatedAt: createdAt,
    };
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue(pendingIntent);
    prisma.mapVietinTransaction.findMany.mockResolvedValue([]);

    await expect(
      service.checkExternalStatus('payment-1'),
    ).resolves.toMatchObject({
      paymentId: 'payment-1',
      status: 'PENDING',
      confirmed: false,
      checkResult: { reason: 'NO_STORED_MATCH', confirmed: false },
    });
    expect(prisma.vietQrPaymentIntent.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'payment-1', status: 'PENDING' },
        data: expect.objectContaining({ status: 'PENDING' }),
      }),
    );
    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
  });

  it('auto-reconciles pending VietQR intents from stored MAP transactions only', async () => {
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-05-20T10:06:00.000Z').getTime());
    const createdAt = new Date('2026-05-20T10:00:00.000Z');
    const paidAt = new Date('2026-05-20T10:05:00.000Z');
    const pendingIntent = {
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      qrPayload: 'payload',
      status: 'PENDING',
      createdAt,
      updatedAt: createdAt,
    };
    const paidIntent = {
      ...pendingIntent,
      status: 'PAID',
      matchedTransactionNumber: 'txn-1',
      matchedAmount: 150000,
      matchedTranTime: paidAt,
      matchedPayerName: 'Nguyen Van A',
      matchedPayerAccount: '123456789',
      matchedTransactionContent: 'IBFT DH-001 CP62 BOT',
      confirmedAt: paidAt,
      lastCheckedAt: paidAt,
      updatedAt: paidAt,
    };
    prisma.vietQrPaymentIntent.findMany.mockResolvedValue([pendingIntent]);
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue(paidIntent);
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'map-id-1',
        transactionNumber: 'txn-1',
        amount: 150000,
        paidAt,
        payerName: 'Nguyen Van A',
        payerAccount: '123456789',
        content: 'IBFT DH-001 CP62 BOT',
      },
    ]);

    await service.reconcilePendingPaymentIntents();

    expect(prisma.vietQrPaymentIntent.findMany).toHaveBeenCalledWith({
      where: { status: 'PENDING' },
      orderBy: { createdAt: 'asc' },
      take: 100,
    });
    expect(prisma.vietQrPaymentIntent.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'payment-1', status: 'PENDING' },
        data: expect.objectContaining({
          status: 'PAID',
          matchedTransactionId: 'map-id-1',
        }),
      }),
    );
    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
  });

  it('marks still-pending VietQR intents failed after the Vietnam-local day changes', async () => {
    const nowSpy = jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-05-20T17:01:00.000Z').getTime());
    const createdAt = new Date('2026-05-20T16:59:00.000Z');
    const pendingIntent = {
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      qrPayload: 'payload',
      status: 'PENDING',
      matchedTransactionNumber: null,
      matchedAmount: null,
      matchedTranTime: null,
      matchedPayerName: null,
      matchedPayerAccount: null,
      matchedTransactionContent: null,
      confirmedAt: null,
      lastCheckedAt: null,
      lastCheckResult: null,
      createdAt,
      updatedAt: createdAt,
    };
    const failedIntent = {
      ...pendingIntent,
      status: 'FAILED',
      lastCheckResult: { reason: 'EXPIRED_VIETNAM_DAY' },
      updatedAt: new Date('2026-05-20T17:01:00.000Z'),
    };
    prisma.vietQrPaymentIntent.findUnique
      .mockResolvedValueOnce(pendingIntent)
      .mockResolvedValueOnce(failedIntent);

    try {
      await expect(
        service.checkExternalStatus('payment-1'),
      ).resolves.toMatchObject({
        paymentId: 'payment-1',
        status: 'FAILED',
        confirmed: false,
        checkResult: { reason: 'EXPIRED_VIETNAM_DAY', confirmed: false },
      });
    } finally {
      nowSpy.mockRestore();
    }

    expect(prisma.mapVietinTransaction.findMany).not.toHaveBeenCalled();
    expect(prisma.vietQrPaymentIntent.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'payment-1', status: 'PENDING' },
        data: expect.objectContaining({ status: 'FAILED' }),
      }),
    );
    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
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

  it('confirms payment when transaction content contains QR transfer content', async () => {
    const createdAt = new Date('2026-05-20T10:00:00.000Z');
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      status: 'PENDING',
      createdAt,
    });
    prisma.vietQrPaymentIntent.update.mockImplementation(async ({ data }) => ({
      id: 'payment-1',
      ...data,
    }));
    mapVietinService.searchTransactionsForStoreCode.mockResolvedValue({
      total: 1,
      list: [
        {
          id: 'map-id-1',
          transactionNumber: 'txn-1',
          amount: 150000,
          statusText: 'Thành công',
          transactionDescription: 'IBFT 123 DH-001 CP62 BOT 456',
          senderName: 'Nguyen Van A',
          senderAccount: '123456789',
          tranTime: '20/05/2026 17:05:00',
        },
      ],
    });

    await expect(
      service.confirmPayment({ role: 'SUPER_ADMIN' }, 'payment-1'),
    ).resolves.toMatchObject({
      id: 'payment-1',
      status: 'PAID',
      confirmed: true,
      reason: 'MATCHED',
      matchedTransactionNumber: 'txn-1',
      matchedAmount: 150000,
      matchedPayerName: 'Nguyen Van A',
      matchedPayerAccount: '123456789',
      matchedTransactionContent: 'IBFT 123 DH-001 CP62 BOT 456',
    });

    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).toHaveBeenCalledWith(
      'CP62',
      expect.objectContaining({
        amount: '150000',
        page: 0,
        size: 100,
      }),
    );
    expect(prisma.vietQrPaymentIntent.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'PAID',
          matchedTransactionId: 'map-id-1',
          matchedTransactionNumber: 'txn-1',
          matchedAmount: 150000,
          matchedPayerName: 'Nguyen Van A',
          matchedPayerAccount: '123456789',
          matchedTransactionContent: 'IBFT 123 DH-001 CP62 BOT 456',
        }),
      }),
    );
  });

  it('confirms payment from stored MAP transactions before calling MAP directly', async () => {
    const createdAt = new Date('2026-05-20T10:00:00.000Z');
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      status: 'PENDING',
      createdAt,
    });
    prisma.mapVietinTransaction.findMany.mockResolvedValue([
      {
        id: 'stored-map-1',
        transactionNumber: 'txn-1',
        amount: 150000,
        content: 'IBFT 123 DH-001 CP62 BOT 456',
        paidAt: new Date('2026-05-20T10:05:00.000Z'),
        payerName: 'Nguyen Van A',
        payerAccount: '123456789',
        firstSeenAt: new Date('2026-05-20T10:05:05.000Z'),
      },
    ]);
    prisma.vietQrPaymentIntent.update.mockImplementation(async ({ data }) => ({
      id: 'payment-1',
      ...data,
    }));

    await expect(
      service.confirmPayment({ role: 'SUPER_ADMIN' }, 'payment-1'),
    ).resolves.toMatchObject({
      id: 'payment-1',
      status: 'PAID',
      confirmed: true,
      reason: 'MATCHED_STORED',
      matchedTransactionNumber: 'txn-1',
      matchedAmount: 150000,
      matchedPayerName: 'Nguyen Van A',
      matchedPayerAccount: '123456789',
      matchedTransactionContent: 'IBFT 123 DH-001 CP62 BOT 456',
    });

    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
  });

  it('does not revive a failed expired payment from the app confirm endpoint', async () => {
    const createdAt = new Date('2026-05-19T16:59:00.000Z');
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      status: 'FAILED',
      matchedTransactionNumber: null,
      matchedAmount: null,
      matchedTranTime: null,
      matchedPayerName: null,
      matchedPayerAccount: null,
      matchedTransactionContent: null,
      confirmedAt: null,
      createdAt,
    });

    await expect(
      service.confirmPayment({ role: 'SUPER_ADMIN' }, 'payment-1'),
    ).resolves.toMatchObject({
      id: 'payment-1',
      status: 'FAILED',
      confirmed: false,
      reason: 'EXPIRED_VIETNAM_DAY',
    });

    expect(prisma.mapVietinTransaction.findMany).not.toHaveBeenCalled();
    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
    expect(prisma.vietQrPaymentIntent.update).not.toHaveBeenCalled();
  });

  it('confirms MAP rows that use Vietnam-local time and alternate field names', async () => {
    const nowSpy = jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-05-20T14:10:00.000Z').getTime());
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      status: 'PENDING',
      createdAt: new Date('2026-05-20T14:00:00.000Z'),
    });
    prisma.vietQrPaymentIntent.update.mockImplementation(async ({ data }) => ({
      id: 'payment-1',
      ...data,
    }));
    mapVietinService.searchTransactionsForStoreCode.mockResolvedValue({
      total: 1,
      list: [
        {
          id: 'map-id-1',
          txnNumber: 'txn-1',
          txnAmount: '150,000',
          statusName: 'Hoàn thành',
          paymentContent: 'MAP DH-001 CP62 BOT extra',
          payerName: 'Tran Thi B',
          payerAccountNo: '987654321',
          txnDate: '20/05/2026 21:05:00',
        },
      ],
    });

    try {
      await expect(
        service.confirmPayment({ role: 'SUPER_ADMIN' }, 'payment-1'),
      ).resolves.toMatchObject({
        status: 'PAID',
        confirmed: true,
        matchedTransactionNumber: 'txn-1',
        matchedAmount: 150000,
        matchedTranTime: new Date('2026-05-20T14:05:00.000Z'),
        matchedPayerName: 'Tran Thi B',
        matchedPayerAccount: '987654321',
        matchedTransactionContent: 'MAP DH-001 CP62 BOT extra',
      });
    } finally {
      nowSpy.mockRestore();
    }
  });

  it('does not confirm when only order code fields match without transfer content', async () => {
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      status: 'PENDING',
      createdAt: new Date('2026-05-20T10:00:00.000Z'),
    });
    prisma.vietQrPaymentIntent.update.mockImplementation(async ({ data }) => ({
      id: 'payment-1',
      ...data,
    }));
    mapVietinService.searchTransactionsForStoreCode.mockResolvedValue({
      total: 1,
      list: [
        {
          amount: 150000,
          statusText: 'SUCCESS',
          transactionDescription: 'Khach chuyen tien',
          billNumber: 'DH-001',
          requestId: 'CP62',
          tranTime: '20/05/2026 17:05:00',
        },
      ],
    });

    await expect(
      service.confirmPayment({ role: 'SUPER_ADMIN' }, 'payment-1'),
    ).resolves.toMatchObject({
      status: 'NOT_FOUND',
      confirmed: false,
      reason: 'NO_MATCH',
    });
  });

  it('does not auto-confirm when amount or transfer content is missing', async () => {
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: null,
      orderCode: null,
      transferContent: '',
      status: 'PENDING',
      createdAt: new Date('2026-05-20T10:00:00.000Z'),
    });
    prisma.vietQrPaymentIntent.update.mockImplementation(async ({ data }) => ({
      id: 'payment-1',
      ...data,
    }));

    await expect(
      service.confirmPayment({ role: 'SUPER_ADMIN' }, 'payment-1'),
    ).resolves.toMatchObject({
      id: 'payment-1',
      status: 'MANUAL_REVIEW',
      confirmed: false,
      reason: 'MISSING_MATCH_FIELDS',
    });
    expect(
      mapVietinService.searchTransactionsForStoreCode,
    ).not.toHaveBeenCalled();
  });

  it('keeps payment unconfirmed when multiple MAP transactions match', async () => {
    prisma.vietQrPaymentIntent.findUnique.mockResolvedValue({
      id: 'payment-1',
      storeCode: 'CP62',
      amount: 150000,
      orderCode: 'DH-001',
      transferContent: 'DH-001 CP62 BOT',
      status: 'PENDING',
      createdAt: new Date('2026-05-20T10:00:00.000Z'),
    });
    prisma.vietQrPaymentIntent.update.mockImplementation(async ({ data }) => ({
      id: 'payment-1',
      ...data,
    }));
    mapVietinService.searchTransactionsForStoreCode.mockResolvedValue({
      total: 2,
      list: [
        {
          amount: 150000,
          statusText: 'SUCCESS',
          transactionDescription: 'DH-001 CP62 BOT',
          tranTime: '20/05/2026 17:05:00',
        },
        {
          amount: 150000,
          statusText: 'SUCCESS',
          transactionDescription: 'DH-001 CP62 BOT',
          tranTime: '20/05/2026 17:06:00',
        },
      ],
    });

    await expect(
      service.confirmPayment({ role: 'SUPER_ADMIN' }, 'payment-1'),
    ).resolves.toMatchObject({
      status: 'AMBIGUOUS',
      confirmed: false,
      reason: 'MULTIPLE_MATCHES',
      matchedCandidates: 2,
    });
  });
});

function decodeQrFromPng(buffer: Buffer): string | null {
  const png = PNG.sync.read(buffer);
  const data = new Uint8ClampedArray(
    png.data.buffer,
    png.data.byteOffset,
    png.data.byteLength,
  );
  return jsQR(data, png.width, png.height)?.data ?? null;
}

function hasValidCrc(payload: string): boolean {
  const expected = payload.slice(-4);
  const withoutCrc = payload.slice(0, -4);
  let crc = 0xffff;
  for (let i = 0; i < withoutCrc.length; i += 1) {
    crc ^= withoutCrc.charCodeAt(i) << 8;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 0x8000) !== 0 ? (crc << 1) ^ 0x1021 : crc << 1;
      crc &= 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0') === expected;
}

function readTopLevelEmvTags(payload: string): Record<string, string> {
  const tags: Record<string, string> = {};
  let index = 0;
  while (index + 4 <= payload.length) {
    const id = payload.slice(index, index + 2);
    const length = Number(payload.slice(index + 2, index + 4));
    const valueStart = index + 4;
    const valueEnd = valueStart + length;
    tags[id] = payload.slice(valueStart, valueEnd);
    index = valueEnd;
    if (id === '63') break;
  }
  return tags;
}
