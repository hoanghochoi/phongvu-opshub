import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import {
  APP_NOTIFICATION_SOURCE_OFFSET_ADJUSTMENT,
  NotificationsService,
} from '../notifications';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import {
  csvCell as safeCsvCell,
  csvExcelTextCell as safeCsvExcelTextCell,
} from '../common/csv-export';
import { logFingerprint } from '../common/log-sanitizer';
import {
  CompleteOffsetAdjustmentDto,
  CreateOffsetAdjustmentDto,
  OFFSET_ADJUSTMENT_NOTIFICATION_STATUS,
  ExportOffsetAdjustmentsDto,
  ListOffsetAdjustmentsDto,
  OFFSET_ADJUSTMENT_STATUSES,
  OFFSET_ADJUSTMENT_TYPES,
  OFFSET_EDIT_CONTENT_KINDS,
  RejectOffsetAdjustmentDto,
  ResubmitOffsetAdjustmentDto,
} from './offset-adjustments.dto';

const OFFSET_ADJUSTMENT_CHANNEL = 'OFFSET_ADJUSTMENT_UPDATED';
const OFFSET_STATUS_PENDING = 'PENDING_ACC';
const OFFSET_STATUS_APPROVED = 'APPROVED';
const OFFSET_STATUS_REJECTED = 'REJECTED_NEEDS_FIX';
const OFFSET_TYPE_SINGLE_ORDER = 'SINGLE_ORDER';
const OFFSET_TYPE_VNPAY_QROFF = 'VNPAY_QROFF';
const FIN_ACC_DEPARTMENT_CODE = 'FIN_ACC';
const ACC_DEPARTMENT_CODE = 'ACC';
const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';
const VIETNAM_UTC_OFFSET_MS = 7 * 60 * 60 * 1000;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

type OffsetInput = CreateOffsetAdjustmentDto | ResubmitOffsetAdjustmentDto;

type NormalizedOffsetData = {
  type: string;
  amount: number;
  oldOrderCode: string | null;
  newOrderCode: string | null;
  orderCode: string | null;
  scanDate: Date | null;
  editContentKind: string | null;
  transactionCode: string | null;
  note: string | null;
};

type OffsetScope = {
  reviewer: boolean;
  where: Prisma.OffsetAdjustmentWhereInput;
};

@Injectable()
export class OffsetAdjustmentsService {
  private readonly logger = new Logger(OffsetAdjustmentsService.name);

  constructor(
    private prisma: PrismaService,
    @Optional() private readonly redisService?: RedisService,
    @Optional() private readonly notificationsService?: NotificationsService,
  ) {}

  async list(user: any, input: ListOffsetAdjustmentsDto) {
    const startedAt = Date.now();
    const filters = this.normalizeListFilters(input);
    const scope = await this.resolveScope(user, {
      requestedAllStores: filters.requestedAllStores,
      storeIds: filters.storeIds,
    });
    const where = this.buildListWhere(user, scope, filters);
    this.logger.log(
      `Offset adjustments list started: user=${this.safeUserLabel(user)} reviewer=${scope.reviewer} storeCount=${filters.storeIds.length} type=${filters.type || 'ALL'} status=${filters.status || 'ALL'} page=${filters.page} limit=${filters.limit}`,
    );

    const [rows, total] = await Promise.all([
      this.prisma.offsetAdjustment.findMany({
        where,
        orderBy: { submittedAt: 'desc' },
        skip: filters.page * filters.limit,
        take: filters.limit,
      }),
      this.prisma.offsetAdjustment.count({ where }),
    ]);
    const singleCounts = await this.singleOrderCounts(scope.where, rows);
    const readAtById =
      filters.status === OFFSET_ADJUSTMENT_NOTIFICATION_STATUS
        ? await this.notificationReadAtById(
            user,
            APP_NOTIFICATION_SOURCE_OFFSET_ADJUSTMENT,
            rows.map((row) => row.id),
          )
        : new Map<string, Date>();

    this.logger.log(
      `Offset adjustments list succeeded: user=${this.safeUserLabel(user)} reviewer=${scope.reviewer} count=${rows.length} total=${total} unread=${rows.filter((row) => !readAtById.has(row.id)).length} durationMs=${Date.now() - startedAt}`,
    );
    return {
      list: rows.map((row) =>
        this.toDto(row, user, scope, singleCounts, readAtById.get(row.id)),
      ),
      page: filters.page,
      limit: filters.limit,
      total,
      canReview: scope.reviewer,
    };
  }

