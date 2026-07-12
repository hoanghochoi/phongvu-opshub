import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';

export type SalesReportErpOrderItem = {
  sku: string | null;
  sellerSku: string | null;
  name: string | null;
  brandCode: string | null;
  brandName: string | null;
  productTypeCode: string | null;
  productTypeName: string | null;
  productGroupId: string | null;
  productGroupCode: string | null;
  productGroupName: string | null;
  categoryType: string | null;
  listingCategories: unknown[];
  quantity: number | null;
  sellPrice: number | null;
  finalSellPrice: number | null;
  rowTotal: number | null;
  raw: Record<string, unknown>;
};

export type SalesReportErpPayment = {
  paymentMethod: string | null;
  amount: number | null;
  paidAt: Date | null;
  transactionCode: string | null;
  partnerTransactionCode: string | null;
  raw: Record<string, unknown>;
};

export type SalesReportErpOrder = {
  orderCode: string;
  erpOrderId: string | null;
  erpExternalOrderRef: string | null;
  erpOrderCreatedAt: Date | null;
  erpPaymentStatus: string | null;
  erpConfirmationStatus: string | null;
  erpFulfillmentStatus: string | null;
  erpLifecycleStatus: SalesReportErpLifecycleStatus;
  erpHasReturnedFullItems: boolean;
  erpReturnedAfterTaxAmount: number;
  erpStatusCheckedAt: Date;
  erpTerminalName: string | null;
  erpGrandTotal: number | null;
  erpCustomerType: string | null;
  erpPlatformId: number | null;
  erpConsultantCustomId: string | null;
  erpConsultantName: string | null;
  customerName: string | null;
  customerType: string;
  customerIsStudent: boolean;
  customerNeed: string | null;
  promotionCodes: string[];
  installmentNeed: boolean;
  installmentLoanAmount: number | null;
  items: SalesReportErpOrderItem[];
  payments: SalesReportErpPayment[];
  paymentMethods: string[];
  sanitizedSnapshot: Record<string, unknown>;
  fetchedAt: Date;
};

export type SalesReportErpOrderListItem = {
  orderCode: string;
  erpOrderId: string | null;
  erpExternalOrderRef: string | null;
  orderCreatedAt: Date | null;
  paymentStatus: string | null;
  confirmationStatus: string | null;
  fulfillmentStatus: string | null;
  lifecycleStatus: SalesReportErpLifecycleStatus;
  hasReturnedFullItems: boolean;
  returnedAfterTaxAmount: number;
  statusCheckedAt: Date;
  terminalName: string | null;
  grandTotal: number | null;
  customerName: string | null;
  customerPhone: string | null;
  customerType: string | null;
  paymentMethods: string[];
  platformId: number | null;
  consultantCustomId: string | null;
  consultantName: string | null;
  consultantEmail: string | null;
  sellerId: string | null;
  sellerName: string | null;
  sellerEmail: string | null;
  storeCode: string | null;
  storeName: string | null;
  sanitizedSnapshot: Record<string, unknown>;
  fetchedAt: Date;
};

export type SalesReportErpLifecycleStatus =
  | 'PENDING'
  | 'COMPLETED'
  | 'COMPLETED_PARTIAL_RETURN'
  | 'CANCELLED'
  | 'RETURNED_FULL';

type SalesReportErpReturnSummary = {
  verified: boolean;
  hasReturnedFullItems: boolean;
  returnedAfterTaxAmount: number;
  completedRequestCount: number;
};

type SalesReportErpResolvedLifecycle = SalesReportErpReturnSummary & {
  lifecycleStatus: SalesReportErpLifecycleStatus;
  statusCheckedAt: Date;
};

export function isSalesReportErpOrderCanceledStatuses(input: {
  confirmationStatus?: string | null;
  fulfillmentStatus?: string | null;
}) {
  return [input.confirmationStatus, input.fulfillmentStatus].some(
    (status) => status?.trim().toLowerCase() === 'cancelled',
  );
}

export class SalesReportErpCanceledOrderException extends BadRequestException {
  constructor(public readonly cacheItem: SalesReportErpOrderListItem) {
    super('Đơn đã bị hủy.');
  }
}

export class SalesReportErpReturnedOrderException extends BadRequestException {
  constructor(public readonly cacheItem: SalesReportErpOrderListItem) {
    super('Đơn đã hoàn trả toàn bộ, không thể báo cáo mua hàng.');
  }
}

type CachedToken = {
  accessToken: string;
  expiresAt: number;
};

const DEFAULT_ERP_SCOPE =
  'openid profile read:permissions sellers om catalog ppm page_builder wms as fms seller-gateway ps-v2 us tenant:management notification-management-apis apl staff-bff user-segment-bff rebate-staff-bff merchant-bff ons-bff uns-bff-api ticket-bff dca payment-staff-bff lo marketing-automation-bff-api rebate-admin shopping-cart:order shopping-cart:write teko:marketing-automation-bff-api terra-staff-bff terra-staff-bff:loyalty user-segment-v2 loyalty-staff-bff loyalty-management-bff';

@Injectable()
export class SalesReportErpService {
  private readonly logger = new Logger(SalesReportErpService.name);
  private cachedToken: CachedToken | null = null;

