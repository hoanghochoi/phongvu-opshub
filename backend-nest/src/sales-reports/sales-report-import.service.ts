import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import { SalesReportCategoriesService } from './sales-report-categories.service';
import {
  SalesReportImportParsedRow,
  SalesReportImportParserService,
} from './sales-report-import-parser.service';

type ImportRowStatus = 'VALID' | 'PURCHASED' | 'DUPLICATE' | 'INVALID';

type ImportOwner = {
  id: string;
  email: string;
  name: string;
};

type ImportStore = {
  storeId: string;
  storeName: string;
  organizationNodeId?: string | null;
  organizationNode?: { displayName?: string | null } | null;
  areaCode?: string | null;
  area?: {
    code?: string | null;
    region?: { code?: string | null } | null;
  } | null;
};

type EnrichedImportRow = SalesReportImportParsedRow & {
  status: ImportRowStatus;
  category: {
    id: string;
    catGroupName: string;
    catGroupNameVi: string;
  } | null;
  store: ImportStore | null;
  owner: ImportOwner | null;
};

type ImportPreviewInternal = {
  fileName: string;
  fileHash: string;
  totalRows: number;
  validRows: number;
  purchasedRows: number;
  duplicateRows: number;
  invalidRows: number;
  unassignedRows: number;
  rows: EnrichedImportRow[];
};

@Injectable()
export class SalesReportImportService {
  private readonly logger = new Logger(SalesReportImportService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly parser: SalesReportImportParserService,
    private readonly categories: SalesReportCategoriesService,
  ) {}

  async preview(user: any, file: Express.Multer.File) {
    const startedAt = Date.now();
    this.logger.log(
      `Sales report import preview started: actor=${safeActor(user)} fileSize=${file?.size ?? file?.buffer?.length ?? 0}`,
    );
    try {
      const preview = await this.buildPreview(user, file);
      this.logger.log(
        `Sales report import preview succeeded: actor=${safeActor(user)} fileHash=${preview.fileHash.slice(0, 12)} totalRows=${preview.totalRows} validRows=${preview.validRows} invalidRows=${preview.invalidRows} duplicateRows=${preview.duplicateRows} purchasedRows=${preview.purchasedRows} unassignedRows=${preview.unassignedRows} durationMs=${Date.now() - startedAt}`,
      );
      return this.toResponse(preview);
    } catch (error) {
      this.logger.error(
        `Sales report import preview failed: actor=${safeActor(user)} durationMs=${Date.now() - startedAt} error=${String(error)}`,
      );
      throw error;
    }
  }

