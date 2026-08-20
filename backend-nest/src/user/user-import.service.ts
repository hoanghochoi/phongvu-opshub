import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AccessChangeService } from '../auth/access-change.service';
import { OpshubMailService } from '../auth/opshub-mail.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  AdminUserImportParseResult,
  AdminUserImportRow,
} from './user-import-parser.service';
import { PreparedAdminUserMutation } from './user-admin-mutation-preparation.service';
import { logFingerprint, safeLogError } from '../common/log-sanitizer';

type ImportOrganizationNode = {
  id: string;
  parentId: string | null;
  type: string;
  code: string;
  businessCode: string | null;
  displayName: string;
  isActive: boolean;
};

export type PreparedAdminUserImport = {
  rowNumber: number;
  email: string;
  action: 'created' | 'updated';
  userId?: string;
  role: string;
  organizationNodeIds: string[];
  organizationNodeId: string | null;
  organizationNodeName: string | null;
  createData?: Record<string, unknown>;
  updateData?: Record<string, unknown>;
};

type UserImportLogger = {
  log: (message: string) => void;
  error: (message: string, trace?: unknown) => void;
};

export type UserWelcomeEmailRuntime = {
  normalizeAccountEmail: (value: unknown) => string;
  userLogId: (user: any) => string;
  logger: UserImportLogger;
};

export class UserWelcomeEmailService {
  constructor(
    private readonly mailService: OpshubMailService | undefined,
    private readonly runtime: UserWelcomeEmailRuntime,
  ) {}

  async sendWelcomeEmailsForImport(
    admin: any,
    prepared: PreparedAdminUserImport[],
    savedByEmail: Map<string, any>,
  ) {
    const sentEmails = new Set<string>();
    const failedByEmail = new Map<string, string>();
    for (const item of prepared) {
      if (item.action !== 'created') continue;
      const user = savedByEmail.get(item.email);
      if (!user) {
        failedByEmail.set(item.email, 'Không tìm thấy người dùng sau import');
        continue;
      }
      const result = await this.sendWelcomeEmail(user, {
        source: 'admin-import',
        admin,
        rowNumber: item.rowNumber,
      });
      if (result.sent) {
        sentEmails.add(item.email);
      } else {
        failedByEmail.set(item.email, result.error || 'Không gửi được email');
      }
    }
    return {
      sentEmails,
      failedByEmail,
      sentRows: sentEmails.size,
      failedRows: failedByEmail.size,
    };
  }

  async sendWelcomeEmail(
    user: any,
    context: { source: string; admin: any; rowNumber?: number },
  ) {
    const email = this.runtime.normalizeAccountEmail(user?.email);
    if (!this.mailService) {
      const error = 'Chưa cấu hình dịch vụ gửi email PhongVu OpsHub.';
      this.runtime.logger.error(
        `Welcome email failed: source=${context.source} emailHash=${logFingerprint(email)} reason=missing_mail_service`,
      );
      return { sent: false, error };
    }
    const displayName = String(user?.firstName || user?.name || email)
      .trim()
      .replace(/\s+/g, ' ');
    try {
      await this.mailService.sendMail({
        to: email,
        subject: 'Chào mừng bạn đến với PhongVu OpsHub',
        text:
          `Chào ${displayName},\n\n` +
          'Tài khoản PhongVu OpsHub của bạn đã được tạo.\n' +
          'Để đặt mật khẩu lần đầu, vui lòng mở ứng dụng và dùng chức năng Quên mật khẩu với email này theo hướng dẫn bên dưới:\n' +
          'Windows và Android tải tại: https://phongvu.work/download\n' +
          'iOS: Mở trang https://phongvu.work bằng trình duyệt Safari -> Share -> Add to Home Screen\n\n' +
          'Nếu bạn không yêu cầu tài khoản này, vui lòng liên hệ quản trị viên.',
      });
      this.runtime.logger.log(
        `Welcome email sent: source=${context.source} emailHash=${logFingerprint(email)} admin=${this.runtime.userLogId(context.admin)} row=${context.rowNumber ?? 'none'}`,
      );
      return { sent: true, error: null };
    } catch (error) {
      const message = this.errorMessageForImport(error);
      this.runtime.logger.error(
        `Welcome email failed: source=${context.source} emailHash=${logFingerprint(email)} admin=${this.runtime.userLogId(context.admin)} row=${context.rowNumber ?? 'none'} error=${safeLogError(message)}`,
      );
      return { sent: false, error: message };
    }
  }

