import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { buildRealtimeRedisEnvelope } from '../common/realtime-event';
import { FEATURE_KEYS } from '../feature/feature.constants';
import {
  AssignSalesReportFollowUpCaseDto,
  CreateSalesReportFollowUpEntryDto,
  ListSalesReportFollowUpCasesDto,
  NOT_PURCHASED_REASON_CODES,
} from './sales-reports.dto';
import { SalesReportsService } from './sales-reports.service';

const MANAGER_ROLE_CODES = new Set([
  'STORE_MANAGER',
  'AREA_MANAGER',
  'REGION_MANAGER',
  'REGIONAL_MANAGER',
]);
const HIDDEN_STATUSES = ['PURCHASED_ELSEWHERE', 'NO_LONGER_INTERESTED'];
const REALTIME_CHANNEL = 'SALES_REPORT_ORDERS_UPDATED';
const INVALID_CONTACT_VALUES = new Set([
  '0',
  'không cung cấp',
  'khong cung cap',
  'không có',
  'khong co',
  'none',
  'null',
  'n/a',
]);

const CASE_INCLUDE = {
  sourceReport: {
    include: {
      categorySelections: { orderBy: { sortOrder: Prisma.SortOrder.asc } },
    },
  },
  entries: { orderBy: { sequenceNumber: Prisma.SortOrder.asc } },
} as const;

@Injectable()
export class SalesReportFollowUpsService {
  private readonly logger = new Logger(SalesReportFollowUpsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly salesReports: SalesReportsService,
    private readonly redis: RedisService,
  ) {}

  async list(user: any, query: ListSalesReportFollowUpCasesDto) {
    const startedAt = Date.now();
    const principal = await this.principal(user);
    const manager = this.isManager(user, principal);
    const scopeWhere = await this.scopeWhere(user, principal, manager);
    const status = query.status === 'HIDDEN' ? 'HIDDEN' : 'OPEN';
    const page = Math.max(0, Number(query.page) || 0);
    const limit = Math.min(100, Math.max(1, Number(query.limit) || 20));
    const search = this.text(query.search, 120);
    const storeCode = this.storeCode(query.storeCode);
    const assigneeUserId = this.text(query.assigneeUserId, 80);

    if (!manager && (storeCode || assigneeUserId)) {
      throw new ForbiddenException(
        'Tài khoản chỉ được xem danh sách khách hàng đang được phân công cho mình.',
      );
    }
    if (manager && storeCode) {
      await this.assertStoreAllowed(user, principal, storeCode);
    }

    const parts: Prisma.SalesReportFollowUpCaseWhereInput[] = [
      scopeWhere,
      {
        status: status === 'OPEN' ? 'OPEN' : { in: HIDDEN_STATUSES },
        sourceReport: {
          reportType: 'NOT_PURCHASED',
          OR: [
            { customerPhone: { not: '' } },
            { customerZaloContact: { not: '' } },
          ],
        },
      },
    ];
    if (storeCode) parts.push({ sourceReport: { storeCode } });
    if (assigneeUserId) parts.push({ assigneeUserId });
    if (search) {
      parts.push({
        sourceReport: {
          OR: [
            { customerName: { contains: search, mode: 'insensitive' } },
            { customerPhone: { contains: search, mode: 'insensitive' } },
            {
              customerZaloContact: {
                contains: search,
                mode: 'insensitive',
              },
            },
          ],
        },
      });
    }
    const where: Prisma.SalesReportFollowUpCaseWhereInput = { AND: parts };
    const orderBy: Prisma.SalesReportFollowUpCaseOrderByWithRelationInput[] = [
      {
        lastFollowUpAt: {
          sort: Prisma.SortOrder.asc,
          nulls: Prisma.NullsOrder.first,
        },
      },
      { priorityAt: Prisma.SortOrder.asc },
    ];
    const contactCandidates =
      await this.prisma.salesReportFollowUpCase.findMany({
        where,
        orderBy,
        select: {
          id: true,
          sourceReport: {
            select: {
              customerPhone: true,
              customerZaloContact: true,
            },
          },
        },
      });
    const validCaseIds = contactCandidates
      .filter((row) =>
        this.hasVisibleContact(
          row.sourceReport.customerPhone,
          row.sourceReport.customerZaloContact,
        ),
      )
      .map((row) => row.id);
    const total = validCaseIds.length;
    const pageCaseIds = validCaseIds.slice(page * limit, (page + 1) * limit);
    const rows = pageCaseIds.length
      ? await this.prisma.salesReportFollowUpCase.findMany({
          where: { AND: [where, { id: { in: pageCaseIds } }] },
          orderBy,
          include: CASE_INCLUDE,
        })
      : [];
    this.logger.log(
      `Follow-up case list succeeded: user=${this.safeUser(user)} manager=${manager} status=${status} count=${rows.length}/${total} excludedInvalidContact=${contactCandidates.length - total} page=${page} durationMs=${Date.now() - startedAt}`,
    );
    return {
      items: rows.map((row) => this.toCaseDto(row, user, principal, manager)),
      page,
      limit,
      total,
      hasMore: (page + 1) * limit < total,
      managedScope: manager,
    };
  }

