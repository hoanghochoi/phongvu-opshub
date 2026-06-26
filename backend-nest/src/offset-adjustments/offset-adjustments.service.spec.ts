import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { OffsetAdjustmentsService } from './offset-adjustments.service';

describe('OffsetAdjustmentsService', () => {
  let prisma: any;
  let redis: { publishMessage: jest.Mock };
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
    service = new OffsetAdjustmentsService(prisma as any, redis as any);
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
        adjustmentId: 'offset-1',
        storeCode: 'CP01',
        status: 'PENDING_ACC',
      }),
    );
    expect(redis.publishMessage).not.toHaveBeenCalledWith(
      'PAYMENT_NOTIFICATION_READY',
      expect.anything(),
    );
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
        adjustmentId: 'offset-1',
        status: 'PENDING_ACC',
      }),
    );
  });

  it('blocks non-reviewers from all-store list requests', async () => {
    await expect(
      service.list(srUser, { allStores: 'true' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
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
    expect(csv).toContain('=""26062500000001""');
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