  private errorMessageForImport(error: unknown) {
    if (error instanceof Error && error.message) return error.message;
    return 'dòng dữ liệu không hợp lệ';
  }
}

export type UserImportRuntime = {
  assertAdmin: (admin: any) => Promise<void>;
  assertSuperAdminCanCreateUsers: (admin: any) => Promise<void>;
  seedDefaultOrganizationTree: () => Promise<void>;
  syncStoreOrganizationNodes: (source: string) => Promise<void>;
  prepareAdminUserMutation: (
    admin: any,
    body: any,
    current: any | null,
  ) => Promise<PreparedAdminUserMutation>;
  assertAccountEmailAllowed: (email: unknown) => Promise<string>;
  assertAdminCanUpdateUser: (
    admin: any,
    userId: string,
    current: any,
  ) => Promise<void>;
  assertOrganizationNodeAssignableByAdmin: (
    admin: any,
    nodeId: string,
  ) => Promise<void>;
  organizationNodeLevel: (type: string) => number;
  normalizeStoreCode: (value: string) => string;
  syncUserOrganizationAssignments: (
    client: Prisma.TransactionClient,
    userId: string,
    organizationNodeIds: string[],
    admin: any,
  ) => Promise<void>;
  userDtoInclude: () => Prisma.UserInclude;
  personnelCodeFor: (user: any) => string | null | undefined;
  userLogId: (user: any) => string;
  logger: UserImportLogger;
};

/**
 * Owns admin import preparation/orchestration while UserService remains the
 * stable public facade. All policy and shared data helpers are explicit
 * callbacks so the collaborator cannot reach into UserService state.
 */