  async detail(user: any, caseId: string) {
    const startedAt = Date.now();
    this.logger.log(
      `Follow-up case detail started: case=${this.text(caseId, 80) ?? 'invalid'} user=${this.safeUser(user)}`,
    );
    try {
      const principal = await this.principal(user);
      const manager = this.isManager(user, principal);
      const row = await this.requireCase(caseId);
      await this.assertCanView(user, principal, manager, row);
      let candidates: Awaited<ReturnType<typeof this.assignmentCandidates>> =
        [];
      if (manager) {
        try {
          candidates = await this.assignmentCandidates(
            row.sourceReport.storeCode,
          );
        } catch (error) {
          this.logger.warn(
            `Follow-up assignment candidates unavailable: case=${row.id} user=${this.safeUser(user)} store=${row.sourceReport.storeCode || 'none'} error=${this.safeError(error)}`,
          );
        }
      }
      const result = {
        ...this.toCaseDto(row, user, principal, manager),
        assignmentCandidates: candidates,
      };
      this.logger.log(
        `Follow-up case detail succeeded: case=${row.id} user=${this.safeUser(user)} historyCount=${row.entries?.length ?? 0} assignmentCandidateCount=${candidates.length} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `Follow-up case detail failed: case=${this.text(caseId, 80) ?? 'invalid'} user=${this.safeUser(user)} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async checkOrder(user: any, caseId: string, orderCode: string) {
    const principal = await this.principal(user);
    const manager = this.isManager(user, principal);
    const row = await this.requireCase(caseId);
    await this.assertCanWrite(user, principal, manager, row);
    this.assertOpen(row);
    return this.salesReports.checkOrder(user, orderCode, this.caseScope(row));
  }

  async createEntry(
    user: any,
    caseId: string,
    body: CreateSalesReportFollowUpEntryDto,
  ) {
    const startedAt = Date.now();
    const principal = await this.principal(user);
    const manager = this.isManager(user, principal);
    const row = await this.requireCase(caseId);
    await this.assertCanWrite(user, principal, manager, row);
    this.assertOpen(row);
    const now = new Date();
    const actor = this.actor(user, principal);

    if (body.outcome === 'PURCHASED') {
      if (!body.purchasedReport) {
        throw new BadRequestException(
          'Vui lòng nhập và kiểm tra đầy đủ thông tin đơn hàng.',
        );
      }
      const purchasedBody = {
        ...body.purchasedReport,
        reportType: 'PURCHASED',
        entrySource: 'COMEBACK',
        customerName:
          this.text(body.purchasedReport.customerName, 120) ??
          row.sourceReport.customerName ??
          undefined,
        customerPhone:
          this.text(body.purchasedReport.customerPhone, 30) ??
          row.sourceReport.customerPhone ??
          undefined,
        customerZaloContact:
          this.text(body.purchasedReport.customerZaloContact, 120) ??
          row.sourceReport.customerZaloContact ??
          undefined,
      };
      const report = await this.salesReports.create(user, purchasedBody, {
        comebackScope: this.caseScope(row),
        persist: async (data, include) =>
          this.prisma.$transaction(async (tx) => {
            const claimed = await tx.salesReportFollowUpCase.updateMany({
              where: {
                id: row.id,
                status: 'OPEN',
                followUpCount: row.followUpCount,
              },
              data: { updatedAt: now },
            });
            if (claimed.count !== 1) {
              throw new ConflictException(
                'Hồ sơ vừa được cập nhật ở thiết bị khác. Vui lòng tải lại.',
              );
            }
            const created = await tx.salesReport.create({ data, include });
            await tx.salesReportFollowUpEntry.create({
              data: {
                caseId: row.id,
                sequenceNumber: row.followUpCount + 1,
                outcome: 'PURCHASED',
                ...actor,
                purchasedReportId: created.id,
                contactedAt: now,
              },
            });
            await tx.salesReportFollowUpCase.update({
              where: { id: row.id },
              data: {
                status: 'PURCHASED',
                convertedReportId: created.id,
                closedAt: now,
                lastFollowUpAt: now,
                lastFollowUpByUserId: actor.actorUserId,
                lastFollowUpByEmail: actor.actorEmail,
                lastFollowUpByName: actor.actorName,
                followUpCount: { increment: 1 },
                priorityAt: now,
              },
            });
            return created;
          }),
      });
      await this.publish(row, user, 'follow_up_purchased');
      this.logger.log(
        `Follow-up purchase succeeded: case=${row.id} user=${this.safeUser(user)} store=${row.sourceReport.storeCode || 'none'} durationMs=${Date.now() - startedAt}`,
      );
      return { caseStatus: 'PURCHASED', report };
    }

    if (body.outcome === 'NOT_PURCHASED') {
      const reason = this.text(body.notPurchasedReason, 40);
      if (!reason || !NOT_PURCHASED_REASON_CODES.includes(reason as any)) {
        throw new BadRequestException(
          'Vui lòng chọn lý do khách chưa mua hàng.',
        );
      }
      if (reason === 'OTHER' && !this.text(body.notPurchasedOtherReason, 500)) {
        throw new BadRequestException('Vui lòng nhập lý do khác.');
      }
    }
    const nextStatus = body.outcome === 'NOT_PURCHASED' ? 'OPEN' : body.outcome;
    await this.prisma.$transaction(async (tx) => {
      const claimed = await tx.salesReportFollowUpCase.updateMany({
        where: {
          id: row.id,
          status: 'OPEN',
          followUpCount: row.followUpCount,
        },
        data: { updatedAt: now },
      });
      if (claimed.count !== 1) {
        throw new ConflictException(
          'Hồ sơ vừa được cập nhật ở thiết bị khác. Vui lòng tải lại.',
        );
      }
      await tx.salesReportFollowUpEntry.create({
        data: {
          caseId: row.id,
          sequenceNumber: row.followUpCount + 1,
          outcome: body.outcome,
          notPurchasedReason:
            body.outcome === 'NOT_PURCHASED'
              ? this.text(body.notPurchasedReason, 40)
              : null,
          notPurchasedOtherReason:
            body.outcome === 'NOT_PURCHASED'
              ? this.text(body.notPurchasedOtherReason, 500)
              : null,
          ...actor,
          contactedAt: now,
        },
      });
      await tx.salesReportFollowUpCase.update({
        where: { id: row.id },
        data: {
          status: nextStatus,
          closedAt: nextStatus === 'OPEN' ? null : now,
          lastFollowUpAt: now,
          lastFollowUpByUserId: actor.actorUserId,
          lastFollowUpByEmail: actor.actorEmail,
          lastFollowUpByName: actor.actorName,
          followUpCount: { increment: 1 },
          priorityAt: now,
          events:
            nextStatus === 'OPEN'
              ? undefined
              : {
                  create: {
                    eventType: 'STATUS_CHANGED',
                    ...actor,
                    fromStatus: 'OPEN',
                    toStatus: nextStatus,
                  },
                },
        },
      });
    });
    await this.publish(row, user, `follow_up_${body.outcome.toLowerCase()}`);
    this.logger.log(
      `Follow-up entry succeeded: case=${row.id} outcome=${body.outcome} user=${this.safeUser(user)} durationMs=${Date.now() - startedAt}`,
    );
    return this.detail(user, row.id);
  }

  async assign(
    user: any,
    caseId: string,
    body: AssignSalesReportFollowUpCaseDto,
  ) {
    const principal = await this.principal(user);
    const manager = this.isManager(user, principal);
    if (!manager) {
      throw new ForbiddenException(
        'Chỉ quản lý cửa hàng hoặc cấp quản lý cao hơn được phân công khách hàng.',
      );
    }
    const row = await this.requireCase(caseId);
    await this.assertCanView(user, principal, manager, row);
    this.assertOpen(row);
    const candidates = await this.assignmentCandidates(
      row.sourceReport.storeCode,
    );
    const target = candidates.find((item) => item.id === body.userId);
    if (!target) {
      throw new BadRequestException(
        'Chỉ được phân công cho nhân viên bán hàng đang hoạt động trong cùng showroom.',
      );
    }
    const actor = this.actor(user, principal);
    const now = new Date();
    await this.prisma.salesReportFollowUpCase.update({
      where: { id: row.id },
      data: {
        assigneeUserId: target.id,
        assigneeEmail: target.email,
        assigneeName: target.name,
        assigneePersonnelCode: target.personnelCode,
        assignedAt: now,
        events: {
          create: {
            eventType: 'REASSIGNED',
            ...actor,
            fromAssigneeUserId: row.assigneeUserId,
            toAssigneeUserId: target.id,
          },
        },
      },
    });
    await this.publish(row, user, 'follow_up_reassigned', [target.id]);
    this.logger.log(
      `Follow-up assignment succeeded: case=${row.id} store=${row.sourceReport.storeCode || 'none'} assignee=${target.id} actor=${this.safeUser(user)}`,
    );
    return this.detail(user, row.id);
  }

  async reopen(user: any, caseId: string) {
    const principal = await this.principal(user);
    const row = await this.requireCase(caseId);
    if (!this.isAssignee(user, principal, row)) {
      throw new ForbiddenException(
        'Chỉ nhân viên đang được phân công mới được mở lại hồ sơ này.',
      );
    }
    if (!HIDDEN_STATUSES.includes(row.status)) {
      throw new BadRequestException(
        'Chỉ hồ sơ đã mua nơi khác hoặc hết nhu cầu mới được mở lại.',
      );
    }
    const actor = this.actor(user, principal);
    await this.prisma.salesReportFollowUpCase.update({
      where: { id: row.id },
      data: {
        status: 'OPEN',
        closedAt: null,
        events: {
          create: {
            eventType: 'REOPENED',
            ...actor,
            fromStatus: row.status,
            toStatus: 'OPEN',
          },
        },
      },
    });
    await this.publish(row, user, 'follow_up_reopened');
    this.logger.log(
      `Follow-up case reopened: case=${row.id} user=${this.safeUser(user)}`,
    );
    return this.detail(user, row.id);
  }

  private async requireCase(caseId: string) {
    const id = this.text(caseId, 80);
    const row = id
      ? await this.prisma.salesReportFollowUpCase.findUnique({
          where: { id },
          include: CASE_INCLUDE,
        })
      : null;
    if (!row) throw new NotFoundException('Không tìm thấy hồ sơ khách hàng.');
    return row;
  }

  private async principal(user: any) {
    if (!user?.id) return user ?? {};
    return (
      (await this.prisma.user.findUnique({
        where: { id: user.id },
        include: {
          store: true,
          jobRole: true,
          organizationAssignments: {
            where: { isActive: true },
            include: {
              organizationNode: {
                include: organizationNodeStoreTreeInclude(),
              },
            },
          },
        },
      })) ?? user
    );
  }

  private isManager(user: any, principal: any) {
    if (isSuperAdminRole(user?.role ?? principal?.role)) return true;
    const codes = [principal?.jobRoleCode, principal?.jobRole?.code]
      .map((value) =>
        String(value || '')
          .trim()
          .toUpperCase(),
      )
      .filter(Boolean);
    return codes.some(
      (code) =>
        MANAGER_ROLE_CODES.has(code) ||
        [...MANAGER_ROLE_CODES].some((role) => code.endsWith(`_${role}`)),
    );
  }

  private async scopeWhere(
    user: any,
    principal: any,
    manager: boolean,
  ): Promise<Prisma.SalesReportFollowUpCaseWhereInput> {
    if (manager) {
      if (isSuperAdminRole(user?.role ?? principal?.role)) return {};
      const stores = this.principalStoreCodes(principal);
      if (stores.length === 0) {
        throw new ForbiddenException('Tài khoản chưa được gán showroom.');
      }
      return { sourceReport: { storeCode: { in: stores } } };
    }
    const parts: Prisma.SalesReportFollowUpCaseWhereInput[] = [];
    if (principal?.id || user?.id) {
      parts.push({ assigneeUserId: principal?.id ?? user.id });
    }
    const email = this.email(principal?.email ?? user?.email);
    if (email) {
      parts.push({ assigneeEmail: { equals: email, mode: 'insensitive' } });
    }
    if (parts.length === 0) {
      throw new ForbiddenException('Tài khoản chưa có thông tin nhân viên.');
    }
    return { OR: parts };
  }

  private async assertCanView(
    user: any,
    principal: any,
    manager: boolean,
    row: any,
  ) {
    if (manager) {
      await this.assertStoreAllowed(
        user,
        principal,
        row.sourceReport.storeCode,
      );
      return;
    }
    if (!this.isAssignee(user, principal, row)) {
      throw new ForbiddenException(
        'Hồ sơ này không nằm trong phạm vi được phân công cho bạn.',
      );
    }
  }

  private async assertCanWrite(
    user: any,
    principal: any,
    manager: boolean,
    row: any,
  ) {
    await this.assertCanView(user, principal, manager, row);
    if (!manager && !this.isAssignee(user, principal, row)) {
      throw new ForbiddenException('Bạn chưa được phân công hồ sơ này.');
    }
  }

  private async assertStoreAllowed(user: any, principal: any, value: unknown) {
    if (isSuperAdminRole(user?.role ?? principal?.role)) return;
    const storeCode = this.storeCode(value);
    if (
      !storeCode ||
      !this.principalStoreCodes(principal).includes(storeCode)
    ) {
      throw new ForbiddenException(
        'Hồ sơ không thuộc showroom hoặc node bạn được phân công.',
      );
    }
  }

  private principalStoreCodes(principal: any) {
    const values = new Set<string>();
    const push = (store: any) => {
      const code = this.storeCode(store?.storeId);
      if (code) values.add(code);
    };
    push(principal?.store);
    for (const assignment of principal?.organizationAssignments ?? []) {
      for (const store of storesForOrganizationNodeTree(
        assignment?.organizationNode,
      )) {
        push(store);
      }
    }
    return [...values];
  }

  private async assignmentCandidates(storeCodeValue: unknown) {
    const storeCode = this.storeCode(storeCodeValue);
    if (!storeCode) return [];
    const users = await this.prisma.user.findMany({
      where: { status: 'yes' },
      include: {
        store: true,
        jobRole: true,
        organizationAssignments: {
          where: { isActive: true },
          include: {
            organizationNode: {
              include: organizationNodeStoreTreeInclude(),
            },
          },
        },
      },
      orderBy: [{ firstName: 'asc' }, { email: 'asc' }],
    });
    return users
      .filter((candidate: any) => {
        const role = String(
          candidate.jobRoleCode ?? candidate.jobRole?.code ?? '',
        ).toUpperCase();
        if (role !== 'SA' && !role.endsWith('_SA')) return false;
        return this.principalStoreCodes(candidate).includes(storeCode);
      })
      .map((candidate: any) => ({
        id: candidate.id,
        email: candidate.email,
        name:
          [candidate.firstName, candidate.lastName]
            .filter(Boolean)
            .join(' ')
            .trim() || candidate.email,
        personnelCode: this.text(candidate.personnelCode, 120),
      }));
  }

  private isAssignee(user: any, principal: any, row: any) {
    const userId = principal?.id ?? user?.id;
    const email = this.email(principal?.email ?? user?.email);
    return (
      (userId && row.assigneeUserId === userId) ||
      (email && this.email(row.assigneeEmail) === email)
    );
  }

  private caseScope(row: any) {
    return {
      storeCode: row.sourceReport.storeCode,
      storeName: row.sourceReport.storeName,
      organizationNodeId: row.sourceReport.organizationNodeId,
      organizationNodeName: row.sourceReport.organizationNodeName,
      regionCode: row.sourceReport.regionCode,
      areaCode: row.sourceReport.areaCode,
    };
  }

  private actor(user: any, principal: any) {
    return {
      actorUserId: principal?.id ?? user?.id ?? null,
      actorEmail: this.email(principal?.email ?? user?.email),
      actorName:
        [principal?.firstName, principal?.lastName]
          .filter(Boolean)
          .join(' ')
          .trim() || null,
    };
  }

  private toCaseDto(row: any, user: any, principal: any, manager: boolean) {
    const report = row.sourceReport;
    const categories = (report.categorySelections ?? []).length
      ? report.categorySelections.map((item: any) => ({
          id: item.categoryGroupId,
          name: item.categoryGroupNameVi,
        }))
      : [{ id: report.categoryGroupId, name: report.categoryGroupNameVi }];
    const referenceAt = row.lastFollowUpAt ?? report.submittedAt;
    return {
      id: row.id,
      status: row.status,
      customerName: report.customerName,
      customerPhone: report.customerPhone,
      customerZaloContact: report.customerZaloContact,
      categories,
      storeCode: report.storeCode,
      storeName: report.storeName,
      firstContactAt: report.submittedAt,
      firstContactByName: report.createdByName,
      firstContactByEmail: report.createdByEmail,
      firstNotPurchasedReason: report.notPurchasedReason,
      firstNotPurchasedReasonLabel: this.notPurchasedLabel(
        report.notPurchasedReason,
      ),
      firstNotPurchasedOtherReason: report.notPurchasedOtherReason,
      assigneeUserId: row.assigneeUserId,
      assigneeEmail: row.assigneeEmail,
      assigneeName: row.assigneeName,
      lastFollowUpAt: row.lastFollowUpAt,
      lastFollowUpByName: row.lastFollowUpByName,
      followUpCount: row.followUpCount,
      nextSequenceNumber: row.followUpCount + 1,
      careAgeDays: this.careAgeDays(referenceAt),
      canWrite: manager || this.isAssignee(user, principal, row),
      canReassign: manager && row.status === 'OPEN',
      canReopen:
        this.isAssignee(user, principal, row) &&
        HIDDEN_STATUSES.includes(row.status),
      entries: (row.entries ?? []).map((entry: any) => ({
        id: entry.id,
        sequenceNumber: entry.sequenceNumber,
        outcome: entry.outcome,
        outcomeLabel: this.outcomeLabel(entry.outcome),
        notPurchasedReason: entry.notPurchasedReason,
        notPurchasedReasonLabel: this.notPurchasedLabel(
          entry.notPurchasedReason,
        ),
        notPurchasedOtherReason: entry.notPurchasedOtherReason,
        actorName: entry.actorName,
        actorEmail: entry.actorEmail,
        contactedAt: entry.contactedAt,
      })),
    };
  }

  private careAgeDays(value: Date | string) {
    const offset = 7 * 60 * 60 * 1000;
    const day = 24 * 60 * 60 * 1000;
    const start = Math.floor((new Date(value).getTime() + offset) / day);
    const today = Math.floor((Date.now() + offset) / day);
    return Math.max(0, today - start);
  }

  private assertOpen(row: any) {
    if (row.status !== 'OPEN') {
      throw new ConflictException(
        'Hồ sơ đã được đóng hoặc cập nhật. Vui lòng tải lại danh sách.',
      );
    }
  }

  private async publish(
    row: any,
    user: any,
    source: string,
    additionalRecipientUserIds: unknown[] = [],
  ) {
    const storeCodes = row.sourceReport.storeCode
      ? [row.sourceReport.storeCode]
      : [];
    const recipientUserIds = [
      row.assigneeUserId,
      user?.id,
      ...additionalRecipientUserIds,
    ];
    await this.redis.publishMessage(
      REALTIME_CHANNEL,
      buildRealtimeRedisEnvelope({
        type: 'SALES_REPORT_ORDERS_UPDATED',
        audience: {
          storeCodes,
          recipientUserIds,
          roles: ['SUPER_ADMIN'],
          featureCodes: [FEATURE_KEYS.SALES_REPORT],
        },
        payload: {
          source,
          dates: [],
          newOrderCount: 0,
          mappedOrderCount: 0,
          storeCodes,
          recipientUserIds: recipientUserIds.filter(Boolean),
          caseId: row.id,
        },
      }),
    );
  }

  private outcomeLabel(value: string) {
    return (
      {
        PURCHASED: 'Mua hàng',
        NOT_PURCHASED: 'Chưa mua',
        PURCHASED_ELSEWHERE: 'Đã mua nơi khác',
        NO_LONGER_INTERESTED: 'Hết nhu cầu',
      }[value] ?? value
    );
  }

  private notPurchasedLabel(value: unknown) {
    const code = String(value || '');
    return (
      {
        NOT_SOLD: 'Chưa kinh doanh',
        SERVICE: 'Dịch vụ',
        CUSTOMER_BROWSING: 'Khách hàng tham khảo',
        NO_DEMO_STOCK: 'Không có hàng trải nghiệm',
        NO_AVAILABLE_STOCK: 'Không có sẵn hàng',
        PRICE_HESITATION: 'Phân vân giá',
        COMPARE_COMPETITOR: 'So sánh đối thủ',
        SPEC_NOT_COMPATIBLE: 'Thông số kỹ thuật chưa tương thích',
        OTHER: 'Khác',
      }[code] ?? null
    );
  }

  private text(value: unknown, max: number) {
    const normalized = String(value ?? '').trim();
    return normalized ? normalized.slice(0, max) : null;
  }

  private email(value: unknown) {
    return this.text(value, 160)?.toLowerCase() ?? null;
  }

  private storeCode(value: unknown) {
    return this.text(value, 40)?.toUpperCase() ?? null;
  }

  private hasVisibleContact(phoneValue: unknown, zaloValue: unknown) {
    const phone = String(phoneValue ?? '').trim();
    const normalizedPhone = phone.toLowerCase();
    const zalo = String(zaloValue ?? '')
      .trim()
      .toLowerCase();
    const hasPhone = /^\d{10}$/.test(phone) || normalizedPhone === '0zalo';
    const hasZalo = Boolean(zalo) && !INVALID_CONTACT_VALUES.has(zalo);
    return hasPhone || hasZalo;
  }

  private safeError(error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return message.replace(/\s+/g, ' ').trim().slice(0, 240) || 'unknown';
  }

  private safeUser(user: any) {
    return this.text(user?.id, 80) ?? this.email(user?.email) ?? 'unknown';
  }
}
