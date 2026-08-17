import { SalesReportErpOrderListItem } from './sales-report-erp.service';

export type SalesReportsErpCachePageInput = {
  date: string;
  limit: number;
  source: string;
  offset?: number;
};

export type SalesReportsErpCachePageResult = {
  count: number;
  newOrderCount: number;
  mappedOrderCount: number;
  excludedOrderCount: number;
  orderCodes: string[];
  storeCodes: string[];
  recipientUserIds: string[];
};

export type SalesReportsErpCachePageOwner = {
  id: string;
  email: string;
  storeCode: string | null;
  storeName: string | null;
  organizationNodeId: string | null;
};

export type SalesReportsErpCachePersistResult = {
  excluded: boolean;
  exclusionReason: string | null;
  storeCode?: string | null;
  orderCreatedAt?: Date | null;
};

export type SalesReportsErpCachePersistOptions = {
  existingCacheRow?: any | null;
  preserveVerifiedLifecycle?: boolean;
  canonicalGrandTotalFromList?: boolean;
};

export type SalesReportsErpCachePageCallbacks = {
  listRecentOrders(input: {
    date: string;
    limit: number;
    offset?: number;
  }): Promise<SalesReportErpOrderListItem[]>;
  loadExistingRows(orderCodes: string[]): Promise<any[]>;
  loadOwners(
    orders: SalesReportErpOrderListItem[],
    extraEmailValues: unknown[],
  ): Promise<Map<string, SalesReportsErpCachePageOwner>>;
  loadStores(storeCodes: string[]): Promise<Map<string, any>>;
  systemContext(): any;
  normalizeOrderCode(value: unknown): string;
  normalizeStoreCode(value: unknown): string | null;
  authoritativeStoreCodeForCache(
    snapshot: unknown,
    existingSnapshot?: unknown,
  ): string | null;
  syncOrderOwner(
    order: SalesReportErpOrderListItem,
    ownerByEmail: Map<string, SalesReportsErpCachePageOwner>,
  ): SalesReportsErpCachePageOwner | null;
  syncOrderOwnerFromEmails(
    emailValues: unknown[],
    ownerByEmail: Map<string, SalesReportsErpCachePageOwner>,
  ): SalesReportsErpCachePageOwner | null;
  persist(
    user: any,
    context: any,
    order: SalesReportErpOrderListItem,
    storeByCode: Map<string, any>,
    owner: SalesReportsErpCachePageOwner | null,
    options: SalesReportsErpCachePersistOptions,
  ): Promise<SalesReportsErpCachePersistResult>;
  log(message: string): void;
};

/**
 * Owns the paged ERP order-cache mapping algorithm. SalesReportsService keeps
 * the stable facade, scheduler, persistence transaction and realtime
 * publication; this runtime only coordinates one page and its aggregation.
 */
export class SalesReportsErpCachePageRuntime {
  constructor(private readonly callbacks: SalesReportsErpCachePageCallbacks) {}