  async exportCsv(user: any, input: ExportOffsetAdjustmentsDto) {
    const startedAt = Date.now();
    const filters = this.normalizeListFilters(input);
    const scope = await this.resolveScope(user, {
      requestedAllStores: filters.requestedAllStores,
      storeIds: filters.storeIds,
    });
    const where = this.buildListWhere(user, scope, filters);
    this.logger.log(
      `Offset adjustments export started: user=${this.safeUserLabel(user)} reviewer=${scope.reviewer} storeCount=${filters.storeIds.length} type=${filters.type || 'ALL'} status=${filters.status || 'ALL'}`,
    );
    try {
      const rows = await this.prisma.offsetAdjustment.findMany({
        where,
        orderBy: { submittedAt: 'desc' },
      });
      this.logger.log(
        `Offset adjustments export succeeded: user=${this.safeUserLabel(user)} reviewer=${scope.reviewer} count=${rows.length} durationMs=${Date.now() - startedAt}`,
      );
      return this.toCsv(rows);
    } catch (error) {
      this.logger.error(
        `Offset adjustments export failed: user=${this.safeUserLabel(user)} reviewer=${scope.reviewer} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async create(user: any, input: CreateOffsetAdjustmentDto) {
    const startedAt = Date.now();
    if (await this.canReview(user)) {
      throw new ForbiddenException('Kế toán chỉ xác nhận hồ sơ cấn trừ.');
    }
    const store = await this.resolveUserStore(user);
    const data = this.normalizeOffsetData(input.type, input);
    await this.assertNoDuplicateWalletFields(data);

    try {
      this.logger.log(
        `Offset adjustment create started: user=${this.safeUserLabel(user)} store=${store.storeId} type=${data.type} amount=${data.amount}`,
      );
      const row = await this.prisma.offsetAdjustment.create({
        data: {
          ...data,
          status: OFFSET_STATUS_PENDING,
          storeCode: store.storeId,
          createdByUserId: user?.id || null,
          createdByEmail: this.safeUserEmail(user),
        },
      });
      await this.writeHistory(row, 'CREATED', user, null, row.status);
      await this.publishOffsetEvent(row);
      this.logger.log(
        `Offset adjustment create succeeded: user=${this.safeUserLabel(user)} id=${row.id} store=${row.storeCode} type=${row.type} durationMs=${Date.now() - startedAt}`,
      );
      return this.toDto(row, user, {
        reviewer: false,
        where: { storeCode: store.storeId },
      });
    } catch (error) {
      if (this.isUniqueConflict(error)) {
        throw new BadRequestException('Hồ sơ cấn trừ loại này đã có mã trùng.');
      }
      this.logger.error(
        `Offset adjustment create failed: user=${this.safeUserLabel(user)} store=${store.storeId} type=${data.type} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async detail(user: any, id: string) {
    const scope = await this.resolveScope(user, {});
    const row = await this.prisma.offsetAdjustment.findFirst({
      where: this.andWhere(scope.where, { id: this.normalizeRequiredId(id) }),
    });
    if (!row) throw new NotFoundException('Không tìm thấy hồ sơ cấn trừ.');
    const singleCounts = await this.singleOrderCounts(scope.where, [row]);
    return this.toDto(row, user, scope, singleCounts);
  }

  async resubmit(user: any, id: string, input: ResubmitOffsetAdjustmentDto) {
    const startedAt = Date.now();
    if (await this.canReview(user)) {
      throw new ForbiddenException('Kế toán chỉ xác nhận hồ sơ cấn trừ.');
    }
    const store = await this.resolveUserStore(user);
    const current = await this.prisma.offsetAdjustment.findFirst({
      where: { id: this.normalizeRequiredId(id), storeCode: store.storeId },
    });
    if (!current) throw new NotFoundException('Không tìm thấy hồ sơ cấn trừ.');
    if (current.status !== OFFSET_STATUS_REJECTED) {
      throw new BadRequestException('Chỉ sửa lại hồ sơ đang bị từ chối.');
    }
    const data = this.normalizeOffsetData(current.type, {
      amount: input.amount ?? current.amount,
      oldOrderCode: input.oldOrderCode ?? current.oldOrderCode ?? undefined,
      newOrderCode: input.newOrderCode ?? current.newOrderCode ?? undefined,
      orderCode: input.orderCode ?? current.orderCode ?? undefined,
      scanDate:
        input.scanDate ??
        this.formatDateForInput(current.scanDate) ??
        undefined,
      editContentKind:
        input.editContentKind ?? current.editContentKind ?? undefined,
      transactionCode:
        input.transactionCode ?? current.transactionCode ?? undefined,
      note: input.note ?? current.note ?? undefined,
    });
    await this.assertNoDuplicateWalletFields(data, current.id);

    try {
      const row = await this.prisma.offsetAdjustment.update({
        where: { id: current.id },
        data: {
          ...data,
          status: OFFSET_STATUS_PENDING,
          rejectReason: null,
          reviewedByUserId: null,
          reviewedByEmail: null,
          reviewedAt: null,
          ctCode: null,
          submittedAt: new Date(),
        },
      });
      await this.writeHistory(
        row,
        'RESUBMITTED',
        user,
        current.status,
        row.status,
      );
      await this.publishOffsetEvent(row);
      this.logger.log(
        `Offset adjustment resubmitted: user=${this.safeUserLabel(user)} id=${row.id} store=${row.storeCode} type=${row.type} durationMs=${Date.now() - startedAt}`,
      );
      return this.toDto(row, user, {
        reviewer: false,
        where: { storeCode: store.storeId },
      });
    } catch (error) {
      if (this.isUniqueConflict(error)) {
        throw new BadRequestException('Hồ sơ cấn trừ loại này đã có mã trùng.');
      }
      this.logger.error(
        `Offset adjustment resubmit failed: user=${this.safeUserLabel(user)} id=${current.id} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async complete(user: any, id: string, input: CompleteOffsetAdjustmentDto) {
    const startedAt = Date.now();
    const scope = await this.resolveReviewerScope(user);
    const current = await this.findReviewable(user, scope, id);
    if (current.status !== OFFSET_STATUS_PENDING) {
      throw new BadRequestException(
        'Hồ sơ đã được xử lý hoặc đang chờ SR sửa.',
      );
    }
    const ctCode =
      current.type === OFFSET_TYPE_VNPAY_QROFF
        ? this.normalizeRequiredText(input.ctCode, 'Vui lòng nhập Mã CT.')
        : null;
    const reviewedAt = new Date();
    const row = await this.prisma.offsetAdjustment.update({
      where: { id: current.id },
      data: {
        status: OFFSET_STATUS_APPROVED,
        ctCode,
        rejectReason: null,
        reviewedByUserId: user?.id || null,
        reviewedByEmail: this.safeUserEmail(user),
        reviewedAt,
      },
    });
    await this.writeHistory(row, 'COMPLETED', user, current.status, row.status);
    await this.publishOffsetEvent(row);
    this.logger.log(
      `Offset adjustment completed: user=${this.safeUserLabel(user)} id=${row.id} store=${row.storeCode} type=${row.type} durationMs=${Date.now() - startedAt}`,
    );
    return this.toDto(row, user, scope);
  }

  async reject(user: any, id: string, input: RejectOffsetAdjustmentDto) {
    const startedAt = Date.now();
    const scope = await this.resolveReviewerScope(user);
    const current = await this.findReviewable(user, scope, id);
    if (current.status !== OFFSET_STATUS_PENDING) {
      throw new BadRequestException(
        'Hồ sơ đã được xử lý hoặc đang chờ SR sửa.',
      );
    }
    const reason = this.normalizeRequiredText(
      input.reason,
      'Vui lòng nhập lý do từ chối.',
    );
    const reviewedAt = new Date();
    const row = await this.prisma.offsetAdjustment.update({
      where: { id: current.id },
      data: {
        status: OFFSET_STATUS_REJECTED,
        rejectReason: reason,
        reviewedByUserId: user?.id || null,
        reviewedByEmail: this.safeUserEmail(user),
        reviewedAt,
      },
    });
    await this.writeHistory(
      row,
      'REJECTED',
      user,
      current.status,
      row.status,
      reason,
    );
    await this.publishOffsetEvent(row);
    this.logger.log(
      `Offset adjustment rejected: user=${this.safeUserLabel(user)} id=${row.id} store=${row.storeCode} type=${row.type} durationMs=${Date.now() - startedAt}`,
    );
    return this.toDto(row, user, scope);
  }

  private async findReviewable(user: any, scope: OffsetScope, id: string) {
    const row = await this.prisma.offsetAdjustment.findFirst({
      where: this.andWhere(scope.where, { id: this.normalizeRequiredId(id) }),
    });
    if (!row) throw new NotFoundException('Không tìm thấy hồ sơ cấn trừ.');
    if (!scope.reviewer) {
      throw new ForbiddenException('Bạn không có quyền xác nhận cấn trừ.');
    }
    return row;
  }

  private async resolveReviewerScope(user: any): Promise<OffsetScope> {
    const scope = await this.resolveScope(user, { requestedAllStores: true });
    if (!scope.reviewer) {
      throw new ForbiddenException('Bạn không có quyền xác nhận cấn trừ.');
    }
    return scope;
  }

  private normalizeOffsetData(typeInput: unknown, input: OffsetInput) {
    const type = this.normalizeType(typeInput);
    const amount = this.normalizeAmount((input as any).amount);
    if (type === OFFSET_TYPE_SINGLE_ORDER) {
      const oldOrderCode = this.normalizeRequiredText(
        (input as any).oldOrderCode,
        'Vui lòng nhập đơn hàng cũ.',
      );
      const newOrderCode = this.normalizeRequiredText(
        (input as any).newOrderCode,
        'Vui lòng nhập đơn hàng mới.',
      );
      if (oldOrderCode === newOrderCode) {
        throw new BadRequestException(
          'Mã đơn cũ và mã đơn mới không được trùng nhau.',
        );
      }
      return {
        type,
        amount,
        oldOrderCode,
        newOrderCode,
        orderCode: null,
        scanDate: null,
        editContentKind: null,
        transactionCode: null,
        note: this.normalizeOptionalText((input as any).note),
      };
    }

    return {
      type,
      amount,
      oldOrderCode: null,
      newOrderCode: null,
      orderCode: this.normalizeRequiredText(
        (input as any).orderCode,
        'Vui lòng nhập đơn hàng.',
      ),
      scanDate: this.parseDateInput((input as any).scanDate),
      editContentKind: this.normalizeEditContentKind(
        (input as any).editContentKind,
      ),
      transactionCode: this.normalizeRequiredText(
        (input as any).transactionCode,
        'Vui lòng nhập mã giao dịch.',
      ),
      note: this.normalizeOptionalText((input as any).note),
    };
  }

  private async assertNoDuplicateWalletFields(
    data: NormalizedOffsetData,
    currentId?: string,
  ) {
    if (data.type === OFFSET_TYPE_SINGLE_ORDER) return;
    const where: Prisma.OffsetAdjustmentWhereInput = {
      type: data.type,
      OR: [
        { orderCode: data.orderCode },
        { transactionCode: data.transactionCode },
      ],
      ...(currentId ? { id: { not: currentId } } : {}),
    };
    const existing = await this.prisma.offsetAdjustment.findFirst({ where });
    if (!existing) return;
    if (existing.orderCode === data.orderCode) {
      throw new BadRequestException('Đơn hàng đã có hồ sơ cấn trừ loại này.');
    }
    throw new BadRequestException('Mã giao dịch đã có hồ sơ cấn trừ loại này.');
  }

  private normalizeListFilters(input: ListOffsetAdjustmentsDto) {
    const dateRange = this.normalizeDateRange(input.startDate, input.endDate);
    const type =
      input.type && input.type !== 'ALL'
        ? this.normalizeType(input.type)
        : null;
    const status =
      input.status && input.status !== 'ALL'
        ? this.normalizeStatus(input.status)
        : null;
    return {
      requestedAllStores: this.isTrue(input.allStores),
      storeIds: this.parseStoreCodes(input.storeIds),
      type,
      status,
      order: this.normalizeOptionalText(input.order),
      amount: this.normalizeOptionalAmount(input.amount),
      dateRange,
      page: Math.max(0, Number(input.page || 0)),
      limit: Math.min(100, Math.max(1, Number(input.limit || 20))),
    };
  }

  private buildFilterWhere(filters: {
    type: string | null;
    status: string | null;
    order: string | null;
    amount: number | null;
    dateRange: { start: Date; end: Date } | null;
  }): Prisma.OffsetAdjustmentWhereInput {
    const parts: Prisma.OffsetAdjustmentWhereInput[] = [];
    if (filters.dateRange) {
      parts.push({
        submittedAt: {
          gte: filters.dateRange.start,
          lt: filters.dateRange.end,
        },
      });
    }
    if (filters.type) parts.push({ type: filters.type });
    if (filters.status) parts.push({ status: filters.status });
    if (filters.amount !== null) parts.push({ amount: filters.amount });
    if (filters.order) {
      parts.push({
        OR: [
          { oldOrderCode: filters.order },
          { newOrderCode: filters.order },
          { orderCode: filters.order },
        ],
      });
    }
    return this.andWhere(...parts);
  }

  private buildListWhere(
    user: any,
    scope: OffsetScope,
    filters: {
      type: string | null;
      status: string | null;
      order: string | null;
      amount: number | null;
      dateRange: { start: Date; end: Date } | null;
    },
  ): Prisma.OffsetAdjustmentWhereInput {
    if (filters.status !== OFFSET_ADJUSTMENT_NOTIFICATION_STATUS) {
      return this.andWhere(scope.where, this.buildFilterWhere(filters));
    }

    const baseFilters = this.buildFilterWhere({ ...filters, status: null });
    if (scope.reviewer) {
      return this.andWhere(scope.where, baseFilters, {
        status: OFFSET_STATUS_PENDING,
      });
    }

    return this.andWhere(scope.where, baseFilters, {
      status: OFFSET_STATUS_REJECTED,
      createdByUserId: String(user?.id || '__missing_user__'),
    });
  }

  private async resolveScope(
    user: any,
    input: { requestedAllStores?: boolean; storeIds?: string[] },
  ): Promise<OffsetScope> {
    const reviewer = await this.canReview(user);
    const storeIds = input.storeIds || [];
    if (reviewer) {
      if (input.requestedAllStores || storeIds.length === 0) {
        return { reviewer, where: {} };
      }
      return { reviewer, where: { storeCode: { in: storeIds } } };
    }

    const allowedStores = await this.resolveUserStores(user);
    const allowedStoreCodes = allowedStores.map((store) => store.storeId);
    if (input.requestedAllStores) {
      throw new ForbiddenException('Không có quyền xem tất cả showroom.');
    }
    const selectedStoreCodes =
      storeIds.length > 0 ? storeIds : allowedStoreCodes;
    const invalidStore = selectedStoreCodes.find(
      (storeCode) => !allowedStoreCodes.includes(storeCode),
    );
    if (invalidStore) {
      throw new ForbiddenException('Chỉ được xem hồ sơ showroom được gán.');
    }
    return {
      reviewer,
      where: { storeCode: this.storeCodeWhere(selectedStoreCodes) },
    };
  }

  private async resolveUserStore(user: any) {
    const stores = await this.resolveUserStores(user);
    return stores[0];
  }

  private async resolveUserStores(user: any) {
    const storesByCode = new Map<string, any>();
    const pushStore = (store: any) => {
      const storeCode = String(store?.storeId || '')
        .trim()
        .toUpperCase();
      if (storeCode && !storesByCode.has(storeCode)) {
        storesByCode.set(storeCode, store);
      }
    };

    if (user?.id) {
      const savedUser = await (this.prisma as any).user?.findUnique?.({
        where: { id: user.id },
        include: {
          store: true,
          organizationAssignments: {
            where: { isActive: true },
            orderBy: [
              { isPrimary: Prisma.SortOrder.desc },
              { createdAt: Prisma.SortOrder.asc },
            ],
            include: {
              organizationNode: {
                include: organizationNodeStoreTreeInclude(),
              },
            },
          },
        },
      });
      pushStore(savedUser?.store);
      for (const assignment of savedUser?.organizationAssignments ?? []) {
        for (const store of storesForOrganizationNodeTree(
          assignment.organizationNode,
        )) {
          pushStore(store);
        }
      }
    }

    if (storesByCode.size === 0 && user?.storeId) {
      const store = await this.prisma.store.findUnique({
        where: { id: user.storeId },
      });
      pushStore(store);
    }
    if (storesByCode.size === 0 && user?.storeCode) {
      const store = await this.prisma.store.findUnique({
        where: { storeId: user.storeCode },
      });
      pushStore(store);
    }

    const stores = Array.from(storesByCode.values());
    if (stores.length === 0) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom.');
    }
    return stores;
  }

  private storeCodeWhere(storeCodes: string[]) {
    return storeCodes.length === 1 ? storeCodes[0] : { in: storeCodes };
  }

  private async canReview(user: any): Promise<boolean> {
    return this.userMatchesAccessCodes(user, [
      ACC_DEPARTMENT_CODE,
      FIN_ACC_DEPARTMENT_CODE,
    ]);
  }

  private async userMatchesAccessCodes(user: any, allowedCodes: string[]) {
    if (String(user?.role || '').toUpperCase() === SUPER_ADMIN_ROLE)
      return true;
    const allowed = new Set(
      allowedCodes.map((code) => this.normalizeAccessCode(code)),
    );
    let departmentCode = this.normalizeAccessCode(user?.departmentCode);
    let organizationNodeId = String(user?.organizationNodeId || '').trim();

    if ((!departmentCode || !organizationNodeId) && user?.id) {
      const stored = await (this.prisma as any).user?.findUnique?.({
        where: { id: user.id },
        select: { departmentCode: true, organizationNodeId: true },
      });
      departmentCode ||= this.normalizeAccessCode(stored?.departmentCode);
      organizationNodeId ||= String(stored?.organizationNodeId || '').trim();
    }

    if (allowed.has(departmentCode)) return true;
    if (!organizationNodeId) return false;
    return this.organizationNodeMatchesAccessCodes(organizationNodeId, allowed);
  }

  private async organizationNodeMatchesAccessCodes(
    nodeId: string,
    allowedCodes: Set<string>,
  ) {
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return false;
    const nodes: Array<{
      id: string;
      parentId: string | null;
      code: string | null;
      businessCode: string | null;
    }> = await organizationNode.findMany({
      select: { id: true, parentId: true, code: true, businessCode: true },
    });
    const byId = new Map(nodes.map((node) => [node.id, node]));
    let cursor = byId.get(nodeId);
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      if (
        allowedCodes.has(this.normalizeAccessCode(cursor.code)) ||
        allowedCodes.has(this.normalizeAccessCode(cursor.businessCode))
      ) {
        return true;
      }
      cursor = cursor.parentId ? byId.get(cursor.parentId) : undefined;
    }
    return false;
  }

  private async singleOrderCounts(
    scopeWhere: Prisma.OffsetAdjustmentWhereInput,
    rows: Array<{ type: string; oldOrderCode: string | null }>,
  ) {
    const codes = Array.from(
      new Set(
        rows
          .filter((row) => row.type === OFFSET_TYPE_SINGLE_ORDER)
          .map((row) => row.oldOrderCode)
          .filter((code): code is string => !!code),
      ),
    );
    const counts = new Map<string, number>();
    await Promise.all(
      codes.map(async (code) => {
        const count = await this.prisma.offsetAdjustment.count({
          where: this.andWhere(scopeWhere, {
            type: OFFSET_TYPE_SINGLE_ORDER,
            oldOrderCode: code,
          }),
        });
        counts.set(code, count);
      }),
    );
    return counts;
  }

  private async writeHistory(
    row: any,
    action: string,
    user: any,
    fromStatus: string | null,
    toStatus: string | null,
    reason?: string,
  ) {
    await this.prisma.offsetAdjustmentHistory.create({
      data: {
        adjustmentId: row.id,
        action,
        fromStatus,
        toStatus,
        actorUserId: user?.id || null,
        actorEmail: this.safeUserEmail(user),
        reason: reason || null,
        snapshot: this.historySnapshot(row),
      },
    });
  }

  private async publishOffsetEvent(row: {
    id: string;
    storeCode: string;
    type: string;
    status: string;
    updatedAt: Date;
  }) {
    if (!this.redisService) {
      this.logger.warn(
        `Offset adjustment realtime skipped: redis unavailable id=${row.id}`,
      );
      return;
    }
    await this.redisService.publishMessage(OFFSET_ADJUSTMENT_CHANNEL, {
      adjustmentId: row.id,
      storeCode: row.storeCode,
      type: row.type,
      status: row.status,
      updatedAt: row.updatedAt.toISOString(),
    });
  }

  private toDto(
    row: any,
    user: any,
    scope: OffsetScope,
    singleCounts = new Map<string, number>(),
    notificationReadAt?: Date | null,
  ) {
    const canResubmit =
      !scope.reviewer && row.status === OFFSET_STATUS_REJECTED;
    return {
      id: row.id,
      type: row.type,
      status: row.status,
      storeCode: row.storeCode,
      oldOrderCode: row.oldOrderCode,
      newOrderCode: row.newOrderCode,
      orderCode: row.orderCode,
      scanDate: this.formatDateForInput(row.scanDate),
      editContentKind: row.editContentKind,
      transactionCode: row.transactionCode,
      amount: row.amount,
      note: row.note,
      ctCode: row.ctCode,
      rejectReason: row.rejectReason,
      createdByEmail: row.createdByEmail,
      reviewedByEmail: row.reviewedByEmail,
      submittedAt: row.submittedAt?.toISOString?.() ?? row.submittedAt,
      reviewedAt: row.reviewedAt?.toISOString?.() ?? row.reviewedAt,
      createdAt: row.createdAt?.toISOString?.() ?? row.createdAt,
      updatedAt: row.updatedAt?.toISOString?.() ?? row.updatedAt,
      notificationReadAt:
        notificationReadAt?.toISOString?.() ?? notificationReadAt ?? null,
      singleOrderReuseCount:
        row.type === OFFSET_TYPE_SINGLE_ORDER && row.oldOrderCode
          ? singleCounts.get(row.oldOrderCode) || 1
          : null,
      canReview: scope.reviewer,
      canResubmit,
    };
  }

  private async notificationReadAtById(
    user: any,
    source: typeof APP_NOTIFICATION_SOURCE_OFFSET_ADJUSTMENT,
    ids: string[],
  ) {
    if (!this.notificationsService) return new Map<string, Date>();
    try {
      return await this.notificationsService.readAtByNotificationId(
        user,
        source,
        ids,
      );
    } catch (error) {
      this.logger.warn(
        `Offset adjustment read-state load failed: user=${this.safeUserLabel(user)} count=${ids.length} error=${this.safeError(error)}`,
      );
      return new Map<string, Date>();
    }
  }

  private historySnapshot(row: any) {
    return {
      id: row.id,
      type: row.type,
      status: row.status,
      storeCode: row.storeCode,
      amount: row.amount,
      oldOrderCode: row.oldOrderCode,
      newOrderCode: row.newOrderCode,
      orderCode: row.orderCode,
      transactionCode: row.transactionCode,
      editContentKind: row.editContentKind,
      ctCode: row.ctCode,
    };
  }

  private andWhere(
    ...parts: Prisma.OffsetAdjustmentWhereInput[]
  ): Prisma.OffsetAdjustmentWhereInput {
    const compact = parts.filter((part) => Object.keys(part).length > 0);
    if (compact.length === 0) return {};
    if (compact.length === 1) return compact[0];
    return { AND: compact };
  }

  private normalizeType(value: unknown) {
    const type = String(value || '')
      .trim()
      .toUpperCase();
    if (!(OFFSET_ADJUSTMENT_TYPES as readonly string[]).includes(type)) {
      throw new BadRequestException('Loại cấn trừ không hợp lệ.');
    }
    return type;
  }

  private normalizeStatus(value: unknown) {
    const status = String(value || '')
      .trim()
      .toUpperCase();
    if (
      status !== OFFSET_ADJUSTMENT_NOTIFICATION_STATUS &&
      !(OFFSET_ADJUSTMENT_STATUSES as readonly string[]).includes(status)
    ) {
      throw new BadRequestException('Trạng thái cấn trừ không hợp lệ.');
    }
    return status;
  }

  private normalizeEditContentKind(value: unknown) {
    const kind = String(value || '')
      .trim()
      .toUpperCase();
    if (!(OFFSET_EDIT_CONTENT_KINDS as readonly string[]).includes(kind)) {
      throw new BadRequestException('Nội dung cần sửa không hợp lệ.');
    }
    return kind;
  }

  private normalizeAmount(value: unknown) {
    const amount =
      typeof value === 'number'
        ? value
        : Number(String(value || '').replace(/[^0-9]/g, ''));
    if (!Number.isInteger(amount) || amount <= 0) {
      throw new BadRequestException('Số tiền không hợp lệ.');
    }
    return amount;
  }

  private normalizeOptionalAmount(value: unknown) {
    const text = String(value || '').replace(/[^0-9]/g, '');
    if (!text) return null;
    return this.normalizeAmount(text);
  }

  private normalizeRequiredText(value: unknown, message: string) {
    const text = this.normalizeOptionalText(value);
    if (!text) throw new BadRequestException(message);
    return text;
  }

  private normalizeOptionalText(value: unknown) {
    const text = String(value ?? '').trim();
    return text.length === 0 ? null : text;
  }

  private normalizeRequiredId(value: unknown) {
    return this.normalizeRequiredText(value, 'Hồ sơ cấn trừ không hợp lệ.');
  }

  private normalizeAccessCode(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase();
  }

  private parseStoreCodes(value?: string) {
    return Array.from(
      new Set(
        String(value || '')
          .split(',')
          .map((item) => item.trim().toUpperCase())
          .filter(Boolean),
      ),
    );
  }

  private isTrue(value?: string) {
    return (
      String(value || '')
        .trim()
        .toLowerCase() === 'true'
    );
  }

  private parseDateInput(value: unknown) {
    const text = this.normalizeRequiredText(value, 'Vui lòng nhập ngày quét.');
    return this.parseDateOnly(text);
  }

  private normalizeDateRange(startInput?: string, endInput?: string) {
    if (!startInput && !endInput) return null;
    const start = this.parseDateOnly(startInput || endInput || '');
    const endSource = endInput ? this.parseDateOnly(endInput) : start;
    const [from, to] =
      endSource < start ? [endSource, start] : [start, endSource];
    return { start: from, end: new Date(to.getTime() + MS_PER_DAY) };
  }

  private parseDateOnly(value: string) {
    const text = String(value || '').trim();
    const slashMatch = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(text);
    const dashMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
    const match = slashMatch || dashMatch;
    if (!match) throw new BadRequestException('Ngày không hợp lệ.');
    const day = slashMatch ? Number(match[1]) : Number(match[3]);
    const month = Number(match[2]);
    const year = slashMatch ? Number(match[3]) : Number(match[1]);
    const date = this.vietnamDateToUtcStart(year, month, day);
    const check = new Date(date.getTime() + VIETNAM_UTC_OFFSET_MS);
    if (
      check.getUTCFullYear() !== year ||
      check.getUTCMonth() + 1 !== month ||
      check.getUTCDate() !== day
    ) {
      throw new BadRequestException('Ngày không hợp lệ.');
    }
    return date;
  }

  private vietnamDateToUtcStart(year: number, month: number, day: number) {
    return new Date(Date.UTC(year, month - 1, day) - VIETNAM_UTC_OFFSET_MS);
  }

  private formatDateForInput(value?: Date | string | null) {
    if (!value) return null;
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) return null;
    const vietnam = new Date(date.getTime() + VIETNAM_UTC_OFFSET_MS);
    const two = (part: number) => String(part).padStart(2, '0');
    return `${vietnam.getUTCFullYear()}-${two(vietnam.getUTCMonth() + 1)}-${two(vietnam.getUTCDate())}`;
  }

  private toCsv(rows: Array<Record<string, any>>) {
    const headers = [
      'SR',
      'Loại',
      'Trạng thái',
      'Đơn hàng cũ',
      'Đơn hàng mới',
      'Đơn hàng',
      'Ngày quét',
      'Nội dung cần sửa',
      'Mã giao dịch',
      'Số tiền',
      'Mã CT',
      'Ghi chú',
      'Lý do từ chối',
      'Người nhập',
      'Kế toán xử lý',
      'Ngày gửi',
      'Ngày xử lý',
    ];
    const lines = [headers.map((value) => this.csvCell(value)).join(',')];
    for (const row of rows) {
      lines.push(
        [
          this.csvCell(row.storeCode),
          this.csvCell(this.typeLabel(row.type)),
          this.csvCell(this.statusLabel(row.status)),
          this.csvExcelTextCell(row.oldOrderCode),
          this.csvExcelTextCell(row.newOrderCode),
          this.csvExcelTextCell(row.orderCode),
          this.csvCell(this.csvVietnamDate(row.scanDate, false)),
          this.csvCell(this.editContentKindLabel(row.editContentKind)),
          this.csvExcelTextCell(row.transactionCode),
          this.csvAmountCell(row.amount),
          this.csvExcelTextCell(row.ctCode),
          this.csvCell(row.note),
          this.csvCell(row.rejectReason),
          this.csvCell(row.createdByEmail),
          this.csvCell(row.reviewedByEmail),
          this.csvCell(this.csvVietnamDate(row.submittedAt)),
          this.csvCell(this.csvVietnamDate(row.reviewedAt)),
        ].join(','),
      );
    }
    return `${String.fromCharCode(0xfeff)}${lines.join('\r\n')}`;
  }

  private typeLabel(type: unknown) {
    switch (String(type || '').toUpperCase()) {
      case 'SINGLE_ORDER':
        return 'Cấn trừ đơn';
      case 'VNPAY_QROFF':
        return 'VNPAY QROFF';
      case 'ZALOPAY':
        return 'Zalo Pay';
      case 'SHOPEEPAY':
        return 'Shopee Pay';
      default:
        return this.csvText(type);
    }
  }

  private statusLabel(status: unknown) {
    switch (String(status || '').toUpperCase()) {
      case OFFSET_STATUS_PENDING:
        return 'Chờ Kế toán xác nhận';
      case OFFSET_STATUS_APPROVED:
        return 'Kế toán đã xác nhận';
      case OFFSET_STATUS_REJECTED:
        return 'Kế toán từ chối chờ sửa';
      default:
        return this.csvText(status);
    }
  }

  private editContentKindLabel(kind: unknown) {
    switch (String(kind || '').toUpperCase()) {
      case 'CUSTOMER_OFFSET':
        return 'Cấn trừ KH';
      case 'TECHNICIAN_OFFSET':
        return 'Cấn trừ KTV';
      default:
        return this.csvText(kind);
    }
  }

  private csvCell(value: unknown) {
    return safeCsvCell(value);
  }

  private csvExcelTextCell(value: unknown) {
    return safeCsvExcelTextCell(value);
  }

  private csvAmountCell(value: unknown) {
    const amount = Number(value);
    if (!Number.isFinite(amount)) return '';
    return String(Math.trunc(amount));
  }

  private csvVietnamDate(value: unknown, includeTime = true) {
    if (!value) return '';
    const date = value instanceof Date ? value : new Date(String(value));
    if (Number.isNaN(date.getTime())) return '';
    const vietnam = new Date(date.getTime() + VIETNAM_UTC_OFFSET_MS);
    const two = (part: number) => String(part).padStart(2, '0');
    const dateText = `${two(vietnam.getUTCDate())}/${two(vietnam.getUTCMonth() + 1)}/${vietnam.getUTCFullYear()}`;
    if (!includeTime) return dateText;
    return `${dateText} ${two(vietnam.getUTCHours())}:${two(vietnam.getUTCMinutes())}:${two(vietnam.getUTCSeconds())}`;
  }

  private csvText(value: unknown) {
    return value === null || value === undefined ? '' : String(value);
  }

  private safeUserEmail(user: any) {
    const email = String(user?.email || '')
      .trim()
      .toLowerCase();
    return email || null;
  }

  private safeUserLabel(user: any) {
    const userId = String(user?.id || '').trim();
    if (userId) return `userId:${userId}`;
    const email = this.safeUserEmail(user);
    return email ? `emailHash:${logFingerprint(email)}` : 'unknown';
  }

  private safeError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }

  private isUniqueConflict(error: any) {
    return error?.code === 'P2002';
  }
}
