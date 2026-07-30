import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { OffsetAdjustmentsService } from './offset-adjustments.service';

describe('OffsetAdjustmentsService', () => {
  let prisma: any;
  let redis: { publishMessage: jest.Mock };
  let notificationsService: { readAtByNotificationId: jest.Mock };
  let salesReportErpService: { lookupOrderStatus: jest.Mock };
  let service: OffsetAdjustmentsService;

  const srUser = {
    id: 'sr-1',
    email: 'sr@phongvu.vn',
    role: 'USER',
    storeId: 'store-uuid-cp01',
    departmentCode: 'SALES',
  };

  const accUser = {
    id: 'acc-1',
    email: 'acc@phongvu.vn',
    role: 'USER',
    departmentCode: 'ACC',
  };

  beforeEach(() => {
    prisma = {
      $transaction: jest.fn(async (callback: (tx: any) => unknown) =>
        callback(prisma),
      ),
      $queryRaw: jest.fn().mockResolvedValue([]),
      store: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'store-uuid-cp01',
          storeId: 'CP01',
          storeName: 'CP01',
        }),
      },
      user: { findUnique: jest.fn() },
      organizationNode: { findMany: jest.fn().mockResolvedValue([]) },
      offsetAdjustment: {
        findMany: jest.fn(),
        count: jest.fn().mockResolvedValue(1),
        findFirst: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
      offsetAdjustmentHistory: {
        create: jest.fn().mockResolvedValue({ id: 'history-1' }),
      },
    };
    redis = { publishMessage: jest.fn().mockResolvedValue(undefined) };
    notificationsService = {
      readAtByNotificationId: jest.fn().mockResolvedValue(new Map()),
    };
    salesReportErpService = {
      lookupOrderStatus: jest.fn(async (orderCode: string) => ({
        orderCode,
        lifecycleStatus: orderCode.endsWith('01') ? 'CANCELLED' : 'COMPLETED',
        lifecycleVerified: true,
        grandTotal: 2000000,
      })),
    };
    service = new OffsetAdjustmentsService(
      prisma as any,
      redis as any,
      notificationsService as any,
      salesReportErpService as any,
    );
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(new Date('2026-06-25T03:00:00.000Z').getTime());
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('creates a single-order offset without touching payment notification channel', async () => {
    const row = offsetRow({
      id: 'offset-1',
      type: 'SINGLE_ORDER',
      oldOrderCode: '26062500000001',
      newOrderCode: '26062500000002',
    });
    prisma.offsetAdjustment.create.mockResolvedValue(row);

    const result = await service.create(srUser, {
      type: 'SINGLE_ORDER',
      oldOrderCode: '26062500000001',
      newOrderCode: '26062500000002',
      amount: 1500000,
      note: 'ghi chu',
    });

    expect(result.id).toBe('offset-1');
    expect(salesReportErpService.lookupOrderStatus).toHaveBeenCalledTimes(2);
    expect(prisma.offsetAdjustment.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          type: 'SINGLE_ORDER',
          storeCode: 'CP01',
          status: 'PENDING_ACC',
          oldOrderCode: '26062500000001',
          newOrderCode: '26062500000002',
          amount: 1500000,
        }),
      }),
    );
    expect(redis.publishMessage).toHaveBeenCalledWith(
      'OFFSET_ADJUSTMENT_UPDATED',
      expect.objectContaining({
        schemaVersion: 1,
        type: 'OFFSET_ADJUSTMENT_NOTIFICATION',
        audience: expect.objectContaining({
          storeCodes: ['CP01'],
          roles: ['SUPER_ADMIN'],
          departmentCodes: ['ACC', 'FIN_ACC'],
          organizationAccessCodes: ['ACC', 'FIN_ACC'],
          featureCodes: ['OFFSET_ADJUSTMENTS'],
        }),
        payload: expect.objectContaining({
          adjustmentId: 'offset-1',
          storeCode: 'CP01',
          status: 'PENDING_ACC',
        }),
      }),
    );
    expect(redis.publishMessage).not.toHaveBeenCalledWith(
      'PAYMENT_NOTIFICATION_READY',
      expect.anything(),
    );
  });

  it('keeps ERP selling channel separate from the Offset showroom and source channel', async () => {
    salesReportErpService.lookupOrderStatus
      .mockResolvedValueOnce({
        lifecycleStatus: 'CANCELLED',
        lifecycleVerified: true,
        grandTotal: 1500000,
        storeCode: 'CP99',
        salesChannel: 'Kênh Online',
      })
      .mockResolvedValueOnce({
        lifecycleStatus: 'COMPLETED',
        lifecycleVerified: true,
        grandTotal: 1500000,
        storeCode: 'CP88',
        salesChannel: 'Kênh Đối tác',
      });
    prisma.offsetAdjustment.create.mockResolvedValue(
      offsetRow({
        type: 'SINGLE_ORDER',
        oldOrderCode: '26062500000001',
        newOrderCode: '26062500000002',
      }),
    );

    const result = await service.create(srUser, {
      type: 'SINGLE_ORDER',
      oldOrderCode: '26062500000001',
      newOrderCode: '26062500000002',
      amount: 1500000,
    });

    expect(salesReportErpService.lookupOrderStatus).toHaveBeenNthCalledWith(
      1,
      '26062500000001',
      null,
    );
    expect(salesReportErpService.lookupOrderStatus).toHaveBeenNthCalledWith(
      2,
      '26062500000002',
      null,
    );
    expect(result).toMatchObject({
      storeCode: 'CP01',
      creationChannel: 'Cấn trừ trên OpsHub',
      salesChannels: [
        { orderCode: '26062500000001', salesChannel: 'Kênh Online' },
        { orderCode: '26062500000002', salesChannel: 'Kênh Đối tác' },
      ],
    });
    expect(prisma.offsetAdjustmentHistory.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          snapshot: expect.objectContaining({
            channels: {
              creationChannel: 'Cấn trừ trên OpsHub',
              salesChannels: [
                { orderCode: '26062500000001', salesChannel: 'Kênh Online' },
                { orderCode: '26062500000002', salesChannel: 'Kênh Đối tác' },
              ],
            },
          }),
        }),
      }),
    );
  });

  it('does not present an ERP payment method as the selling channel', async () => {
    salesReportErpService.lookupOrderStatus.mockResolvedValue({
      lifecycleStatus: 'COMPLETED',
      lifecycleVerified: true,
      grandTotal: 250000,
      salesChannel: null,
      paymentMethods: ['VNPAY', 'cash'],
    });
    prisma.offsetAdjustment.findFirst.mockResolvedValue(null);
    prisma.offsetAdjustment.create.mockResolvedValue(
      offsetRow({ type: 'ZALOPAY', amount: 200000 }),
    );

    const result = await service.create(srUser, {
      type: 'ZALOPAY',
      orderCode: '26062500000003',
      scanDate: '2026-06-25',
      editContentKind: 'CUSTOMER_OFFSET',
      transactionCode: 'TXN-ZALOPAY',
      amount: 200000,
    });

    expect(result.salesChannels).toEqual([
      {
        orderCode: '26062500000003',
        salesChannel: 'ERP (chưa có tên kênh bán)',
      },
    ]);
    expect(JSON.stringify(result.salesChannels)).not.toContain('VNPAY');
    expect(JSON.stringify(result.salesChannels)).not.toContain('Tiền mặt');
  });

  it.each(['PENDING', 'COMPLETED', 'RETURNED_FULL'])(
    'blocks a single-order offset when the old order lifecycle is %s',
    async (lifecycleStatus) => {
      salesReportErpService.lookupOrderStatus
        .mockResolvedValueOnce({
          lifecycleStatus,
          lifecycleVerified: true,
          grandTotal: 1500000,
        })
        .mockResolvedValueOnce({
          lifecycleStatus: 'COMPLETED',
          lifecycleVerified: true,
          grandTotal: 1500000,
        });

      await expect(
        service.create(srUser, {
          type: 'SINGLE_ORDER',
          oldOrderCode: '26062500000001',
          newOrderCode: '26062500000002',
          amount: 1500000,
        }),
      ).rejects.toThrow('Đã hủy hoặc Hoàn một phần');
      expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
      expect(prisma.offsetAdjustmentHistory.create).not.toHaveBeenCalled();
      expect(redis.publishMessage).not.toHaveBeenCalled();
    },
  );

  it.each(['CANCELLED', 'RETURNED_FULL'])(
    'blocks a single-order offset when the new order lifecycle is %s',
    async (lifecycleStatus) => {
      salesReportErpService.lookupOrderStatus
        .mockResolvedValueOnce({
          lifecycleStatus: 'COMPLETED_PARTIAL_RETURN',
          lifecycleVerified: true,
          grandTotal: 1500000,
        })
        .mockResolvedValueOnce({
          lifecycleStatus,
          lifecycleVerified: true,
          grandTotal: 1500000,
        });

      await expect(
        service.create(srUser, {
          type: 'SINGLE_ORDER',
          oldOrderCode: '26062500000001',
          newOrderCode: '26062500000002',
          amount: 1500000,
        }),
      ).rejects.toThrow('đã hủy hoặc hoàn toàn phần');
      expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
    },
  );

  it('accepts an amount equal to the new order total', async () => {
    salesReportErpService.lookupOrderStatus
      .mockResolvedValueOnce({
        lifecycleStatus: 'CANCELLED',
        lifecycleVerified: true,
        grandTotal: 500000,
      })
      .mockResolvedValueOnce({
        lifecycleStatus: 'PENDING',
        lifecycleVerified: true,
        grandTotal: 1500000,
      });
    prisma.offsetAdjustment.create.mockResolvedValue(
      offsetRow({
        type: 'SINGLE_ORDER',
        oldOrderCode: '26062500000001',
        newOrderCode: '26062500000002',
        amount: 1500000,
      }),
    );

    await expect(
      service.create(srUser, {
        type: 'SINGLE_ORDER',
        oldOrderCode: '26062500000001',
        newOrderCode: '26062500000002',
        amount: 1500000,
      }),
    ).resolves.toMatchObject({ amount: 1500000 });
  });

  it('blocks an amount above the order total without writing', async () => {
    salesReportErpService.lookupOrderStatus
      .mockResolvedValueOnce({
        lifecycleStatus: 'CANCELLED',
        lifecycleVerified: true,
        grandTotal: 500000,
      })
      .mockResolvedValueOnce({
        lifecycleStatus: 'COMPLETED',
        lifecycleVerified: true,
        grandTotal: 1499999,
      });

    await expect(
      service.create(srUser, {
        type: 'SINGLE_ORDER',
        oldOrderCode: '26062500000001',
        newOrderCode: '26062500000002',
        amount: 1500000,
      }),
    ).rejects.toThrow('không được vượt quá giá trị đơn hàng mới');
    expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
    expect(prisma.offsetAdjustmentHistory.create).not.toHaveBeenCalled();
  });

  it.each([
    ['old', 0, 'Không tìm thấy đơn hàng cũ'],
    ['new', 1, 'Không tìm thấy đơn hàng mới'],
  ])(
    'returns a clear error when the %s order does not exist',
    async (_phase, rejectedCall, message) => {
      if (rejectedCall === 0) {
        salesReportErpService.lookupOrderStatus
          .mockRejectedValueOnce(new BadRequestException('not found'))
          .mockResolvedValueOnce({
            lifecycleStatus: 'COMPLETED',
            lifecycleVerified: true,
            grandTotal: 1500000,
          });
      } else {
        salesReportErpService.lookupOrderStatus
          .mockResolvedValueOnce({
            lifecycleStatus: 'CANCELLED',
            lifecycleVerified: true,
            grandTotal: 1500000,
          })
          .mockRejectedValueOnce(new BadRequestException('not found'));
      }

      await expect(
        service.create(srUser, {
          type: 'SINGLE_ORDER',
          oldOrderCode: '26062500000001',
          newOrderCode: '26062500000002',
          amount: 100000,
        }),
      ).rejects.toThrow(message);
      expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
      expect(prisma.offsetAdjustmentHistory.create).not.toHaveBeenCalled();
      expect(redis.publishMessage).not.toHaveBeenCalled();
    },
  );

  it('fails closed when the ERP lookup times out', async () => {
    salesReportErpService.lookupOrderStatus.mockRejectedValue(
      new Error('timeout'),
    );

    await expect(
      service.create(srUser, {
        type: 'SINGLE_ORDER',
        oldOrderCode: '26062500000001',
        newOrderCode: '26062500000002',
        amount: 100000,
      }),
    ).rejects.toThrow('Chưa thể kiểm tra đơn hàng trên hệ thống bán hàng');
    expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
    expect(prisma.offsetAdjustmentHistory.create).not.toHaveBeenCalled();
    expect(redis.publishMessage).not.toHaveBeenCalled();
  });

  it.each(['VNPAY_QROFF', 'ZALOPAY', 'SHOPEEPAY'])(
    'accepts verified %s orders without restricting their lifecycle',
    async (type) => {
      salesReportErpService.lookupOrderStatus.mockResolvedValue({
        lifecycleStatus: 'RETURNED_FULL',
        lifecycleVerified: true,
        grandTotal: 250000,
      });
      prisma.offsetAdjustment.findFirst.mockResolvedValue(null);
      prisma.offsetAdjustment.create.mockResolvedValue(
        offsetRow({ type, amount: 200000 }),
      );

      await expect(
        service.create(srUser, {
          type,
          orderCode: '26062500000003',
          scanDate: '2026-06-25',
          editContentKind: 'CUSTOMER_OFFSET',
          transactionCode: `TXN-${type}`,
          amount: 200000,
        }),
      ).resolves.toMatchObject({ type, amount: 200000 });
    },
  );

  it('fails closed when ERP does not return an order total', async () => {
    salesReportErpService.lookupOrderStatus.mockResolvedValue({
      lifecycleStatus: 'COMPLETED',
      lifecycleVerified: true,
      grandTotal: null,
    });
    prisma.offsetAdjustment.findFirst.mockResolvedValue(null);

    await expect(
      service.create(srUser, {
        type: 'SHOPEEPAY',
        orderCode: '26062500000003',
        scanDate: '2026-06-25',
        editContentKind: 'CUSTOMER_OFFSET',
        transactionCode: 'TXN-NEW',
        amount: 250000,
      }),
    ).rejects.toThrow('Chưa lấy được giá trị đơn hàng');
    expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
  });

  it('fails closed when ERP has not verified a wallet order lifecycle', async () => {
    salesReportErpService.lookupOrderStatus.mockResolvedValue({
      lifecycleStatus: 'PENDING',
      lifecycleVerified: false,
      grandTotal: 250000,
    });
    prisma.offsetAdjustment.findFirst.mockResolvedValue(null);

    await expect(
      service.create(srUser, {
        type: 'VNPAY_QROFF',
        orderCode: '26062500000003',
        scanDate: '2026-06-25',
        editContentKind: 'CUSTOMER_OFFSET',
        transactionCode: 'TXN-NEW',
        amount: 250000,
      }),
    ).rejects.toThrow('Chưa xác minh được trạng thái đơn hàng');
    expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
    expect(prisma.offsetAdjustmentHistory.create).not.toHaveBeenCalled();
    expect(redis.publishMessage).not.toHaveBeenCalled();
  });

  it('keeps a committed create successful when realtime publication fails', async () => {
    const row = offsetRow({ amount: 250000 });
    prisma.offsetAdjustment.findFirst.mockResolvedValue(null);
    prisma.offsetAdjustment.create.mockResolvedValue(row);
    redis.publishMessage.mockRejectedValue(new Error('redis unavailable'));

    await expect(
      service.create(srUser, {
        type: 'ZALOPAY',
        orderCode: '26062500000003',
        scanDate: '2026-06-25',
        editContentKind: 'CUSTOMER_OFFSET',
        transactionCode: 'TXN-NEW',
        amount: 250000,
      }),
    ).resolves.toMatchObject({ id: row.id });
  });

  it('rejects a single-order offset when old and new orders match', async () => {
    await expect(
      service.create(srUser, {
        type: 'SINGLE_ORDER',
        oldOrderCode: '26062500000001',
        newOrderCode: '26062500000001',
        amount: 100000,
      }),
    ).rejects.toThrow('Mã đơn cũ và mã đơn mới không được trùng nhau.');
    expect(prisma.offsetAdjustment.create).not.toHaveBeenCalled();
  });

  it('blocks duplicate wallet order or transaction only within the same type', async () => {
    prisma.offsetAdjustment.findFirst.mockResolvedValue(
      offsetRow({
        id: 'offset-old',
        type: 'VNPAY_QROFF',
        orderCode: '26062500000003',
        transactionCode: 'TXN-OLD',
      }),
    );

    await expect(
      service.create(srUser, {
        type: 'VNPAY_QROFF',
        orderCode: '26062500000003',
        scanDate: '2026-06-25',
        editContentKind: 'CUSTOMER_OFFSET',
        transactionCode: 'TXN-NEW',
        amount: 100000,
      }),
    ).rejects.toThrow('Đơn hàng đã có hồ sơ cấn trừ loại này.');
    expect(prisma.offsetAdjustment.findFirst).toHaveBeenCalledWith({
      where: expect.objectContaining({ type: 'VNPAY_QROFF' }),
    });
    expect(salesReportErpService.lookupOrderStatus).not.toHaveBeenCalled();
  });

  it('requires CT code when ACC completes VNPAY QROFF', async () => {
    prisma.offsetAdjustment.findFirst.mockResolvedValue(
      offsetRow({ id: 'offset-vnpay', type: 'VNPAY_QROFF' }),
    );

    await expect(service.complete(accUser, 'offset-vnpay', {})).rejects.toThrow(
      'Vui lòng nhập Mã CT.',
    );

    const approved = offsetRow({
      id: 'offset-vnpay',
      type: 'VNPAY_QROFF',
      status: 'APPROVED',
      ctCode: 'CT-001',
      reviewedByEmail: 'acc@phongvu.vn',
    });
    prisma.offsetAdjustment.update.mockResolvedValue(approved);

    const result = await service.complete(accUser, 'offset-vnpay', {
      ctCode: 'CT-001',
    });

    expect(result.status).toBe('APPROVED');
    expect(prisma.offsetAdjustment.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ status: 'APPROVED', ctCode: 'CT-001' }),
      }),
    );
  });

  it('lets SR resubmit a rejected row and sends it back to ACC', async () => {
    prisma.offsetAdjustment.findFirst
      .mockResolvedValueOnce(
        offsetRow({ id: 'offset-1', status: 'REJECTED_NEEDS_FIX' }),
      )
      .mockResolvedValueOnce(null);
    const resubmitted = offsetRow({ id: 'offset-1', status: 'PENDING_ACC' });
    prisma.offsetAdjustment.update.mockResolvedValue(resubmitted);

    const result = await service.resubmit(srUser, 'offset-1', {
      orderCode: '26062500000004',
      scanDate: '2026-06-25',
      editContentKind: 'TECHNICIAN_OFFSET',
      transactionCode: 'TXN-004',
      amount: 250000,
    });

    expect(result.status).toBe('PENDING_ACC');
    expect(prisma.offsetAdjustmentHistory.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ action: 'RESUBMITTED' }),
      }),
    );
    expect(redis.publishMessage).toHaveBeenCalledWith(
      'OFFSET_ADJUSTMENT_UPDATED',
      expect.objectContaining({
        schemaVersion: 1,
        type: 'OFFSET_ADJUSTMENT_NOTIFICATION',
        payload: expect.objectContaining({
          adjustmentId: 'offset-1',
          status: 'PENDING_ACC',
        }),
      }),
    );
  });

  it('does not update a rejected row when ERP validation fails on resubmit', async () => {
    prisma.offsetAdjustment.findFirst
      .mockResolvedValueOnce(
        offsetRow({ id: 'offset-1', status: 'REJECTED_NEEDS_FIX' }),
      )
      .mockResolvedValueOnce(null);
    salesReportErpService.lookupOrderStatus.mockRejectedValue(
      new Error('erp unavailable'),
    );

    await expect(
      service.resubmit(srUser, 'offset-1', { amount: 250000 }),
    ).rejects.toThrow('Chưa thể kiểm tra đơn hàng trên hệ thống bán hàng');
    expect(prisma.offsetAdjustment.update).not.toHaveBeenCalled();
    expect(prisma.offsetAdjustmentHistory.create).not.toHaveBeenCalled();
    expect(redis.publishMessage).not.toHaveBeenCalled();
  });

  it('rejects a resubmit when the row changes during the ERP wait', async () => {
    prisma.offsetAdjustment.findFirst
      .mockResolvedValueOnce(
        offsetRow({ id: 'offset-1', status: 'REJECTED_NEEDS_FIX' }),
      )
      .mockResolvedValueOnce(null);
    prisma.offsetAdjustment.update.mockRejectedValue({ code: 'P2025' });

    await expect(
      service.resubmit(srUser, 'offset-1', { amount: 250000 }),
    ).rejects.toThrow('Dữ liệu hồ sơ vừa thay đổi');
    expect(prisma.offsetAdjustmentHistory.create).not.toHaveBeenCalled();
    expect(redis.publishMessage).not.toHaveBeenCalled();
  });

  it('atomically completes selected non-VNPAY offsets', async () => {
    const rows = [
      offsetRow({ id: 'offset-1', type: 'SINGLE_ORDER' }),
      offsetRow({ id: 'offset-2', type: 'ZALOPAY' }),
    ];
    prisma.offsetAdjustment.findMany.mockResolvedValue(rows);
    prisma.offsetAdjustment.update.mockImplementation(async ({ where }: any) =>
      offsetRow({
        id: where.id,
        type: where.id === 'offset-1' ? 'SINGLE_ORDER' : 'ZALOPAY',
        status: 'APPROVED',
        reviewedByEmail: 'acc@phongvu.vn',
      }),
    );

    await expect(
      service.batchComplete(accUser, { ids: ['offset-2', 'offset-1'] }),
    ).resolves.toEqual({ processedCount: 2 });
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(prisma.offsetAdjustment.update).toHaveBeenCalledTimes(2);
    expect(prisma.offsetAdjustmentHistory.create).toHaveBeenCalledTimes(2);
    expect(redis.publishMessage).toHaveBeenCalledTimes(2);
    expect(prisma.$queryRaw.mock.calls[0][0].sql).toContain('ORDER BY "id"');
    expect(prisma.offsetAdjustment.update.mock.calls[0][0].where.id).toBe(
      'offset-1',
    );
    expect(prisma.offsetAdjustment.update.mock.calls[1][0].where.id).toBe(
      'offset-2',
    );
  });

  it.each(['complete', 'reject'])(
    'prevents stale single %s from overwriting a completed batch',
    async (action) => {
      let state = offsetRow({ id: 'offset-1', type: 'ZALOPAY' });
      let transactionCall = 0;
      let releaseSingleTransaction!: () => void;
      let markSingleTransactionStarted!: () => void;
      const singleTransactionStarted = new Promise<void>((resolve) => {
        markSingleTransactionStarted = resolve;
      });
      const singleTransactionRelease = new Promise<void>((resolve) => {
        releaseSingleTransaction = resolve;
      });

      prisma.offsetAdjustment.findFirst.mockImplementation(async () => ({
        ...state,
      }));
      prisma.offsetAdjustment.findMany.mockImplementation(async () => [
        { ...state },
      ]);
      prisma.offsetAdjustment.update.mockImplementation(
        async ({ where, data }: any) => {
          if (
            (where.status && where.status !== state.status) ||
            (where.updatedAt &&
              where.updatedAt.getTime() !== state.updatedAt.getTime())
          ) {
            throw { code: 'P2025' };
          }
          state = {
            ...state,
            ...data,
            updatedAt: new Date('2026-06-25T03:01:00.000Z'),
          };
          return { ...state };
        },
      );
      prisma.$transaction.mockImplementation(async (callback: any) => {
        transactionCall += 1;
        if (transactionCall === 1) {
          markSingleTransactionStarted();
          await singleTransactionRelease;
        }
        return callback(prisma);
      });

      const staleSingle =
        action === 'complete'
          ? service.complete(accUser, 'offset-1', {})
          : service.reject(accUser, 'offset-1', { reason: 'Sai thông tin' });
      await singleTransactionStarted;

      await expect(
        service.batchComplete(accUser, { ids: ['offset-1'] }),
      ).resolves.toEqual({ processedCount: 1 });
      releaseSingleTransaction();

      await expect(staleSingle).rejects.toThrow('Dữ liệu hồ sơ vừa thay đổi');
      expect(state.status).toBe('APPROVED');
      expect(prisma.offsetAdjustmentHistory.create).toHaveBeenCalledTimes(1);
      expect(redis.publishMessage).toHaveBeenCalledTimes(1);
    },
  );

  it.each([
    [['offset-1', 'offset-1'], 'khác nhau'],
    [Array.from({ length: 101 }, (_, index) => `offset-${index}`), '1 đến 100'],
  ])('rejects invalid batch id lists before lookup', async (ids, message) => {
    await expect(service.batchComplete(accUser, { ids })).rejects.toThrow(
      message,
    );
    expect(prisma.offsetAdjustment.findMany).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects a batch containing a missing or out-of-scope offset', async () => {
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({ id: 'offset-1', type: 'ZALOPAY' }),
    ]);

    await expect(
      service.batchComplete(accUser, { ids: ['offset-1', 'offset-2'] }),
    ).rejects.toThrow('không còn khả dụng trong phạm vi của bạn');
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.offsetAdjustment.update).not.toHaveBeenCalled();
  });

  it('rejects a mixed VNPAY batch before any write', async () => {
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({ id: 'offset-1', type: 'ZALOPAY' }),
      offsetRow({ id: 'offset-2', type: 'VNPAY_QROFF' }),
    ]);

    await expect(
      service.batchComplete(accUser, { ids: ['offset-1', 'offset-2'] }),
    ).rejects.toThrow('cần nhập Mã CT và xác nhận riêng');
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.offsetAdjustment.update).not.toHaveBeenCalled();
  });

  it('rolls back a batch when one selected offset changed', async () => {
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({ id: 'offset-1', type: 'ZALOPAY' }),
      offsetRow({ id: 'offset-2', type: 'SHOPEEPAY' }),
    ]);
    prisma.offsetAdjustment.update
      .mockResolvedValueOnce(offsetRow({ id: 'offset-1', status: 'APPROVED' }))
      .mockRejectedValueOnce({ code: 'P2025' });

    await expect(
      service.batchComplete(accUser, { ids: ['offset-1', 'offset-2'] }),
    ).rejects.toThrow('Dữ liệu hồ sơ vừa thay đổi');
    expect(redis.publishMessage).not.toHaveBeenCalled();
  });

  it('returns an actionable conflict when the batch transaction is aborted', async () => {
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({ id: 'offset-1', type: 'ZALOPAY' }),
    ]);
    prisma.$transaction.mockRejectedValueOnce({ code: 'P2034' });

    await expect(
      service.batchComplete(accUser, { ids: ['offset-1'] }),
    ).rejects.toThrow('Dữ liệu hồ sơ vừa thay đổi');
    expect(redis.publishMessage).not.toHaveBeenCalled();
  });

  it('blocks non-reviewers from all-store list requests', async () => {
    await expect(
      service.list(srUser, { allStores: 'true' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('lists rejected offset notifications only for the requesting SR user', async () => {
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({
        id: 'offset-rejected',
        status: 'REJECTED_NEEDS_FIX',
        rejectReason: 'Sai mã đơn',
        createdByUserId: 'sr-1',
      }),
    ]);
    prisma.offsetAdjustment.count.mockResolvedValue(1);

    const result = await service.list(srUser, {
      status: 'NOTIFICATION',
      page: 0,
      limit: 20,
    });

    expect(result).toMatchObject({
      total: 1,
      canReview: false,
      list: [{ id: 'offset-rejected', status: 'REJECTED_NEEDS_FIX' }],
    });
    expect(prisma.offsetAdjustment.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          AND: [
            { storeCode: 'CP01' },
            { status: 'REJECTED_NEEDS_FIX', createdByUserId: 'sr-1' },
          ],
        },
      }),
    );
  });

  it('lists pending offset notifications for reviewers', async () => {
    const readAt = new Date('2026-06-26T03:00:00.000Z');
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({ id: 'offset-pending', status: 'PENDING_ACC' }),
    ]);
    prisma.offsetAdjustment.count.mockResolvedValue(1);
    notificationsService.readAtByNotificationId.mockResolvedValue(
      new Map([['offset-pending', readAt]]),
    );

    const result = await service.list(accUser, {
      allStores: 'true',
      status: 'NOTIFICATION',
      page: 0,
      limit: 20,
    });

    expect(result).toMatchObject({
      total: 1,
      canReview: true,
      list: [
        {
          id: 'offset-pending',
          status: 'PENDING_ACC',
          notificationReadAt: readAt.toISOString(),
        },
      ],
    });
    expect(notificationsService.readAtByNotificationId).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'acc-1' }),
      'offset_adjustment',
      ['offset-pending'],
    );
    expect(prisma.offsetAdjustment.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { status: 'PENDING_ACC' },
      }),
    );
  });

  it('exports filtered offset adjustments as Excel-friendly CSV', async () => {
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({
        id: 'offset-export',
        type: 'SINGLE_ORDER',
        oldOrderCode: '26062500000001',
        newOrderCode: '26062500000002',
        orderCode: null,
        scanDate: null,
        editContentKind: null,
        transactionCode: null,
        amount: 1500000,
        note: '=HYPERLINK("https://invalid.example")',
      }),
    ]);

    const csv = await service.exportCsv(accUser, {
      allStores: 'true',
      type: 'SINGLE_ORDER',
      status: 'PENDING_ACC',
    });

    expect(prisma.offsetAdjustment.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          AND: [{ type: 'SINGLE_ORDER' }, { status: 'PENDING_ACC' }],
        },
        orderBy: { submittedAt: 'desc' },
      }),
    );
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toContain('Cấn trừ đơn');
    expect(csv).toContain('Chờ Kế toán xác nhận');
    expect(csv).toContain("'26062500000001");
    expect(csv).toContain("'=HYPERLINK");
    expect(csv).not.toContain(',=HYPERLINK');
  });

  it('returns persisted ERP and OpsHub channel labels from the latest history snapshot', async () => {
    prisma.offsetAdjustment.findMany.mockResolvedValue([
      offsetRow({
        history: [
          {
            snapshot: {
              channels: {
                creationChannel: 'Cấn trừ trên OpsHub',
                salesChannels: [
                  {
                    orderCode: '26062500000003',
                    salesChannel: 'Kênh Online',
                  },
                ],
              },
            },
          },
        ],
      }),
    ]);
    prisma.offsetAdjustment.count.mockResolvedValue(1);

    await expect(
      service.list(srUser, { page: 0, limit: 20 }),
    ).resolves.toMatchObject({
      list: [
        {
          creationChannel: 'Cấn trừ trên OpsHub',
          salesChannels: [
            { orderCode: '26062500000003', salesChannel: 'Kênh Online' },
          ],
        },
      ],
    });
  });
});

function offsetRow(overrides: Record<string, any> = {}) {
  const now = new Date('2026-06-25T03:00:00.000Z');
  return {
    id: 'offset-1',
    type: 'ZALOPAY',
    status: 'PENDING_ACC',
    storeCode: 'CP01',
    oldOrderCode: null,
    newOrderCode: null,
    orderCode: '26062500000003',
    scanDate: new Date('2026-06-24T17:00:00.000Z'),
    editContentKind: 'CUSTOMER_OFFSET',
    transactionCode: 'TXN-001',
    amount: 1500000,
    note: null,
    ctCode: null,
    rejectReason: null,
    createdByUserId: 'sr-1',
    createdByEmail: 'sr@phongvu.vn',
    reviewedByUserId: null,
    reviewedByEmail: null,
    submittedAt: now,
    reviewedAt: null,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}