  async sync(
    input: SalesReportsErpCachePageInput,
  ): Promise<SalesReportsErpCachePageResult> {
    const orders = await this.callbacks.listRecentOrders({
      date: input.date,
      limit: input.limit,
      offset: input.offset,
    });
    const orderCodes = orders
      .map((order) => this.callbacks.normalizeOrderCode(order.orderCode))
      .filter(Boolean);
    const existingRows = orderCodes.length
      ? ((await this.callbacks.loadExistingRows(orderCodes)) ?? [])
      : [];
    const existingByCode = new Map(
      existingRows
        .map((row: any) => [
          this.callbacks.normalizeOrderCode(row.orderCode),
          row,
        ])
        .filter((entry): entry is [string, any] => Boolean(entry[0])),
    );
    const existingCodes = new Set(
      existingRows.map((row: any) =>
        this.callbacks.normalizeOrderCode(row.orderCode),
      ),
    );
    const context = this.callbacks.systemContext();
    const ownerByEmail = await this.callbacks.loadOwners(
      orders,
      existingRows.flatMap((row: any) => [
        row.sourceUserEmail,
        row.consultantEmail,
        row.sellerEmail,
      ]),
    );
    const storeByCode = await this.callbacks.loadStores(
      [
        ...orders.flatMap((order) => {
          const orderCode = this.callbacks.normalizeOrderCode(order.orderCode);
          const existingRow = orderCode ? existingByCode.get(orderCode) : null;
          return [
            this.callbacks.authoritativeStoreCodeForCache(
              order.sanitizedSnapshot,
              existingRow?.sanitizedSnapshot,
            ),
          ];
        }),
      ].filter((code): code is string => Boolean(code)),
    );
    let ownerMappedCount = 0;
    let storeMappedCount = 0;
    let newOrderCount = 0;
    let mappedOrderCount = 0;
    let excludedOrderCount = 0;
    const storeCodes = new Set<string>();
    const recipientUserIds = new Set<string>();

    for (const order of orders) {
      const orderCode = this.callbacks.normalizeOrderCode(order.orderCode);
      const existingRow = orderCode ? existingByCode.get(orderCode) : null;
      const owner =
        this.callbacks.syncOrderOwner(order, ownerByEmail) ??
        this.callbacks.syncOrderOwnerFromEmails(
          [
            existingRow?.sourceUserEmail,
            existingRow?.consultantEmail,
            existingRow?.sellerEmail,
          ],
          ownerByEmail,
        );
      const isNew = orderCode ? !existingCodes.has(orderCode) : false;
      if (owner) ownerMappedCount += 1;
      const mappedStoreCode = this.callbacks.normalizeStoreCode(
        this.callbacks.authoritativeStoreCodeForCache(
          order.sanitizedSnapshot,
          existingRow?.sanitizedSnapshot,
        ),
      );
      if (mappedStoreCode) storeMappedCount += 1;
      const mappedStore = mappedStoreCode
        ? storeByCode.get(mappedStoreCode)
        : null;
      const mappedOrganizationNodeId = mappedStore?.organizationNodeId ?? null;
      const storeMappingChanged =
        existingRow &&
        (this.callbacks.normalizeStoreCode(existingRow.storeCode) !==
          mappedStoreCode ||
          (existingRow.organizationNodeId ?? null) !==
            mappedOrganizationNodeId);
      const mappingBackfilled =
        !isNew &&
        Boolean(
          storeMappingChanged ||
          (!existingRow?.sourceUserId && owner?.id) ||
          (!existingRow?.sourceUserEmail && owner?.email),
        );
      const cacheResult = await this.callbacks.persist(
        null,
        context,
        order,
        storeByCode,
        owner,
        {
          existingCacheRow: existingRow,
          preserveVerifiedLifecycle: true,
          canonicalGrandTotalFromList: true,
        },
      );
      const becameExcluded =
        cacheResult.excluded && !Boolean(existingRow?.excludedAt);
      const visibleNew = isNew && !cacheResult.excluded;
      const visibleMappingBackfilled =
        mappingBackfilled && !cacheResult.excluded;
      if (visibleNew) newOrderCount += 1;
      if (visibleMappingBackfilled) mappedOrderCount += 1;
      if (becameExcluded) excludedOrderCount += 1;
      if (
        (visibleNew || visibleMappingBackfilled || becameExcluded) &&
        owner?.id
      ) {
        recipientUserIds.add(owner.id);
      }
      if (
        (visibleNew || visibleMappingBackfilled || becameExcluded) &&
        mappedStoreCode
      ) {
        storeCodes.add(mappedStoreCode);
      }
    }

    this.callbacks.log(
      `Sales report ERP order cache mapping completed: source=${input.source} orders=${orders.length} newOrderCount=${newOrderCount} mappedOrderCount=${mappedOrderCount} excludedOrderCount=${excludedOrderCount} ownerMapped=${ownerMappedCount} storeMapped=${storeMappedCount} missingStore=${orders.length - storeMappedCount}`,
    );
    return {
      count: orders.length,
      newOrderCount,
      mappedOrderCount,
      excludedOrderCount,
      orderCodes,
      storeCodes: Array.from(storeCodes),
      recipientUserIds: Array.from(recipientUserIds),
    };
  }
}