  async commit(user: any, file: Express.Multer.File, expectedFileHash: string) {
    const startedAt = Date.now();
    this.logger.log(
      `Sales report import commit started: actor=${safeActor(user)} fileSize=${file?.size ?? file?.buffer?.length ?? 0}`,
    );
    const normalizedExpectedHash = String(expectedFileHash || '')
      .trim()
      .toLowerCase();
    if (!/^[a-f0-9]{64}$/.test(normalizedExpectedHash)) {
      throw new BadRequestException(
        'Phiên xem trước không hợp lệ. Vui lòng xem trước file lại.',
      );
    }

    const preview = await this.buildPreview(user, file);
    if (preview.fileHash !== normalizedExpectedHash) {
      this.logger.warn(
        `Sales report import commit blocked by hash mismatch: actor=${safeActor(user)} expected=${normalizedExpectedHash.slice(0, 12)} actual=${preview.fileHash.slice(0, 12)}`,
      );
      throw new BadRequestException(
        'File đã thay đổi sau khi xem trước. Vui lòng xem trước lại trước khi nhập.',
      );
    }

    const actor = await this.resolveActor(user);
    const batch = await this.prisma.salesReportImportBatch.create({
      data: {
        fileName: preview.fileName,
        fileHash: preview.fileHash,
        status: 'PROCESSING',
        importedByUserId: actor.id,
        importedByEmail: actor.email,
        importedByName: actor.name,
        totalRows: preview.totalRows,
        validRows: preview.validRows,
        purchasedRows: preview.purchasedRows,
        duplicateRows: preview.duplicateRows,
        invalidRows: preview.invalidRows,
        unassignedRows: preview.unassignedRows,
      },
    });

    let importedRows = 0;
    let duplicateRows = preview.duplicateRows;
    let unassignedRows = 0;
    try {
      for (const row of preview.rows) {
        if (row.status !== 'VALID' || !row.category || !row.store) continue;
        try {
          await this.prisma.salesReport.create({
            data: this.createReportData(row, actor, batch.id),
          });
          importedRows += 1;
          if (!row.owner) unassignedRows += 1;
        } catch (error) {
          if (
            error instanceof Prisma.PrismaClientKnownRequestError &&
            error.code === 'P2002'
          ) {
            duplicateRows += 1;
            this.logger.warn(
              `Sales report import row skipped by concurrent duplicate: batchId=${batch.id} rowNumber=${row.rowNumber}`,
            );
            continue;
          }
          throw error;
        }
      }
      await this.prisma.salesReportImportBatch.update({
        where: { id: batch.id },
        data: {
          status: 'COMPLETED',
          importedRows,
          duplicateRows,
          unassignedRows,
          completedAt: new Date(),
        },
      });
      this.logger.log(
        `Sales report import commit succeeded: actor=${safeActor(user)} batchId=${batch.id} fileHash=${preview.fileHash.slice(0, 12)} importedRows=${importedRows} duplicateRows=${duplicateRows} invalidRows=${preview.invalidRows} purchasedRows=${preview.purchasedRows} unassignedRows=${unassignedRows} durationMs=${Date.now() - startedAt}`,
      );
      return {
        ...this.toResponse(preview),
        batchId: batch.id,
        importedRows,
        duplicateRows,
        unassignedRows,
      };
    } catch (error) {
      await this.prisma.salesReportImportBatch
        .update({
          where: { id: batch.id },
          data: {
            status: importedRows > 0 ? 'PARTIAL_FAILED' : 'FAILED',
            importedRows,
            duplicateRows,
            unassignedRows,
            completedAt: new Date(),
          },
        })
        .catch(() => undefined);
      this.logger.error(
        `Sales report import commit failed: actor=${safeActor(user)} batchId=${batch.id} importedRows=${importedRows} durationMs=${Date.now() - startedAt} error=${String(error)}`,
      );
      throw error;
    }
  }

  private async buildPreview(
    user: any,
    file: Express.Multer.File,
  ): Promise<ImportPreviewInternal> {
    const parsed = this.parser.parse(file);
    const [categories, stores, existingReports, owners] = await Promise.all([
      this.categories.listCategories(),
      this.resolveStoresInScope(user),
      this.prisma.salesReport.findMany({
        where: {
          importFingerprint: {
            in: parsed.rows.map((row) => row.fingerprint),
          },
        },
        select: { importFingerprint: true },
      }),
      this.resolveOwners(parsed.rows),
    ]);
    const categoryByKey = new Map<string, (typeof categories)[number]>();
    for (const category of categories) {
      for (const value of [
        category.id,
        category.catGroupName,
        category.catGroupNameVi,
      ]) {
        const key = normalizeKey(value);
        if (key && !categoryByKey.has(key)) categoryByKey.set(key, category);
      }
    }
    const storeByCode = new Map(
      stores.map((store) => [store.storeId.toUpperCase(), store] as const),
    );
    const existingFingerprints = new Set(
      existingReports
        .map((report) => report.importFingerprint)
        .filter((value): value is string => Boolean(value)),
    );
    const seenFingerprints = new Set<string>();

    const rows: EnrichedImportRow[] = parsed.rows.map((row) => {
      const errors = [...row.errors];
      const warnings = [...row.warnings];
      const category =
        categoryByKey.get(normalizeKey(row.categoryValue)) ?? null;
      const store = storeByCode.get(row.storeCode) ?? null;
      if (row.categoryValue && !category) {
        errors.push('Ngành hàng không khớp danh mục đang sử dụng.');
      }
      if (row.storeCode && !store) {
        errors.push('SR không tồn tại hoặc không thuộc phạm vi được gán.');
      }
      const ownerCandidate = row.salespersonEmail
        ? owners.get(row.salespersonEmail)
        : null;
      const owner =
        ownerCandidate && store && ownerCandidate.storeCodes.has(store.storeId)
          ? ownerCandidate.owner
          : null;
      if (!owner) {
        warnings.push(
          row.salespersonEmail
            ? 'Chưa khớp được nhân viên đang hoạt động tại SR; hồ sơ sẽ để chưa phân công.'
            : 'Thiếu email nhân viên; hồ sơ sẽ để chưa phân công.',
        );
      }

      let status: ImportRowStatus;
      if (row.purchased === true) {
        status = 'PURCHASED';
      } else if (errors.length > 0) {
        status = 'INVALID';
      } else if (
        existingFingerprints.has(row.fingerprint) ||
        seenFingerprints.has(row.fingerprint)
      ) {
        status = 'DUPLICATE';
      } else {
        status = 'VALID';
      }
      seenFingerprints.add(row.fingerprint);
      return { ...row, errors, warnings, category, store, owner, status };
    });

    return {
      fileName: parsed.fileName,
      fileHash: parsed.fileHash,
      totalRows: parsed.totalRows,
      validRows: rows.filter((row) => row.status === 'VALID').length,
      purchasedRows: rows.filter((row) => row.status === 'PURCHASED').length,
      duplicateRows: rows.filter((row) => row.status === 'DUPLICATE').length,
      invalidRows: rows.filter((row) => row.status === 'INVALID').length,
      unassignedRows: rows.filter((row) => row.status === 'VALID' && !row.owner)
        .length,
      rows,
    };
  }