  async lookupOrder(orderCodeInput: string, storeCode?: string | null) {
    const orderCode = this.normalizeOrderCode(orderCodeInput);
    if (!orderCode) {
      throw new BadRequestException('Vui lòng nhập mã đơn hàng.');
    }
    const startedAt = Date.now();
    this.logger.log(
      `Sales report ERP lookup started: orderLength=${orderCode.length} store=${storeCode || 'none'}`,
    );
    try {
      const accessToken = await this.getAccessToken();
      const order = await this.fetchOrder(orderCode, accessToken);
      const status = await this.resolveOrderLifecycle(
        order,
        orderCode,
        accessToken,
      );
      this.assertOrderCanBeReported(
        order,
        orderCode,
        storeCode ?? null,
        status,
      );
      const items = await this.normalizeItems(
        order,
        accessToken,
        storeCode ?? null,
      );
      const payments = this.normalizePayments(order?.payments);
      const result = this.normalizeOrder(
        orderCode,
        order,
        items,
        payments,
        status,
      );
      const customerTaxCode = this.billingTaxCode(order);
      this.logger.log(
        `Sales report ERP lookup succeeded: orderLength=${orderCode.length} itemCount=${items.length} listingCategoryItemCount=${result.items.filter((item) => item.listingCategories.length > 0).length} paymentCount=${payments.length} customerType=${result.customerType} billingCustomerType=${result.erpCustomerType || 'none'} hasBillingTaxCode=${Boolean(customerTaxCode)} promotionCodes=${result.promotionCodes.join(',')} customerIsStudent=${result.customerIsStudent} installmentNeed=${result.installmentNeed} installmentLoanAmount=${result.installmentLoanAmount ?? 0} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      if (
        error instanceof BadRequestException ||
        error instanceof ServiceUnavailableException
      ) {
        throw error;
      }
      this.logger.error(
        `Sales report ERP lookup failed: orderLength=${orderCode.length} durationMs=${Date.now() - startedAt} errorType=${this.errorType(error)}`,
      );
      throw new ServiceUnavailableException(
        'Chưa kiểm tra được mã đơn hàng. Vui lòng thử lại sau ít phút.',
      );
    }
  }

  async listRecentOrders(input: {
    date: string;
    storeCode?: string | null;
    limit?: number;
  }) {
    const startedAt = Date.now();
    const date = this.normalizeDateOnly(input.date);
    const limit = Math.max(1, Math.min(50, Number(input.limit ?? 50)));
    this.logger.log(
      `Sales report ERP order list sync started: date=${date} limit=${limit} store=${input.storeCode || 'none'}`,
    );
    try {
      const accessToken = await this.getAccessToken();
      const rows: any[] = await this.fetchOrderList(date, accessToken, limit);
      const fetchedAt = new Date();
      const orders = rows
        .map((row: any) =>
          this.normalizeOrderListItem(row, input.storeCode ?? null, fetchedAt),
        )
        .filter(
          (
            row: SalesReportErpOrderListItem | null,
          ): row is SalesReportErpOrderListItem => Boolean(row?.orderCode),
        );
      const businessCount = orders.filter(
        (order) => order.customerType === 'BUSINESS',
      ).length;
      const personalCount = orders.filter(
        (order) => order.customerType === 'PERSONAL',
      ).length;
      this.logger.log(
        `Sales report ERP order list sync succeeded: date=${date} count=${orders.length} businessCount=${businessCount} personalCount=${personalCount} durationMs=${Date.now() - startedAt}`,
      );
      return orders;
    } catch (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      this.logger.error(
        `Sales report ERP order list sync failed: date=${date} durationMs=${Date.now() - startedAt} errorType=${this.errorType(error)}`,
      );
      throw new ServiceUnavailableException(
        'Chưa đồng bộ được danh sách đơn hàng. Vui lòng thử lại sau ít phút.',
      );
    }
  }

  private async fetchOrderList(
    date: string,
    accessToken: string,
    limit: number,
  ) {
    const baseUrl = this.env(
      'ERP_STAFF_BFF_BASE_URL',
      'https://staff-bff.tekoapis.com',
    ).replace(/\/$/, '');
    const url = new URL(`${baseUrl}/api/v2/staff-admin/orders`);
    url.searchParams.set('createdAtGte', `${date}T00:00:00+07:00`);
    url.searchParams.set('createdAtLte', `${date}T23:59:59+07:00`);
    const sellerId =
      process.env.ERP_ORDER_LIST_SELLER_ID === undefined
        ? '1'
        : process.env.ERP_ORDER_LIST_SELLER_ID.trim();
    if (sellerId && sellerId.toUpperCase() !== 'ALL') {
      url.searchParams.set('sellerId', sellerId);
    }
    const platformId = this.env('ERP_ORDER_LIST_PLATFORM_ID', '3');
    if (platformId && platformId.toUpperCase() !== 'ALL') {
      url.searchParams.set('platformId', platformId);
    }
    url.searchParams.set('limit', String(limit));
    url.searchParams.set('sort', this.env('ERP_ORDER_LIST_SORT', '-createdAt'));
    const response = await this.fetchWithTimeout(url.toString(), {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
      },
    });
    if (!response.ok) {
      this.logger.warn(
        `Sales report ERP order list endpoint failed: status=${response.status}`,
      );
      throw new ServiceUnavailableException(
        'Chưa đồng bộ được danh sách đơn hàng. Vui lòng thử lại sau ít phút.',
      );
    }
    const body = (await response.json()) as any;
    return this.extractOrderListRows(body);
  }

  private extractOrderListRows(body: any) {
    const candidates = [
      body?.data?.orders,
      body?.data?.items,
      body?.data?.data,
      body?.orders,
      body?.items,
      body?.result?.orders,
      body?.result?.items,
    ];
    for (const candidate of candidates) {
      if (Array.isArray(candidate)) return candidate;
    }
    if (Array.isArray(body?.data)) return body.data;
    if (Array.isArray(body)) return body;
    return [];
  }

  private normalizeOrderListItem(
    row: any,
    fallbackStoreCode: string | null,
    fetchedAt: Date,
    resolvedStatus?: SalesReportErpResolvedLifecycle,
  ): SalesReportErpOrderListItem | null {
    const order = row?.order && typeof row.order === 'object' ? row.order : row;
    const consultant = this.firstObject(
      order?.consultant,
      order?.seller,
      order?.staff,
      order?.sale,
      order?.employee,
    );
    const seller = this.firstObject(
      order?.seller,
      order?.sellerInfo,
      order?.staff,
      order?.sale,
      order?.employee,
    );
    const creator = this.firstObject(
      order?.creator,
      order?.createdBy,
      order?.createdByUser,
      order?.owner,
    );
    const createdFromSiteDisplayName = this.firstText(
      order?.createdFromSiteDisplayName,
    );
    const siteDisplayName = this.firstText(
      order?.siteDisplayName,
      order?.site?.displayName,
      order?.createdFromSite?.displayName,
    );
    const terminalName = this.firstText(
      order?.terminalName,
      createdFromSiteDisplayName,
      siteDisplayName,
      order?.terminal?.name,
      order?.storeName,
      order?.store?.storeName,
      order?.store?.name,
    );
    const createdFromSiteStoreCode = this.extractStoreCodeFromDisplayName(
      createdFromSiteDisplayName,
    );
    const siteStoreCode = this.extractStoreCodeFromDisplayName(siteDisplayName);
    const terminalStoreCode =
      this.extractStoreCodeFromDisplayName(terminalName);
    const storeCode = this.normalizeStoreCode(
      this.firstText(
        createdFromSiteStoreCode,
        siteStoreCode,
        order?.storeCode,
        order?.terminalCode,
        order?.terminal?.code,
        order?.store?.storeId,
        order?.store?.code,
        terminalStoreCode,
        fallbackStoreCode,
      ),
    );
    const orderCode = this.normalizeOrderCode(
      this.firstText(
        order?.orderCode,
        order?.orderId,
        order?.code,
        order?.displayOrderCode,
        order?.externalOrderRef,
      ),
    );
    if (!orderCode) return null;
    const paymentMethods = this.cleanPaymentMethods(
      order?.paymentMethods ?? order?.payments ?? order?.paymentMethod,
    );
    const consultantCustomId = this.firstText(
      consultant?.customId,
      consultant?.code,
      consultant?.staffCode,
      consultant?.employeeCode,
      order?.consultantCustomId,
      order?.sellerCustomId,
    );
    const creatorId = this.firstText(
      creator?.id,
      creator?.userId,
      creator?.staffId,
      order?.creatorId,
      order?.createdById,
    );
    const creatorName = this.firstText(
      creator?.name,
      creator?.fullName,
      creator?.displayName,
      order?.creatorName,
      order?.createdByName,
    );
    const creatorEmail = this.firstText(
      creator?.email,
      creator?.username,
      order?.creatorEmail,
      order?.createdByEmail,
    );
    const consultantName = this.firstText(
      consultant?.name,
      consultant?.fullName,
      consultant?.displayName,
      order?.consultantName,
      order?.sellerName,
      creatorName,
    );
    const consultantEmail = this.firstText(
      consultant?.email,
      consultant?.username,
      order?.consultantEmail,
      order?.sellerEmail,
      order?.staffEmail,
      order?.saleEmail,
      creatorEmail,
    );
    const sellerId = this.firstText(
      seller?.id,
      seller?.sellerId,
      seller?.code,
      order?.sellerId,
      order?.seller?.id,
      creatorId,
    );
    const sellerName = this.firstText(
      seller?.name,
      seller?.fullName,
      seller?.displayName,
      order?.sellerName,
      creatorName,
    );
    const sellerEmail = this.firstText(
      seller?.email,
      seller?.username,
      order?.sellerEmail,
      order?.staffEmail,
      order?.saleEmail,
      creatorEmail,
    );
    const customerName = this.firstText(
      order?.customerName,
      order?.customer?.name,
      order?.customer?.fullName,
      order?.customerInfo?.name,
      order?.buyerName,
      order?.receiverName,
      order?.shippingAddress?.fullName,
    );
    const customerPhone = this.firstText(
      order?.customerPhone,
      order?.customer?.phone,
      order?.customer?.phoneNumber,
      order?.customerInfo?.phone,
      order?.buyerPhone,
      order?.receiverPhone,
      order?.shippingAddress?.phone,
    );
    const orderCreatedAtText = this.orderCreatedAtText(order, row);
    const orderCreatedAt = this.parseDate(orderCreatedAtText);
    const billingCustomerType = this.billingCustomerType(order);
    const billingTaxCode = this.billingTaxCode(order);
    const customerType = this.detectCustomerType(
      billingCustomerType,
      billingTaxCode,
    );
    const lifecycle =
      resolvedStatus ?? this.lifecycleFromListOrder(order, fetchedAt);
    return {
      orderCode,
      erpOrderId: this.firstText(order?.orderId, order?.id),
      erpExternalOrderRef: this.optionalText(order?.externalOrderRef),
      orderCreatedAt,
      paymentStatus: this.optionalText(order?.paymentStatus),
      confirmationStatus: this.optionalText(order?.confirmationStatus),
      fulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
      lifecycleStatus: lifecycle.lifecycleStatus,
      hasReturnedFullItems: lifecycle.hasReturnedFullItems,
      returnedAfterTaxAmount: lifecycle.returnedAfterTaxAmount,
      statusCheckedAt: lifecycle.statusCheckedAt,
      terminalName,
      grandTotal: this.toInt(order?.grandTotal ?? order?.totalAmount),
      customerName,
      customerPhone,
      customerType,
      paymentMethods,
      platformId: this.toInt(order?.platformId),
      consultantCustomId,
      consultantName,
      consultantEmail,
      sellerId,
      sellerName,
      sellerEmail,
      storeCode,
      storeName: this.firstText(order?.storeName, order?.store?.storeName),
      sanitizedSnapshot: {
        orderId: this.firstText(order?.orderId, order?.id),
        orderCode,
        createdAt: orderCreatedAtText,
        paymentStatus: this.optionalText(order?.paymentStatus),
        confirmationStatus: this.optionalText(order?.confirmationStatus),
        fulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
        lifecycleStatus: lifecycle.lifecycleStatus,
        hasReturnedFullItems: lifecycle.hasReturnedFullItems,
        returnedAfterTaxAmount: lifecycle.returnedAfterTaxAmount,
        terminalName,
        createdFromSiteDisplayName,
        siteDisplayName,
        grandTotal: this.toInt(order?.grandTotal ?? order?.totalAmount),
        customerName,
        customerType,
        billingInfo: {
          customerType: billingCustomerType,
          hasTaxCode: Boolean(billingTaxCode),
        },
        paymentMethods,
        platformId: this.toInt(order?.platformId),
        consultant: {
          customId: consultantCustomId,
          name: consultantName,
          email: consultantEmail,
        },
        seller: {
          id: sellerId,
          name: sellerName,
          email: sellerEmail,
        },
        creator: {
          id: creatorId,
          name: creatorName,
          email: creatorEmail,
        },
      },
      fetchedAt,
    };
  }

  private async fetchOrder(orderCode: string, accessToken: string) {
    const baseUrl = this.env(
      'ERP_STAFF_BFF_BASE_URL',
      'https://staff-bff.tekoapis.com',
    ).replace(/\/$/, '');
    const url = `${baseUrl}/api/v2/staff-admin/orders/${encodeURIComponent(
      orderCode,
    )}?thousandSeparator=%2C&decimalSeparator=.`;
    const response = await this.fetchWithTimeout(url, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
      },
    });
    if (response.status === 404) {
      throw new BadRequestException('Không tìm thấy mã đơn hàng trên ERP.');
    }
    if (!response.ok) {
      this.logger.warn(
        `Sales report ERP order endpoint failed: status=${response.status}`,
      );
      throw new ServiceUnavailableException(
        'Chưa kiểm tra được mã đơn hàng. Vui lòng thử lại sau ít phút.',
      );
    }
    const body = (await response.json()) as any;
    const order = body?.data?.order;
    if (!order?.orderId) {
      throw new BadRequestException('Không tìm thấy mã đơn hàng trên ERP.');
    }
    return order;
  }

  private assertOrderCanBeReported(
    order: any,
    orderCode: string,
    storeCode: string | null,
    status: SalesReportErpResolvedLifecycle,
  ) {
    if (status.lifecycleStatus === 'CANCELLED') {
      this.logger.warn(
        `Sales report ERP canceled order blocked: orderLength=${orderCode.length}`,
      );
      throw new SalesReportErpCanceledOrderException(
        this.excludedOrderCacheItem(order, orderCode, storeCode, status),
      );
    }
    if (status.lifecycleStatus === 'RETURNED_FULL') {
      this.logger.warn(
        `Sales report ERP returned order blocked: orderLength=${orderCode.length}`,
      );
      throw new SalesReportErpReturnedOrderException(
        this.excludedOrderCacheItem(order, orderCode, storeCode, status),
      );
    }
  }

  async lookupOrderStatus(
    orderCodeInput: string,
    fallbackStoreCode?: string | null,
  ): Promise<SalesReportErpOrderListItem> {
    const orderCode = this.normalizeOrderCode(orderCodeInput);
    if (!orderCode) throw new BadRequestException('Mã đơn hàng không hợp lệ.');
    const accessToken = await this.getAccessToken();
    const order = await this.fetchOrder(orderCode, accessToken);
    const status = await this.resolveOrderLifecycle(
      order,
      orderCode,
      accessToken,
    );
    const normalized = this.normalizeOrderListItem(
      order,
      fallbackStoreCode ?? null,
      status.statusCheckedAt,
      status,
    );
    if (!normalized) {
      throw new ServiceUnavailableException(
        'ERP chưa trả đủ dữ liệu trạng thái đơn hàng.',
      );
    }
    return normalized;
  }

  private excludedOrderCacheItem(
    order: any,
    orderCode: string,
    fallbackStoreCode: string | null,
    status: SalesReportErpResolvedLifecycle,
  ): SalesReportErpOrderListItem {
    const normalized = this.normalizeOrderListItem(
      order,
      fallbackStoreCode,
      status.statusCheckedAt,
      status,
    );
    if (!normalized) {
      throw new ServiceUnavailableException(
        'ERP chưa trả đủ dữ liệu trạng thái đơn hàng.',
      );
    }
    return {
      ...normalized,
      orderCode,
      sanitizedSnapshot: {
        ...normalized.sanitizedSnapshot,
        exclusionCandidate: true,
      },
    };
  }

  private async resolveOrderLifecycle(
    order: any,
    orderCode: string,
    accessToken: string,
  ): Promise<SalesReportErpResolvedLifecycle> {
    const statusCheckedAt = new Date();
    if (
      isSalesReportErpOrderCanceledStatuses({
        confirmationStatus: this.optionalText(order?.confirmationStatus),
        fulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
      })
    ) {
      return {
        verified: true,
        lifecycleStatus: 'CANCELLED',
        hasReturnedFullItems: false,
        returnedAfterTaxAmount: 0,
        completedRequestCount: 0,
        statusCheckedAt,
      };
    }
    const returns = await this.fetchReturnSummary(
      orderCode,
      this.toInt(order?.platformId),
      this.toInt(order?.grandTotal),
      order?.hasReturnedFullItems === true,
      accessToken,
    );
    const grandTotal = Math.max(0, this.toInt(order?.grandTotal) ?? 0);
    const returnedAmount = Math.min(
      grandTotal,
      Math.max(0, returns.returnedAfterTaxAmount),
    );
    const fullReturn =
      returns.hasReturnedFullItems ||
      (grandTotal > 0 && returnedAmount >= grandTotal);
    if (fullReturn) {
      return {
        ...returns,
        lifecycleStatus: 'RETURNED_FULL',
        hasReturnedFullItems: true,
        returnedAfterTaxAmount: grandTotal || returnedAmount,
        statusCheckedAt,
      };
    }
    const delivered =
      this.optionalText(order?.fulfillmentStatus)?.toUpperCase() ===
      'DELIVERED';
    return {
      ...returns,
      lifecycleStatus:
        delivered && returns.verified
          ? returnedAmount > 0
            ? 'COMPLETED_PARTIAL_RETURN'
            : 'COMPLETED'
          : 'PENDING',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: returnedAmount,
      statusCheckedAt,
    };
  }

  private lifecycleFromListOrder(
    order: any,
    statusCheckedAt: Date,
  ): SalesReportErpResolvedLifecycle {
    const cancelled = isSalesReportErpOrderCanceledStatuses({
      confirmationStatus: this.optionalText(order?.confirmationStatus),
      fulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
    });
    return {
      verified: cancelled,
      lifecycleStatus: cancelled ? 'CANCELLED' : 'PENDING',
      hasReturnedFullItems: false,
      returnedAfterTaxAmount: 0,
      completedRequestCount: 0,
      statusCheckedAt,
    };
  }

  private async fetchReturnSummary(
    orderCode: string,
    platformId: number | null,
    grandTotal: number | null,
    hasReturnedFullItems: boolean,
    accessToken: string,
  ): Promise<SalesReportErpReturnSummary> {
    const baseUrl = this.env(
      'ERP_STAFF_BFF_BASE_URL',
      'https://staff-bff.tekoapis.com',
    ).replace(/\/$/, '');
    const url = new URL(`${baseUrl}/api/v2/return-requests`);
    url.searchParams.set('orderIds', orderCode);
    url.searchParams.set(
      'platformId',
      String(platformId ?? Number(this.env('ERP_ORDER_LIST_PLATFORM_ID', '3'))),
    );
    try {
      const response = await this.fetchWithTimeout(url.toString(), {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: 'application/json',
        },
      });
      if (!response.ok) {
        this.logger.warn(
          `Sales report ERP return lookup failed: status=${response.status} orderLength=${orderCode.length}`,
        );
        return {
          verified: hasReturnedFullItems,
          hasReturnedFullItems,
          returnedAfterTaxAmount: hasReturnedFullItems
            ? Math.max(0, grandTotal ?? 0)
            : 0,
          completedRequestCount: 0,
        };
      }
      const body = (await response.json().catch(() => ({}))) as any;
      const requests = Array.isArray(body?.request)
        ? body.request
        : Array.isArray(body?.data?.request)
          ? body.data.request
          : [];
      const seenRequestIds = new Set<string>();
      const completed = requests.filter((request: any) => {
        if (
          this.optionalText(request?.status)?.toUpperCase() !==
          'RETURN_STATUS_RETURNED'
        ) {
          return false;
        }
        const requestId = this.firstText(
          request?.id,
          request?.requestId,
          request?.returnRequestId,
          request?.code,
        );
        if (!requestId) return true;
        if (seenRequestIds.has(requestId)) return false;
        seenRequestIds.add(requestId);
        return true;
      });
      let returnedAfterTaxAmount = 0;
      for (const request of completed) {
        const items = Array.isArray(request?.items) ? request.items : [];
        for (const item of items) {
          const quantity = Math.max(0, this.toInt(item?.returnedQuantity) ?? 0);
          const unitAfterTaxPrice = Math.max(
            0,
            this.toInt(item?.unitAfterTaxPrice) ??
              this.toInt(item?.unitPrice) ??
              0,
          );
          returnedAfterTaxAmount += quantity * unitAfterTaxPrice;
        }
      }
      const cappedAmount = Math.min(
        Math.max(0, grandTotal ?? returnedAfterTaxAmount),
        Math.max(0, returnedAfterTaxAmount),
      );
      return {
        verified: true,
        hasReturnedFullItems:
          hasReturnedFullItems ||
          ((grandTotal ?? 0) > 0 && cappedAmount >= (grandTotal ?? 0)),
        returnedAfterTaxAmount: cappedAmount,
        completedRequestCount: completed.length,
      };
    } catch (error) {
      this.logger.warn(
        `Sales report ERP return lookup failed unexpectedly: orderLength=${orderCode.length} errorType=${this.errorType(error)}`,
      );
      return {
        verified: hasReturnedFullItems,
        hasReturnedFullItems,
        returnedAfterTaxAmount: hasReturnedFullItems
          ? Math.max(0, grandTotal ?? 0)
          : 0,
        completedRequestCount: 0,
      };
    }
  }

  private async normalizeItems(
    order: any,
    accessToken: string,
    storeCode: string | null,
  ): Promise<SalesReportErpOrderItem[]> {
    const rawItems: any[] = Array.isArray(order?.orderCaptureLineItems)
      ? order.orderCaptureLineItems
      : [];
    const productBySku = await this.fetchProducts(
      rawItems
        .map((item: any) => this.optionalText(item?.sellerSku))
        .filter((sku: string | null): sku is string => Boolean(sku)),
      accessToken,
      storeCode,
    );
    return rawItems.map((item: any) => {
      const sellerSku = this.optionalText(item?.sellerSku);
      const product = sellerSku ? productBySku.get(sellerSku) : null;
      const brand = product?.brand;
      const productType = product?.productType;
      const productGroup = product?.productGroup;
      return {
        sku: this.optionalText(product?.sku) ?? sellerSku,
        sellerSku,
        name: this.optionalText(item?.name) ?? this.optionalText(product?.name),
        brandCode: this.optionalText(brand?.code ?? brand?.id),
        brandName: this.optionalText(brand?.name ?? brand?.displayName),
        productTypeCode: this.optionalText(
          productType?.code ?? productType?.id,
        ),
        productTypeName: this.optionalText(
          productType?.name ?? productType?.displayName,
        ),
        productGroupId: this.optionalText(
          productGroup?.id ?? productGroup?.code,
        ),
        productGroupCode: this.optionalText(productGroup?.code),
        productGroupName: this.optionalText(
          productGroup?.name ?? productGroup?.displayName,
        ),
        categoryType: null,
        listingCategories: this.cleanListingCategories(product?.categories),
        quantity: this.toInt(item?.quantity),
        sellPrice: this.toInt(item?.sellPrice),
        finalSellPrice: this.toInt(item?.finalSellPrice),
        rowTotal: this.toInt(item?.rowTotal),
        raw: this.sanitizeItemRaw(item, product),
      };
    });
  }

  private async fetchProducts(
    sellerSkus: string[],
    accessToken: string,
    storeCode: string | null,
  ) {
    const uniqueSkus = Array.from(new Set(sellerSkus)).slice(0, 50);
    const result = new Map<string, any>();
    if (uniqueSkus.length === 0) return result;
    const baseUrl = this.env(
      'ERP_LISTING_BASE_URL',
      'https://listing.tekoapis.com',
    ).replace(/\/$/, '');
    const url = new URL(`${baseUrl}/api/products/`);
    url.searchParams.set(
      'channel',
      this.env('ERP_LISTING_CHANNEL', 'pv_showroom'),
    );
    url.searchParams.set(
      'terminal',
      storeCode || this.env('ERP_LISTING_TERMINAL', '{storeCode}'),
    );
    url.searchParams.set('skus', uniqueSkus.join(','));
    try {
      const response = await this.fetchWithTimeout(url.toString(), {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: 'application/json',
        },
      });
      if (!response.ok) {
        this.logger.warn(
          `Sales report ERP product lookup skipped: status=${response.status}`,
        );
        return result;
      }
      const body = (await response.json()) as any;
      const products = Array.isArray(body?.result?.products)
        ? body.result.products
        : [];
      for (const product of products) {
        const sku = this.optionalText(product?.sku);
        if (sku) result.set(sku, product);
      }
    } catch (error) {
      this.logger.warn(
        `Sales report ERP product lookup failed but order lookup continues: errorType=${this.errorType(error)}`,
      );
    }
    return result;
  }

  private normalizePayments(value: unknown): SalesReportErpPayment[] {
    const payments = Array.isArray(value) ? value : [];
    return payments.map((payment) => ({
      paymentMethod: this.firstText(
        (payment as any)?.paymentMethod,
        (payment as any)?.paymentMethodName,
        (payment as any)?.method,
        (payment as any)?.methodName,
        (payment as any)?.name,
      ),
      amount: this.toInt((payment as any)?.amount),
      paidAt: this.parseDate(
        (payment as any)?.paidAt ?? (payment as any)?.createdAt,
      ),
      transactionCode: this.firstText(
        (payment as any)?.transactionCode,
        (payment as any)?.code,
      ),
      partnerTransactionCode: this.optionalText(
        (payment as any)?.partnerTransactionCode,
      ),
      raw: {
        paymentMethod: this.firstText(
          (payment as any)?.paymentMethod,
          (payment as any)?.paymentMethodName,
          (payment as any)?.method,
          (payment as any)?.methodName,
          (payment as any)?.name,
        ),
        amount: this.toInt((payment as any)?.amount),
        paidAt: this.optionalText((payment as any)?.paidAt),
      },
    }));
  }

  private normalizeOrder(
    orderCode: string,
    order: any,
    items: SalesReportErpOrderItem[],
    payments: SalesReportErpPayment[],
    status: SalesReportErpResolvedLifecycle,
  ): SalesReportErpOrder {
    const fetchedAt = new Date();
    const customerNeed = items
      .map((item) => item.name)
      .filter((name): name is string => Boolean(name))
      .slice(0, 5)
      .join('; ');
    const erpCustomerType = this.billingCustomerType(order);
    const billingTaxCode = this.billingTaxCode(order);
    const detectedCustomerType = this.detectCustomerType(
      erpCustomerType,
      billingTaxCode,
    );
    const priceSummaryTags = this.priceSummaryTags(order?.priceSummary);
    const hasExamScorePromotion = payments.some((payment) =>
      this.hasCodePrefix(payment.partnerTransactionCode, 'PVDD'),
    );
    const hasStudentPromotion = priceSummaryTags.some((tag) =>
      this.hasCodePrefix(tag, 'PVHSSV'),
    );
    const customerIsStudent = hasExamScorePromotion || hasStudentPromotion;
    const customerType = customerIsStudent ? 'PERSONAL' : detectedCustomerType;
    const promotionCodes: string[] = [];
    if (hasExamScorePromotion) promotionCodes.push('EXAM_SCORE_EXCHANGE');
    if (hasStudentPromotion) promotionCodes.push('STUDENT');
    if (promotionCodes.length === 0) promotionCodes.push('OTHER');
    const installmentPayments = payments.filter((payment) =>
      this.isInstallmentPaymentMethod(payment.paymentMethod),
    );
    const installmentLoanAmount = installmentPayments.reduce(
      (total, payment) => total + Math.max(payment.amount ?? 0, 0),
      0,
    );
    const customerName = this.firstText(
      order?.customerName,
      order?.customer?.name,
      order?.customer?.fullName,
      order?.customer?.displayName,
      order?.customerInfo?.name,
      order?.customerInfo?.fullName,
      order?.buyerName,
      order?.receiverName,
      order?.recipientName,
      order?.shippingAddress?.fullName,
      order?.shippingAddress?.name,
      order?.billingAddress?.fullName,
      order?.billingAddress?.name,
    );
    const paymentMethods = Array.from(
      new Set(
        payments
          .map((payment) => payment.paymentMethod)
          .filter((value): value is string => Boolean(value)),
      ),
    );
    const orderCreatedAtText = this.orderCreatedAtText(order);
    return {
      orderCode,
      erpOrderId: this.optionalText(order?.orderId),
      erpExternalOrderRef: this.optionalText(order?.externalOrderRef),
      erpOrderCreatedAt: this.parseDate(orderCreatedAtText),
      erpPaymentStatus: this.optionalText(order?.paymentStatus),
      erpConfirmationStatus: this.optionalText(order?.confirmationStatus),
      erpFulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
      erpLifecycleStatus: status.lifecycleStatus,
      erpHasReturnedFullItems: status.hasReturnedFullItems,
      erpReturnedAfterTaxAmount: status.returnedAfterTaxAmount,
      erpStatusCheckedAt: status.statusCheckedAt,
      erpTerminalName: this.optionalText(order?.terminalName),
      erpGrandTotal: this.toInt(order?.grandTotal),
      erpCustomerType,
      erpPlatformId: this.toInt(order?.platformId),
      erpConsultantCustomId: this.optionalText(order?.consultant?.customId),
      erpConsultantName: this.optionalText(order?.consultant?.name),
      customerName,
      customerType,
      customerIsStudent,
      customerNeed: customerNeed || null,
      promotionCodes,
      installmentNeed: installmentPayments.length > 0,
      installmentLoanAmount:
        installmentLoanAmount > 0 ? installmentLoanAmount : null,
      items,
      payments,
      paymentMethods,
      sanitizedSnapshot: {
        orderId: this.optionalText(order?.orderId),
        createdAt: orderCreatedAtText,
        customerType: erpCustomerType,
        billingInfo: {
          customerType: erpCustomerType,
          hasTaxCode: Boolean(billingTaxCode),
        },
        promotionCodes,
        customerIsStudent,
        installmentNeed: installmentPayments.length > 0,
        installmentLoanAmount:
          installmentLoanAmount > 0 ? installmentLoanAmount : null,
        paymentStatus: this.optionalText(order?.paymentStatus),
        confirmationStatus: this.optionalText(order?.confirmationStatus),
        fulfillmentStatus: this.optionalText(order?.fulfillmentStatus),
        lifecycleStatus: status.lifecycleStatus,
        hasReturnedFullItems: status.hasReturnedFullItems,
        returnedAfterTaxAmount: status.returnedAfterTaxAmount,
        terminalName: this.optionalText(order?.terminalName),
        createdFromSiteDisplayName: this.optionalText(
          order?.createdFromSiteDisplayName,
        ),
        siteDisplayName: this.firstText(
          order?.siteDisplayName,
          order?.site?.displayName,
          order?.createdFromSite?.displayName,
        ),
        externalOrderRef: this.optionalText(order?.externalOrderRef),
        customerName,
        grandTotal: this.toInt(order?.grandTotal),
        paymentMethods,
        platformId: this.toInt(order?.platformId),
        consultant: {
          customId: this.optionalText(order?.consultant?.customId),
          name: this.optionalText(order?.consultant?.name),
        },
        itemCount: items.length,
        paymentCount: payments.length,
        items: items.map((item) => ({
          sku: item.sku,
          sellerSku: item.sellerSku,
          name: item.name,
          quantity: item.quantity,
          finalSellPrice: item.finalSellPrice,
          rowTotal: item.rowTotal,
          productGroupId: item.productGroupId,
          productGroupCode: item.productGroupCode,
          productGroupName: item.productGroupName,
          categoryType: item.categoryType,
        })),
        payments: payments.map((payment) => ({
          paymentMethod: payment.paymentMethod,
          amount: payment.amount,
          paidAt: payment.paidAt?.toISOString() ?? null,
          partnerTransactionCode: payment.partnerTransactionCode,
        })),
      },
      fetchedAt,
    };
  }

  private async getAccessToken() {
    const staticToken = process.env.ERP_ACCESS_TOKEN?.trim();
    if (staticToken) return staticToken;
    const now = Date.now();
    if (this.cachedToken && this.cachedToken.expiresAt > now) {
      return this.cachedToken.accessToken;
    }
    const username = process.env.ERP_USERNAME?.trim();
    const password = process.env.ERP_PASSWORD?.trim();
    if (!username || !password) {
      throw new ServiceUnavailableException(
        'Chưa cấu hình tài khoản ERP để kiểm tra đơn hàng.',
      );
    }
    const token = await this.loginWithPassword(username, password);
    this.cachedToken = token;
    return token.accessToken;
  }

  private async loginWithPassword(
    username: string,
    password: string,
  ): Promise<CachedToken> {
    const clientId = this.env(
      'ERP_CLIENT_ID',
      '04409baea81b46e1a53e64efe0de16a5',
    );
    const redirectUri = this.env('ERP_REDIRECT_URI', 'https://erp.phongvu.vn');
    const oauthBase = this.env(
      'ERP_OAUTH_BASE_URL',
      'https://oauth-merchant.phongvu.vn',
    ).replace(/\/$/, '');
    const identityBase = this.env(
      'ERP_IDENTITY_BASE_URL',
      'https://identity.tekoapis.com',
    ).replace(/\/$/, '');
    const state = this.base64Url(randomBytes(12));
    const nonce = this.base64Url(randomBytes(12));
    const codeVerifier = this.base64Url(randomBytes(32));
    const codeChallenge = this.base64Url(
      createHash('sha256').update(codeVerifier).digest(),
    );
    const scope = this.env('ERP_SCOPE', DEFAULT_ERP_SCOPE);

    const challengeUrl = this.authorizeUrl(oauthBase, {
      clientId,
      redirectUri,
      state,
      nonce,
      scope,
      codeChallenge,
    });
    const challengeResponse = await this.fetchWithTimeout(challengeUrl, {
      redirect: 'manual',
    });
    const challengeLocation =
      challengeResponse.headers.get('location') ?? challengeResponse.url;
    const challenge = this.urlParam(challengeLocation, 'challenge');
    if (!challenge) {
      throw new ServiceUnavailableException(
        'Chưa lấy được phiên đăng nhập ERP.',
      );
    }

    const loginResponse = await this.fetchWithTimeout(
      `${identityBase}/api/v1/users/login`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({
          challenge,
          username,
          password,
          client_id: clientId,
        }),
      },
    );
    if (!loginResponse.ok) {
      this.logger.warn(
        `Sales report ERP login failed: status=${loginResponse.status}`,
      );
      throw new ServiceUnavailableException(
        'Tài khoản ERP chưa đăng nhập được. Vui lòng kiểm tra cấu hình.',
      );
    }
    const loginBody = (await loginResponse.json().catch(() => ({}))) as any;
    const loginVerifier =
      loginBody?.data?.login_verifier ??
      loginBody?.login_verifier ??
      loginBody?.data?.loginVerifier ??
      loginBody?.loginVerifier ??
      loginBody?.data?.verifier ??
      loginBody?.verifier;
    const redirectTo = this.rawText(
      loginBody?.data?.redirect_to ??
        loginBody?.redirect_to ??
        loginBody?.data?.redirectTo ??
        loginBody?.redirectTo,
    );
    let codeRequestUrl: string;
    if (redirectTo) {
      codeRequestUrl = this.requireOAuthRedirect(redirectTo, oauthBase);
      this.logger.log(
        'Sales report ERP login returned redirect authorization URL.',
      );
    } else if (loginVerifier) {
      codeRequestUrl = this.authorizeUrl(oauthBase, {
        clientId,
        redirectUri,
        state,
        nonce,
        scope,
        codeChallenge,
        loginVerifier: String(loginVerifier),
      });
      this.logger.log('Sales report ERP login returned login verifier.');
    } else {
      const topLevelKeys = this.objectKeys(loginBody).join(',') || 'none';
      const dataKeys = this.objectKeys(loginBody?.data).join(',') || 'none';
      this.logger.warn(
        `Sales report ERP login missing verifier: topLevelKeys=${topLevelKeys} dataKeys=${dataKeys}`,
      );
      throw new ServiceUnavailableException(
        'ERP chưa trả phiên xác thực hợp lệ.',
      );
    }

    const codeResponse = await this.fetchWithTimeout(codeRequestUrl, {
      redirect: 'manual',
    });
    const codeLocation =
      codeResponse.headers.get('location') ?? codeResponse.url;
    const code = this.urlParam(codeLocation, 'code');
    if (!code) {
      throw new ServiceUnavailableException('ERP chưa trả mã xác thực hợp lệ.');
    }

    const tokenResponse = await this.fetchWithTimeout(
      `${oauthBase}/oauth/token`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
        body: new URLSearchParams({
          code,
          grant_type: 'authorization_code',
          redirect_uri: redirectUri,
          client_id: clientId,
          code_verifier: codeVerifier,
        }),
      },
    );
    if (!tokenResponse.ok) {
      this.logger.warn(
        `Sales report ERP token exchange failed: status=${tokenResponse.status}`,
      );
      throw new ServiceUnavailableException(
        'ERP chưa cấp được token kiểm tra đơn hàng.',
      );
    }
    const tokenBody = (await tokenResponse.json()) as any;
    const accessToken = String(tokenBody?.access_token || '').trim();
    if (!accessToken) {
      throw new ServiceUnavailableException('ERP chưa trả token hợp lệ.');
    }
    const expiresIn = Number(tokenBody?.expires_in || 3600);
    const safetySeconds = Number(
      process.env.ERP_TOKEN_TTL_SAFETY_SECONDS || 60,
    );
    return {
      accessToken,
      expiresAt:
        Date.now() +
        Math.max(60, expiresIn - Math.max(0, safetySeconds)) * 1000,
    };
  }

  private authorizeUrl(
    oauthBase: string,
    input: {
      clientId: string;
      redirectUri: string;
      state: string;
      nonce: string;
      scope: string;
      codeChallenge: string;
      loginVerifier?: string;
    },
  ) {
    const url = new URL(`${oauthBase}/oauth/authorize`);
    url.searchParams.set('client_id', input.clientId);
    url.searchParams.set('redirect_uri', input.redirectUri);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('state', input.state);
    url.searchParams.set('scope', input.scope);
    url.searchParams.set('code_challenge', input.codeChallenge);
    url.searchParams.set('code_challenge_method', 'S256');
    url.searchParams.set('nonce', input.nonce);
    if (input.loginVerifier) {
      url.searchParams.set('login_verifier', input.loginVerifier);
    }
    return url.toString();
  }

  private async fetchWithTimeout(
    url: string,
    init: RequestInit = {},
  ): Promise<Response> {
    const timeoutMs = Number(process.env.ERP_ORDER_TIMEOUT_MS || 10_000);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetch(url, { ...init, signal: controller.signal });
    } finally {
      clearTimeout(timer);
    }
  }

  private sanitizeItemRaw(item: any, product: any) {
    return {
      sellerSku: this.optionalText(item?.sellerSku),
      name: this.optionalText(item?.name),
      sellerName: this.optionalText(item?.sellerName),
      quantity: this.toInt(item?.quantity),
      sellPrice: this.toInt(item?.sellPrice),
      finalSellPrice: this.toInt(item?.finalSellPrice),
      rowTotal: this.toInt(item?.rowTotal),
      productGroup: product?.productGroup
        ? {
            id: this.optionalText(product.productGroup?.id),
            code: this.optionalText(product.productGroup?.code),
            name: this.optionalText(product.productGroup?.name),
          }
        : null,
      productType: product?.productType
        ? {
            id: this.optionalText(product.productType?.id),
            code: this.optionalText(product.productType?.code),
            name: this.optionalText(product.productType?.name),
          }
        : null,
      categories: this.cleanListingCategories(product?.categories),
    };
  }

  private cleanListingCategories(value: unknown) {
    const categories = Array.isArray(value)
      ? value
      : value && typeof value === 'object'
        ? Object.values(value as Record<string, unknown>)
        : [];
    return categories
      .map((category) => this.cleanListingCategory(category))
      .filter((category) => Object.keys(category).length > 0)
      .slice(0, 10);
  }

  private cleanListingCategory(value: unknown) {
    if (typeof value === 'string') return { name: this.optionalText(value) };
    if (!value || typeof value !== 'object') return {};
    const record = value as Record<string, unknown>;
    const level = this.toInt(
      record.level ??
        record.lvl ??
        record.categoryLevel ??
        record.depth ??
        record.displayLevel,
    );
    return {
      id: this.optionalText(record.id ?? record.categoryId),
      code: this.optionalText(record.code ?? record.categoryCode),
      name: this.optionalText(record.name ?? record.categoryName),
      displayName: this.optionalText(record.displayName),
      level,
    };
  }

  private billingCustomerType(order: any) {
    return this.optionalText(order?.billingInfo?.customerType);
  }

  private billingTaxCode(order: any) {
    return this.optionalText(order?.billingInfo?.taxCode);
  }

  private detectCustomerType(
    billingCustomerType: string | null,
    billingTaxCode: string | null,
  ) {
    return billingCustomerType?.toUpperCase() === 'BUSINESS' || billingTaxCode
      ? 'BUSINESS'
      : 'PERSONAL';
  }

  private priceSummaryTags(value: unknown) {
    const rows = Array.isArray(value) ? value : [];
    return Array.from(
      new Set(
        rows.flatMap((row) => {
          const tags = Array.isArray((row as any)?.tags)
            ? (row as any).tags
            : [];
          return tags
            .map((tag: unknown) =>
              typeof tag === 'object' && tag !== null
                ? this.firstText(
                    (tag as any).code,
                    (tag as any).value,
                    (tag as any).name,
                    (tag as any).tag,
                    (tag as any).label,
                  )
                : this.optionalText(tag),
            )
            .filter((tag: string | null): tag is string => Boolean(tag));
        }),
      ),
    ).slice(0, 50);
  }

  private hasCodePrefix(value: unknown, prefix: string) {
    const text = this.optionalText(value)?.toUpperCase();
    return Boolean(text?.startsWith(prefix));
  }

  private isInstallmentPaymentMethod(value: unknown) {
    const text = this.optionalText(value)?.toUpperCase();
    return Boolean(text?.includes('INSTALLMENT'));
  }

  private parseDate(value: unknown) {
    const text = String(value || '').trim();
    if (!text) return null;
    const date = new Date(text);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private orderCreatedAtText(order: any, row?: any) {
    return this.firstText(
      order?.createdAt,
      order?.orderCreatedAt,
      order?.createdDate,
      order?.createdDateTime,
      order?.createdAtUtc,
      order?.createdAtUTC,
      order?.orderedAt,
      order?.orderDate,
      order?.placedAt,
      row?.createdAt,
      row?.orderCreatedAt,
      row?.createdDate,
      row?.createdDateTime,
      row?.orderedAt,
      row?.orderDate,
    );
  }

  private toInt(value: unknown) {
    const normalized =
      typeof value === 'string' ? value.replace(/,/g, '').trim() : value;
    const number = Number(normalized);
    if (!Number.isFinite(number)) return null;
    return Math.trunc(number);
  }

  private optionalText(value: unknown) {
    const text = String(value ?? '').trim();
    return text ? text.slice(0, 500) : null;
  }

  private firstText(...values: unknown[]) {
    for (const value of values) {
      const text = this.optionalText(value);
      if (text) return text;
    }
    return null;
  }

  private firstObject(...values: unknown[]) {
    return values.find(
      (value) => value && typeof value === 'object' && !Array.isArray(value),
    ) as Record<string, unknown> | undefined;
  }

  private cleanPaymentMethods(value: unknown) {
    const raw = Array.isArray(value) ? value : value ? [value] : [];
    return Array.from(
      new Set(
        raw
          .map((item) =>
            typeof item === 'object' && item !== null
              ? this.firstText(
                  (item as any).paymentMethod,
                  (item as any).paymentMethodName,
                  (item as any).method,
                  (item as any).methodName,
                  (item as any).name,
                )
              : this.optionalText(item),
          )
          .filter((item): item is string => Boolean(item)),
      ),
    ).slice(0, 20);
  }

  private rawText(value: unknown) {
    const text = String(value ?? '').trim();
    return text || null;
  }

  private normalizeOrderCode(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase()
      .replace(/\s+/g, '');
  }

  private normalizeStoreCode(value: unknown) {
    const text = String(value || '')
      .trim()
      .toUpperCase();
    if (!text) return null;
    const match = text.match(
      /(?:^|[^A-Z0-9])([A-Z]{2,3}\d{1,4})(?=$|[^A-Z0-9])/,
    );
    if (match) return match[1];
    const cleaned = text.replace(/[^A-Z0-9_]/g, '');
    return /^[A-Z]{2,3}\d{1,4}$/.test(cleaned) ? cleaned : null;
  }

  private extractStoreCodeFromDisplayName(value: unknown) {
    const text = String(value || '')
      .trim()
      .toUpperCase();
    if (!text) return null;
    const bracketMatch = text.match(/^\[([^\]]+)\]/);
    if (bracketMatch) return this.normalizeStoreCode(bracketMatch[1]);
    const leadingMatch = text.match(/^([A-Z]{2,3}\d{1,4})(?=$|[^A-Z0-9])/);
    return leadingMatch?.[1] ?? null;
  }

  private normalizeDateOnly(value: unknown) {
    const text = String(value || '').trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return text;
    const now = new Date();
    const vnNow = new Date(now.getTime() + 7 * 60 * 60 * 1000);
    const two = (part: number) => String(part).padStart(2, '0');
    return `${vnNow.getUTCFullYear()}-${two(vnNow.getUTCMonth() + 1)}-${two(vnNow.getUTCDate())}`;
  }

  private env(key: string, fallback: string) {
    return process.env[key]?.trim() || fallback;
  }

  private base64Url(buffer: Buffer) {
    return buffer
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }

  private requireOAuthRedirect(url: string, oauthBase: string) {
    try {
      const redirectUrl = new URL(url);
      const allowedBase = new URL(oauthBase);
      if (redirectUrl.origin === allowedBase.origin) {
        return redirectUrl.toString();
      }
    } catch {
      // Fall through to the safe operational error below.
    }
    this.logger.warn(
      'Sales report ERP login returned unexpected redirect URL.',
    );
    throw new ServiceUnavailableException(
      'ERP chưa trả phiên xác thực hợp lệ.',
    );
  }

  private objectKeys(value: unknown) {
    if (!value || typeof value !== 'object') return [];
    return Object.keys(value as Record<string, unknown>).slice(0, 20);
  }

  private errorType(error: unknown) {
    return error instanceof Error ? error.name : typeof error;
  }

  private urlParam(url: string, key: string) {
    try {
      return new URL(url).searchParams.get(key);
    } catch {
      return null;
    }
  }
}