export class UserImportService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly accessChangeService: AccessChangeService,
    private readonly welcomeEmailService: UserWelcomeEmailService,
    private readonly runtime: UserImportRuntime,
  ) {}

  async adminImportUsers(admin: any, parsed: AdminUserImportParseResult) {
    await this.runtime.assertAdmin(admin);
    await this.runtime.assertSuperAdminCanCreateUsers(admin);
    const startedAt = Date.now();
    this.runtime.logger.log(
      'Admin user import started: admin=' +
        this.runtime.userLogId(admin) +
        ' role=' +
        admin.role +
        ' rows=' +
        parsed.rows.length +
        ' skipped=' +
        parsed.skippedRows,
    );

    try {
      await this.runtime.seedDefaultOrganizationTree();
      await this.runtime.syncStoreOrganizationNodes('admin-user-import');
      const prepared = await this.prepareAdminUserImport(admin, parsed.rows);

      await this.prisma.$transaction(async (tx) => {
        for (const item of prepared) {
          let userId = item.userId;
          if (item.action === 'created') {
            const created = await tx.user.create({
              data: item.createData as any,
            });
            userId = created.id;
          } else if (item.userId) {
            await tx.user.update({
              where: { id: item.userId },
              data: item.updateData as any,
            });
          }
          if (!userId) continue;
          await this.runtime.syncUserOrganizationAssignments(
            tx,
            userId,
            item.organizationNodeIds,
            admin,
          );
        }
      });

      const emails = prepared.map((item) => item.email);
      const savedUsers = await this.prisma.user.findMany({
        where: { email: { in: emails } },
        include: this.runtime.userDtoInclude(),
      });
      const savedByEmail = new Map(
        savedUsers.map((user) => [String(user.email).toLowerCase(), user]),
      );
      await this.accessChangeService.publishForUserIds(
        prepared
          .filter((item) => item.action === 'updated')
          .map((item) => savedByEmail.get(item.email)?.id),
        'user-access-import-updated',
      );
      const welcomeEmailSummary =
        await this.welcomeEmailService.sendWelcomeEmailsForImport(
          admin,
          prepared,
          savedByEmail,
        );
      const results = prepared.map((item) => {
        const saved = savedByEmail.get(item.email);
        return {
          rowNumber: item.rowNumber,
          email: item.email,
          action: item.action,
          welcomeEmailSent:
            item.action === 'created' &&
            welcomeEmailSummary.sentEmails.has(item.email),
          welcomeEmailError:
            item.action === 'created'
              ? (welcomeEmailSummary.failedByEmail.get(item.email) ?? null)
              : null,
          role: saved?.role ?? item.role,
          organizationNodeId:
            saved?.organizationNodeId ?? item.organizationNodeId,
          organizationNodeName:
            saved?.organizationNode?.displayName ?? item.organizationNodeName,
          personnelCode: saved ? this.runtime.personnelCodeFor(saved) : null,
        };
      });
      const createdRows = results.filter(
        (item) => item.action === 'created',
      ).length;
      const updatedRows = results.filter(
        (item) => item.action === 'updated',
      ).length;

      this.runtime.logger.log(
        'Admin user import completed: admin=' +
          this.runtime.userLogId(admin) +
          ' created=' +
          createdRows +
          ' updated=' +
          updatedRows +
          ' skipped=' +
          parsed.skippedRows +
          ' welcomeSent=' +
          welcomeEmailSummary.sentRows +
          ' welcomeFailed=' +
          welcomeEmailSummary.failedRows +
          ' durationMs=' +
          (Date.now() - startedAt),
      );
      return {
        totalRows: parsed.totalRows,
        createdRows,
        updatedRows,
        skippedRows: parsed.skippedRows,
        welcomeEmailSentRows: welcomeEmailSummary.sentRows,
        welcomeEmailFailedRows: welcomeEmailSummary.failedRows,
        results,
      };
    } catch (error) {
      this.runtime.logger.error(
        'Admin user import failed: admin=' +
          this.runtime.userLogId(admin) +
          ' rows=' +
          parsed.rows.length +
          ' durationMs=' +
          (Date.now() - startedAt),
        safeLogError(error),
      );
      throw error;
    }
  }

  private async prepareAdminUserImport(
    admin: any,
    rows: AdminUserImportRow[],
  ): Promise<PreparedAdminUserImport[]> {
    const emails = rows.map((row) => row.email);
    const existingUsers = await this.prisma.user.findMany({
      where: { email: { in: emails } },
      include: this.runtime.userDtoInclude(),
    });
    const existingByEmail = new Map(
      existingUsers.map((user) => [String(user.email).toLowerCase(), user]),
    );
    const organizationNodes = await this.listActiveOrganizationNodesForImport();
    const prepared: PreparedAdminUserImport[] = [];
    const errors: string[] = [];

    for (const row of rows) {
      try {
        await this.runtime.assertAccountEmailAllowed(row.email);
        const nodes = await this.resolveImportOrganizationNodes(
          admin,
          row,
          organizationNodes,
        );
        const node = nodes[0];
        const current = existingByEmail.get(row.email) ?? null;
        if (current) {
          await this.runtime.assertAdminCanUpdateUser(
            admin,
            current.id,
            current,
          );
        }
        const body = {
          email: row.email,
          firstName: row.fullName,
          lastName: '',
          role: row.role,
          status: current ? undefined : 'yes',
          organizationNodeIds: nodes.map((item) => item.id),
        };
        const mutation = await this.runtime.prepareAdminUserMutation(
          admin,
          body,
          current,
        );
        prepared.push({
          rowNumber: row.rowNumber,
          email: row.email,
          action: current ? 'updated' : 'created',
          userId: current?.id,
          role: mutation.role,
          organizationNodeIds: mutation.organizationNodeIds,
          organizationNodeId: mutation.personnel.organizationNodeId ?? node.id,
          organizationNodeName: node.displayName,
          createData: current ? undefined : mutation.createData,
          updateData: current ? mutation.updateData : undefined,
        });
      } catch (error) {
        errors.push(`dòng ${row.rowNumber}: ${this.errorMessage(error)}`);
      }
    }

    if (errors.length > 0) {
      const preview = errors.slice(0, 8).join('; ');
      const suffix =
        errors.length > 8 ? `; và ${errors.length - 8} lỗi khác` : '';
      throw new BadRequestException(
        `File nhân sự chưa hợp lệ: ${preview}${suffix}`,
      );
    }
    return prepared;
  }

  private async listActiveOrganizationNodesForImport() {
    return this.prisma.organizationNode.findMany({
      where: { isActive: true },
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
        displayName: true,
        isActive: true,
      },
    });
  }

  private async resolveImportOrganizationNode(
    admin: any,
    row: AdminUserImportRow,
    nodes: ImportOrganizationNode[],
  ) {
    const byId = new Map(nodes.map((node) => [node.id, node]));
    let previous: ImportOrganizationNode | null = null;
    let target: ImportOrganizationNode | null = null;

    for (let level = 0; level < row.levelCodes.length; level += 1) {
      const value = row.levelCodes[level];
      if (!value) continue;
      const candidates = nodes.filter(
        (node) =>
          node.isActive &&
          this.runtime.organizationNodeLevel(node.type) === level &&
          this.importNodeMatches(node, value) &&
          (!previous ||
            this.organizationNodeIsDescendantOf(node, previous, byId)),
      );
      if (candidates.length === 0) {
        throw new BadRequestException(
          `không tìm thấy node lv${level} với mã ${value}`,
        );
      }
      if (candidates.length > 1) {
        throw new BadRequestException(
          `mã đơn vị Lv${level} bị trùng hoặc mơ hồ: ${value}`,
        );
      }
      previous = candidates[0];
      target = candidates[0];
    }

    if (!target) throw new BadRequestException('Thiếu đơn vị tổ chức');
    await this.runtime.assertOrganizationNodeAssignableByAdmin(
      admin,
      target.id,
    );
    return target;
  }

  private async resolveImportOrganizationNodes(
    admin: any,
    row: AdminUserImportRow,
    nodes: ImportOrganizationNode[],
  ) {
    if (!row.storeIds?.length) {
      return [await this.resolveImportOrganizationNode(admin, row, nodes)];
    }

    const storeCodes = row.storeIds.map((value) =>
      this.runtime.normalizeStoreCode(value),
    );
    const stores = await this.prisma.store.findMany({
      where: { storeId: { in: storeCodes } },
      include: { organizationNode: true },
    });
    const byCode = new Map(
      stores.map((store) => [String(store.storeId).toUpperCase(), store]),
    );
    const resolvedNodes: ImportOrganizationNode[] = [];
    for (const storeCode of storeCodes) {
      const store = byCode.get(storeCode);
      if (!store?.organizationNodeId || !store.organizationNode) {
        throw new BadRequestException(
          `không tìm thấy showroom ${storeCode} trên cây tổ chức`,
        );
      }
      await this.runtime.assertOrganizationNodeAssignableByAdmin(
        admin,
        store.organizationNodeId,
      );
      resolvedNodes.push({
        id: store.organizationNode.id,
        parentId: store.organizationNode.parentId,
        type: store.organizationNode.type,
        code: store.organizationNode.code,
        businessCode: store.organizationNode.businessCode,
        displayName: store.organizationNode.displayName,
        isActive: store.organizationNode.isActive,
      });
    }
    return resolvedNodes;
  }

  private organizationNodeIsDescendantOf(
    node: { id: string; parentId: string | null },
    ancestor: { id: string },
    byId: Map<string, { id: string; parentId: string | null }>,
  ) {
    let cursor: { id: string; parentId: string | null } | undefined = node;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      if (cursor.id === ancestor.id) return true;
      cursor = cursor.parentId ? byId.get(cursor.parentId) : undefined;
    }
    return false;
  }

  private importNodeMatches(
    node: { code: string; businessCode: string | null },
    value: string,
  ) {
    const keys = this.importLookupKeys(value);
    const nodeKeys = [
      ...this.importLookupKeys(node.code),
      ...this.importLookupKeys(node.businessCode),
    ];
    return nodeKeys.some((key) => keys.has(key));
  }

  private importLookupKeys(value: unknown) {
    const raw = String(value || '')
      .trim()
      .toUpperCase();
    const normalized = raw.replace(/[^A-Z0-9_]/g, '_');
    return new Set([raw, normalized].filter(Boolean));
  }

  private errorMessage(error: unknown) {
    if (error instanceof Error && error.message) return error.message;
    return 'dòng dữ liệu không hợp lệ';
  }
}