  private toResponse(preview: ImportPreviewInternal) {
    return {
      fileName: preview.fileName,
      fileHash: preview.fileHash,
      totalRows: preview.totalRows,
      validRows: preview.validRows,
      purchasedRows: preview.purchasedRows,
      duplicateRows: preview.duplicateRows,
      invalidRows: preview.invalidRows,
      unassignedRows: preview.unassignedRows,
      rows: preview.rows.map((row) => ({
        rowNumber: row.rowNumber,
        status: row.status,
        customerName: row.customerName,
        customerPhone: row.customerPhone,
        salespersonEmail: row.salespersonEmail,
        sourceSalespersonCode: row.sourceSalespersonCode,
        storeCode: row.storeCode,
        errors: row.errors,
        warnings: row.warnings,
      })),
    };
  }

  private createReportData(
    row: EnrichedImportRow,
    actor: { id: string | null; email: string | null; name: string | null },
    batchId: string,
  ): Prisma.SalesReportCreateInput {
    const category = row.category!;
    const store = row.store!;
    const owner = row.owner;
    const submittedAt = row.submittedAt!;
    return {
      reportType: 'NOT_PURCHASED',
      customerName: row.customerName,
      customerPhone: row.customerPhone,
      customerContactChannels: row.customerContactChannels,
      customerNeed: row.customerNeed,
      categoryGroup: { connect: { id: category.id } },
      categoryGroupName: category.catGroupName,
      categoryGroupNameVi: category.catGroupNameVi,
      consultedSolutionAnswer: 'NOT_CAPTURED',
      experiencedAnswer: 'NOT_CAPTURED',
      zaloAnswer: 'NOT_CAPTURED',
      appDownloadAnswer: 'NOT_CAPTURED',
      notPurchasedReason: row.notPurchasedReason,
      notPurchasedOtherReason: row.notPurchasedOtherReason,
      createdBy: owner ? { connect: { id: owner.id } } : undefined,
      createdByEmail: row.salespersonEmail || null,
      createdByName: owner?.name ?? null,
      sourceSalespersonCode: row.sourceSalespersonCode || null,
      storeCode: store.storeId,
      storeName: store.storeName,
      organizationNodeId: store.organizationNodeId ?? null,
      organizationNodeName: store.organizationNode?.displayName ?? null,
      regionCode: store.area?.region?.code ?? null,
      areaCode: store.area?.code ?? store.areaCode ?? null,
      entrySource: 'HISTORICAL_IMPORT',
      importFingerprint: row.fingerprint,
      importBatch: { connect: { id: batchId } },
      submittedByUserId: actor.id,
      submittedByEmail: actor.email,
      submittedByName: actor.name,
      submittedAt,
      rawResponses: {
        reportType: 'NOT_PURCHASED',
        entrySource: 'HISTORICAL_IMPORT',
        historicalImport: {
          sourceSalespersonCode: row.sourceSalespersonCode || null,
          sourceSalespersonEmail: row.salespersonEmail || null,
          behaviorAnswers: 'NOT_CAPTURED',
        },
      } as Prisma.InputJsonValue,
      categorySelections: {
        create: {
          categoryGroupId: category.id,
          categoryGroupName: category.catGroupName,
          categoryGroupNameVi: category.catGroupNameVi,
          sortOrder: 0,
        },
      },
      sourceFollowUpCase: {
        create: {
          status: 'OPEN',
          assigneeUserId: owner?.id ?? null,
          assigneeEmail: owner?.email ?? null,
          assigneeName: owner?.name ?? null,
          assignedAt: owner ? submittedAt : null,
          priorityAt: submittedAt,
          events: {
            create: {
              eventType: 'CREATED',
              actorUserId: actor.id,
              actorEmail: actor.email,
              actorName: actor.name,
              toAssigneeUserId: owner?.id ?? null,
              toStatus: 'OPEN',
              createdAt: submittedAt,
            },
          },
        },
      },
    };
  }

