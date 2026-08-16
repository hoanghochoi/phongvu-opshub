import { Prisma } from '@prisma/client';
import * as XLSX from 'xlsx';

export type MapVietinStoredTransactionRow = {
  id: string;
  storeCode: string | null;
  transactionKey: string;
  transactionNumber: string | null;
  amount: number;
  content: string;
  orders?: string[] | null;
  orderSource?: string | null;
  orderUpdatedAt?: Date | null;
  orderUpdatedByUserId?: string | null;
  orderUpdatedByEmail?: string | null;
  orderTrackingStatus?: string | null;
  orderTrackingUpdatedAt?: Date | null;
  orderTrackingUpdatedByUserId?: string | null;
  orderTrackingUpdatedByEmail?: string | null;
  status: string | null;
  paidAt: Date | null;
  payerName: string | null;
  payerAccount: string | null;
  incomeType?: string | null;
  incomeTypeSource?: string | null;
  incomeTypeUpdatedAt?: Date | null;
  incomeTypeUpdatedByUserId?: string | null;
  incomeTypeUpdatedByEmail?: string | null;
  rawData?: Prisma.JsonValue | null;
  firstSeenAt: Date;
  orderTransferRequests?: Array<{
    id: string;
    requestedOrders: string[];
    status: string;
    requestedByUserId?: string | null;
    requestedByEmail?: string | null;
    reviewNote?: string | null;
    createdAt: Date;
  }>;
};

type StoredPayer = { name: string | null; account: string | null };

export type MapVietinStatementResponseRuntimeConfig = {
  resolveStoredPayer: (row: {
    payerName?: string | null;
    payerAccount?: string | null;
    rawData?: Prisma.JsonValue | null;
  }) => StoredPayer;
  resolveStoredTransactionReference: (row: {
    transactionNumber?: string | null;
    rawData?: Prisma.JsonValue | null;
  }) => string | null;
  resolveStoredReceivingAccount: (row: {
    rawData?: Prisma.JsonValue | null;
  }) => string | null;
  storedIncomeType: (row: {
    content?: string | null;
    storeCode?: string | null;
    payerAccount?: string | null;
    incomeType?: string | null;
  }) => string;
  storedOrderTrackingStatus: (row: {
    orderTrackingStatus?: string | null;
  }) => string;
  isStatementOrderTransferWindowOpen: (row: {
    paidAt?: Date | null;
    firstSeenAt?: Date | null;
  }) => boolean;
  mapIncomeTypeLabel: (incomeType: string) => string;
  orderTrackingFollowing: string;
  orderTrackingUnfollowed: string;
  orderSourceOffset: string;
  statementOrderTransferPendingStatus: string;
  statementOrderTransferApprovedStatus: string;
  orderActionRequiresStatementPermissionMessage: string;
  orderTransferWindowForbiddenMessage: string;
  incomeTypeSourceAuto: string;
  vietnamUtcOffsetHours: number;
};

export class MapVietinStatementResponseRuntime {
  constructor(
    private readonly config: MapVietinStatementResponseRuntimeConfig,
  ) {}

  toStoredTransactionDto(
    row: MapVietinStoredTransactionRow,
    options: {
      canEditProtectedOrders?: boolean;
      canUseStatements?: boolean;
      canEditIncomeType?: boolean;
      canManageTracking?: boolean;
    } = {},
  ) {
    const payer = this.config.resolveStoredPayer(row);
    const incomeType = this.config.storedIncomeType(row);
    const orders = row.orders || [];
    const pendingTransferRequest = row.orderTransferRequests?.[0] || null;
    const canUseStatements = options.canUseStatements !== false;
    const transferWindowOpen =
      this.config.isStatementOrderTransferWindowOpen(row);
    const orderTrackingStatus = this.config.storedOrderTrackingStatus(row);
    const isFollowing =
      orderTrackingStatus === this.config.orderTrackingFollowing;
    const hasStoreCode = Boolean(row.storeCode);
    const canEditOrders =
      canUseStatements &&
      isFollowing &&
      !pendingTransferRequest &&
      (orders.length === 0 || transferWindowOpen);
    let orderEditBlockedReason: string | null = null;
    if (!canEditOrders) {
      orderEditBlockedReason = !canUseStatements
        ? this.config.orderActionRequiresStatementPermissionMessage
        : !isFollowing
          ? 'Giao dịch đang Bỏ theo dõi. Vui lòng Theo dõi lại trước khi cập nhật mã đơn.'
          : pendingTransferRequest
            ? 'Giao dịch đang chờ Kế toán xác nhận.'
            : this.config.orderTransferWindowForbiddenMessage;
    }
    const canRequestOrderTransfer = canEditOrders && hasStoreCode;
    let orderTransferBlockedReason: string | null = null;
    if (!canRequestOrderTransfer) {
      orderTransferBlockedReason = orderEditBlockedReason;
    }
    return {
      id: row.id,
      storeId: row.storeCode,
      transactionKey: row.transactionKey,
      transactionNumber: row.transactionNumber,
      transactionReference: this.config.resolveStoredTransactionReference(row),
      amount: row.amount,
      content: row.content,
      orders,
      orderSource: row.orderSource || null,
      orderUpdatedAt: row.orderUpdatedAt || null,
      orderUpdatedByUserId: row.orderUpdatedByUserId || null,
      orderUpdatedByEmail: row.orderUpdatedByEmail || null,
      orderTrackingStatus,
      orderTrackingUpdatedAt: row.orderTrackingUpdatedAt || null,
      orderTrackingUpdatedByUserId: row.orderTrackingUpdatedByUserId || null,
      orderTrackingUpdatedByEmail: row.orderTrackingUpdatedByEmail || null,
      canManageOrderTracking:
        canUseStatements &&
        !pendingTransferRequest &&
        options.canManageTracking === true,
      orderTrackingActionBlockedReason: pendingTransferRequest
        ? 'Giao dịch đang có yêu cầu chờ xử lý.'
        : options.canManageTracking === true
          ? null
          : 'Bạn không có quyền thay đổi trạng thái theo dõi giao dịch.',
      canEditOrders,
      orderEditBlockedReason,
      canRequestOrderTransfer,
      orderTransferRequestBlockedReason: orderTransferBlockedReason,
      hasPendingOrderTransferRequest: Boolean(pendingTransferRequest),
      orderTransferRequestId: pendingTransferRequest?.id || null,
      orderTransferRequestedOrders:
        pendingTransferRequest?.requestedOrders || [],
      orderTransferRequestedByUserId:
        pendingTransferRequest?.requestedByUserId || null,
      orderTransferRequestedByEmail:
        pendingTransferRequest?.requestedByEmail || null,
      orderTransferRequestedAt: pendingTransferRequest?.createdAt || null,
      orderTransferReviewNote: pendingTransferRequest?.reviewNote || null,
      orderTransferStatus: pendingTransferRequest
        ? this.config.statementOrderTransferPendingStatus
        : row.orderSource === this.config.orderSourceOffset
          ? this.config.statementOrderTransferApprovedStatus
          : null,
      isOrderOffsetConfirmed: row.orderSource === this.config.orderSourceOffset,
      status: row.status,
      paidAt: row.paidAt,
      payerName: payer.name,
      payerAccount: payer.account,
      receivingAccount: this.config.resolveStoredReceivingAccount(row),
      incomeType,
      incomeTypeLabel: this.config.mapIncomeTypeLabel(incomeType),
      incomeTypeSource:
        row.incomeTypeSource || this.config.incomeTypeSourceAuto,
      incomeTypeUpdatedAt: row.incomeTypeUpdatedAt || null,
      incomeTypeUpdatedByUserId: row.incomeTypeUpdatedByUserId || null,
      incomeTypeUpdatedByEmail: row.incomeTypeUpdatedByEmail || null,
      canEditIncomeType: canUseStatements && options.canEditIncomeType === true,
      firstSeenAt: row.firstSeenAt,
    };
  }

  toStatementsXlsx(rows: MapVietinStoredTransactionRow[]) {
    const headers = [
      'Mã showroom',
      'Loại giao dịch',
      'Mã sao kê',
      'Số tiền',
      'Nội dung chuyển khoản',
      'Mã đơn hàng',
      'Trạng thái theo dõi',
      'Trạng thái',
      'Ngày giao dịch',
      'Người chuyển',
      'Tài khoản chuyển',
      'Tài khoản nhận',
      'Lần đầu thấy',
      'Nguồn đơn hàng',
      'Người sửa đơn hàng',
      'Thời gian sửa đơn hàng',
    ];
    const values: unknown[][] = [headers];
    for (const row of rows) {
      const payer = this.config.resolveStoredPayer(row);
      const transactionReference =
        this.config.resolveStoredTransactionReference(row);
      const statementNumber = transactionReference || row.transactionNumber;
      const incomeType = this.config.storedIncomeType(row);
      values.push([
        this.csvText(row.storeCode),
        this.config.mapIncomeTypeLabel(incomeType),
        this.csvText(statementNumber),
        this.csvAmountValue(row.amount),
        this.csvText(row.content),
        this.csvText((row.orders || []).join('\n')),
        this.config.storedOrderTrackingStatus(row) ===
        this.config.orderTrackingUnfollowed
          ? 'Bỏ theo dõi'
          : 'Đang theo dõi',
        this.csvText(row.status),
        this.csvVietnamDate(row.paidAt),
        this.csvText(payer.name),
        this.csvText(payer.account),
        this.csvText(this.config.resolveStoredReceivingAccount(row)),
        this.csvVietnamDate(row.firstSeenAt),
        this.csvText(row.orderSource),
        this.csvText(row.orderUpdatedByEmail),
        this.csvVietnamDate(row.orderUpdatedAt),
      ]);
    }
    const worksheet = XLSX.utils.aoa_to_sheet(values);
    worksheet['!cols'] = [
      { wch: 14 },
      { wch: 18 },
      { wch: 24 },
      { wch: 16 },
      { wch: 52 },
      { wch: 30 },
      { wch: 20 },
      { wch: 16 },
      { wch: 22 },
      { wch: 28 },
      { wch: 24 },
      { wch: 24 },
      { wch: 22 },
      { wch: 18 },
      { wch: 28 },
      { wch: 22 },
    ];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Sao kê');
    return XLSX.write(workbook, { bookType: 'xlsx', type: 'buffer' });
  }

  private csvAmountValue(value: unknown) {
    const amount = Number(value);
    return Number.isFinite(amount) ? Math.trunc(amount) : null;
  }

  private csvVietnamDate(value: unknown) {
    if (!value) return '';
    const date = value instanceof Date ? value : new Date(String(value));
    if (Number.isNaN(date.getTime())) return '';
    const vietnamTime = new Date(
      date.getTime() + this.config.vietnamUtcOffsetHours * 60 * 60 * 1000,
    );
    const two = (part: number) => String(part).padStart(2, '0');
    return [
      `${two(vietnamTime.getUTCDate())}/${two(vietnamTime.getUTCMonth() + 1)}/${vietnamTime.getUTCFullYear()}`,
      `${two(vietnamTime.getUTCHours())}:${two(vietnamTime.getUTCMinutes())}:${two(vietnamTime.getUTCSeconds())}`,
    ].join(' ');
  }

  private csvText(value: unknown) {
    return value === null || value === undefined ? '' : String(value);
  }
}