  private async resolveStoresInScope(user: any): Promise<ImportStore[]> {
    if (isSuperAdminRole(user?.role)) {
      return this.prisma.store.findMany({
        orderBy: { storeId: Prisma.SortOrder.asc },
        include: {
          organizationNode: true,
          area: { include: { region: true } },
        },
      });
    }
    const saved = await this.loadUserWithScope(user);
    const storeCodes = storeCodesForUser(saved);
    if (storeCodes.size === 0) {
      throw new ForbiddenException('Tài khoản chưa được gán showroom.');
    }
    return this.prisma.store.findMany({
      where: { storeId: { in: Array.from(storeCodes) } },
      orderBy: { storeId: Prisma.SortOrder.asc },
      include: {
        organizationNode: true,
        area: { include: { region: true } },
      },
    });
  }

  private async resolveOwners(rows: SalesReportImportParsedRow[]) {
    const emails = Array.from(
      new Set(rows.map((row) => row.salespersonEmail).filter(Boolean)),
    );
    if (emails.length === 0)
      return new Map<string, { owner: ImportOwner; storeCodes: Set<string> }>();
    const users = await this.prisma.user.findMany({
      where: {
        email: { in: emails, mode: Prisma.QueryMode.insensitive },
        status: 'yes',
      },
      include: {
        store: true,
        organizationAssignments: {
          where: { isActive: true },
          include: {
            organizationNode: {
              include: organizationNodeStoreTreeInclude(),
            },
          },
        },
      },
    });
    return new Map(
      users.map((user) => [
        user.email.toLowerCase(),
        {
          owner: {
            id: user.id,
            email: user.email,
            name: [user.firstName, user.lastName]
              .filter(Boolean)
              .join(' ')
              .trim(),
          },
          storeCodes: storeCodesForUser(user),
        },
      ]),
    );
  }

  private async resolveActor(user: any) {
    const saved = await this.loadUserWithScope(user);
    return {
      id: saved?.id ?? user?.id ?? null,
      email: saved?.email ?? user?.email ?? null,
      name:
        [saved?.firstName, saved?.lastName].filter(Boolean).join(' ').trim() ||
        user?.name ||
        null,
    };
  }

  private async loadUserWithScope(user: any) {
    if (user?.__authContext?.scopeSnapshot) {
      return user.__authContext.scopeSnapshot;
    }
    if (!user?.id) return user ?? {};
    return this.prisma.user.findUnique({
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
  }
}

function storeCodesForUser(user: any) {
  const codes = new Set<string>();
  const push = (store: any) => {
    const code = String(store?.storeId || '')
      .trim()
      .toUpperCase();
    if (code) codes.add(code);
  };
  push(user?.store);
  for (const assignment of user?.organizationAssignments ?? []) {
    for (const store of storesForOrganizationNodeTree(
      assignment?.organizationNode,
    )) {
      push(store);
    }
  }
  return codes;
}

function normalizeKey(value: unknown) {
  return String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '');
}

function safeActor(user: any) {
  return String(user?.id || user?.email || 'unknown')
    .replace(/\s+/g, '')
    .slice(0, 80);
}
