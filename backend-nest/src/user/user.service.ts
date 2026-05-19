import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { BigQuery } from '@google-cloud/bigquery';
import { PrismaService } from '../prisma/prisma.service';
import { Cron, CronExpression } from '@nestjs/schedule';
import { getDataSyncSource } from '../config/env';
import { UploadService } from '../upload/upload.service';

const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';
const ADMIN_ROLE = 'ADMIN';
const STAFF_ROLE = 'STAFF';

const DEFAULT_ROLE_DEFINITIONS = [
  {
    code: SUPER_ADMIN_ROLE,
    displayName: 'Super Admin',
    description: 'Toan quyen he thong',
  },
  {
    code: ADMIN_ROLE,
    displayName: 'Admin',
    description: 'Quan ly user theo pham vi',
  },
  {
    code: 'MANAGER',
    displayName: 'Manager',
    description: 'Nhom quyen quan ly van hanh',
  },
  {
    code: STAFF_ROLE,
    displayName: 'Staff',
    description: 'Quyen thao tac hang ngay',
  },
];

@Injectable()
export class UserService implements OnModuleInit {
  private readonly logger = new Logger(UserService.name);
  private bigquery?: BigQuery;

  constructor(
    private prisma: PrismaService,
    private uploadService: UploadService,
  ) {
    if (getDataSyncSource() !== 'bigquery') {
      return;
    }

    const projectId = process.env.BIGQUERY_PROJECT_ID;
    const keyFilename = process.env.BIGQUERY_KEY_FILE;

    this.bigquery = new BigQuery({
      projectId,
      ...(keyFilename ? { keyFilename } : {}),
    });
  }

  async onModuleInit() {
    await this.seedDefaultRoles();

    if (getDataSyncSource() !== 'bigquery') {
      this.logger.log('DATA_SYNC_SOURCE=local, skipping BigQuery user sync');
      return;
    }

    this.syncUsersFromBigQuery();
  }

  // -------------------------------------------------------
  // Sync every hour from BigQuery → Postgres
  // -------------------------------------------------------
  @Cron(CronExpression.EVERY_HOUR)
  async syncUsersFromBigQuery() {
    if (getDataSyncSource() !== 'bigquery') {
      this.logger.log('DATA_SYNC_SOURCE=local, skipping BigQuery user sync');
      return;
    }

    this.logger.log('Starting User sync from BigQuery...');
    try {
      const projectId = process.env.BIGQUERY_PROJECT_ID;
      const datasetId = process.env.BIGQUERY_USER_DATASET_ID;
      const tableId = process.env.BIGQUERY_USER_TABLE_ID;

      if (!projectId || !datasetId || !tableId) {
        this.logger.warn(
          'BIGQUERY_USER_DATASET_ID / BIGQUERY_USER_TABLE_ID not set, skipping user sync',
        );
        return;
      }

      const query = `SELECT * FROM \`${projectId}.${datasetId}.${tableId}\``;
      const [rows] = await this.bigquery!.query({ query });

      this.logger.log(`Fetched ${rows.length} user rows from BigQuery`);

      if (rows.length === 0) {
        this.logger.warn('No user rows found in BigQuery table');
        return;
      }

      let syncedCount = 0;
      let storeCreatedCount = 0;

      for (const row of rows) {
        const email = String(row.email || '')
          .trim()
          .toLowerCase();
        if (!email) continue;

        const firstName = String(row.first_name || '').trim();
        const lastName = String(row.last_name || '').trim();
        const role = this.normalizeRoleCode(
          String(row.role || 'STAFF')
            .trim()
            .toUpperCase(),
        );
        await this.ensureRoleExists(role);
        const branchId = String(row.branch_id || '').trim();
        const branchName = String(row.branch_name || '').trim();
        const status = String(row.status || 'yes')
          .trim()
          .toLowerCase();

        // Resolve Store: find or create by branchId
        let storeUuid: string | null = null;
        if (branchId) {
          let store = await this.prisma.store.findUnique({
            where: { storeId: branchId },
          });

          if (!store) {
            // Auto-create Store
            store = await this.prisma.store.create({
              data: {
                storeId: branchId,
                storeName: branchName || branchId,
              },
            });
            storeCreatedCount++;
            this.logger.log(`Created new Store: ${branchId} - ${branchName}`);
          } else if (branchName && store.storeName !== branchName) {
            // Update store name if changed
            await this.prisma.store.update({
              where: { storeId: branchId },
              data: { storeName: branchName },
            });
          }

          storeUuid = store.id;
        }

        // Upsert User
        await this.prisma.user.upsert({
          where: { email },
          update: {
            firstName: firstName || undefined,
            lastName: lastName || undefined,
            role,
            status,
            storeId: storeUuid,
          },
          create: {
            email,
            password: '',
            firstName: firstName || email.split('@')[0],
            lastName: lastName || null,
            role,
            status,
            storeId: storeUuid,
          },
        });

        syncedCount++;
      }

      this.logger.log(
        `User sync complete: ${syncedCount} users synced, ${storeCreatedCount} new stores created`,
      );
    } catch (error) {
      this.logger.error('User sync from BigQuery failed:', error);
    }
  }

  async listStores(q?: string) {
    const query = q?.trim();
    return this.prisma.store.findMany({
      where: query
        ? {
            OR: [
              { storeId: { contains: query, mode: 'insensitive' } },
              { storeName: { contains: query, mode: 'insensitive' } },
            ],
          }
        : undefined,
      orderBy: { storeId: 'asc' },
      select: {
        id: true,
        storeId: true,
        storeName: true,
        transferAccountNumber: true,
        transferAccountName: true,
        transferBankName: true,
        transferBankBin: true,
      },
    });
  }

  async getProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { store: true },
    });
    if (!user) throw new NotFoundException('Không tìm thấy user');
    return this.toUserDto(user);
  }

  async updateProfile(
    userId: string,
    body: { firstName?: string; lastName?: string },
  ) {
    const firstName = body.firstName?.trim();
    if (!firstName) {
      throw new BadRequestException('Tên không được để trống');
    }
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: {
        firstName,
        lastName: body.lastName?.trim() || null,
      },
      include: { store: true },
    });
    return this.toUserDto(user);
  }

  async updateAvatar(userId: string, file?: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('Vui lòng chọn ảnh đại diện');
    }
    const avatarUrl = await this.uploadService.saveUserAvatar(userId, file);
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: { avatarUrl },
      include: { store: true },
    });
    return this.toUserDto(user);
  }

  async selectStoreOnce(userId: string, storeCode: string) {
    const normalizedStoreCode = storeCode.trim();
    if (!normalizedStoreCode) {
      throw new BadRequestException('Vui lòng chọn chi nhánh');
    }

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { store: true },
    });
    if (!user) throw new NotFoundException('Không tìm thấy user');
    if (user.storeId || user.branchLockedAt) {
      throw new ForbiddenException('Chi nhánh đã được khóa và không thể đổi');
    }

    const store = await this.prisma.store.findUnique({
      where: { storeId: normalizedStoreCode },
    });
    if (!store) throw new BadRequestException('Chi nhánh không hợp lệ');

    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: {
        storeId: store.id,
        branchLockedAt: new Date(),
        profileCompletedAt: new Date(),
      },
      include: { store: true },
    });
    return this.toUserDto(updated);
  }

  async adminListUsers(admin: any, q?: string) {
    this.assertAdmin(admin);
    const query = q?.trim();
    return this.prisma.user
      .findMany({
        where: {
          ...this.adminScope(admin),
          ...(query
            ? {
                OR: [
                  { email: { contains: query, mode: 'insensitive' } },
                  { firstName: { contains: query, mode: 'insensitive' } },
                  { lastName: { contains: query, mode: 'insensitive' } },
                ],
              }
            : {}),
        },
        include: { store: true },
        orderBy: { createdAt: 'desc' },
        take: 200,
      })
      .then((users) => users.map((user) => this.toUserDto(user)));
  }

  async adminCreateUser(admin: any, body: any) {
    this.assertAdmin(admin);
    const email = String(body.email || '')
      .trim()
      .toLowerCase();
    if (!email) throw new BadRequestException('Email không được để trống');

    const role = await this.resolveAssignableRole(body.role || STAFF_ROLE);
    this.assertRoleEditable(admin, role);
    const storeUuid = await this.resolveStoreForAdmin(admin, body.storeId);

    const user = await this.prisma.user.create({
      data: {
        email,
        password: '',
        firstName: String(body.firstName || email.split('@')[0]).trim(),
        lastName: String(body.lastName || '').trim() || null,
        role,
        status:
          String(body.status || 'yes').toLowerCase() === 'no' ? 'no' : 'yes',
        storeId: storeUuid,
        branchLockedAt: storeUuid ? new Date() : null,
        profileCompletedAt: storeUuid ? new Date() : null,
      },
      include: { store: true },
    });
    return this.toUserDto(user);
  }

  async adminUpdateUser(admin: any, userId: string, body: any) {
    this.assertAdmin(admin);
    const current = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { store: true },
    });
    if (!current) throw new NotFoundException('Không tìm thấy user');

    if (admin.role === ADMIN_ROLE && current.storeId !== admin.storeId) {
      throw new ForbiddenException('Không có quyền sửa user ngoài chi nhánh');
    }

    const role = body.role
      ? await this.resolveAssignableRole(body.role)
      : current.role;
    this.assertRoleEditable(admin, role);
    const storeUuid =
      body.storeId !== undefined
        ? await this.resolveStoreForAdmin(admin, body.storeId)
        : current.storeId;

    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: {
        firstName: body.firstName?.trim() || current.firstName,
        lastName:
          body.lastName === undefined
            ? current.lastName
            : String(body.lastName || '').trim() || null,
        role,
        status:
          body.status === undefined
            ? current.status
            : String(body.status).toLowerCase() === 'no'
              ? 'no'
              : 'yes',
        storeId: storeUuid,
        branchLockedAt: storeUuid
          ? (current.branchLockedAt ?? new Date())
          : null,
        profileCompletedAt: storeUuid
          ? (current.profileCompletedAt ?? new Date())
          : current.profileCompletedAt,
      },
      include: { store: true },
    });
    return this.toUserDto(updated);
  }

  private async resolveStoreForAdmin(admin: any, storeCode?: string) {
    const normalizedStoreCode = String(storeCode || '').trim();
    if (!normalizedStoreCode) return null;

    const store = await this.prisma.store.findUnique({
      where: { storeId: normalizedStoreCode },
    });
    if (!store) throw new BadRequestException('Chi nhánh không hợp lệ');
    if (admin.role === ADMIN_ROLE && admin.storeId !== store.id) {
      throw new ForbiddenException(
        'Admin chỉ được gán user vào chi nhánh của mình',
      );
    }
    return store.id;
  }

  private assertAdmin(user: any) {
    if (user.role !== SUPER_ADMIN_ROLE && user.role !== ADMIN_ROLE) {
      throw new ForbiddenException('Không có quyền quản trị user');
    }
  }

  private assertSuperAdmin(user: any) {
    if (user.role !== SUPER_ADMIN_ROLE) {
      throw new ForbiddenException('Chi SUPER_ADMIN duoc quan ly role');
    }
  }

  private assertRoleEditable(admin: any, role: string) {
    if (admin.role === ADMIN_ROLE && role === SUPER_ADMIN_ROLE) {
      throw new ForbiddenException('Admin không được gán quyền SUPER_ADMIN');
    }
  }

  private adminScope(admin: any) {
    if (admin.role === ADMIN_ROLE) {
      return { storeId: admin.storeId };
    }
    return {};
  }

  private toUserDto(user: any) {
    return {
      id: user.id,
      email: user.email,
      name: user.firstName,
      firstName: user.firstName,
      lastName: user.lastName,
      avatarUrl: user.avatarUrl,
      storeId: user.store?.storeId ?? null,
      storeName: user.store?.storeName ?? null,
      role: user.role,
      status: user.status,
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      mustSelectStore: this.mustSelectStore(user),
    };
  }

  private mustSelectStore(user: {
    role: string;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    const hasStore = Boolean(user.storeId || user.store?.storeId);
    return (
      user.role !== SUPER_ADMIN_ROLE && user.role !== ADMIN_ROLE && !hasStore
    );
  }

  async adminListRoles(admin: any) {
    this.assertAdmin(admin);
    await this.seedDefaultRoles();
    return this.prisma.roleDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
    });
  }

  async adminCreateRole(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeRoleCode(body.code, true);
    const existing = await this.prisma.roleDefinition.findUnique({
      where: { code },
    });
    if (existing) {
      throw new BadRequestException('Role da ton tai');
    }
    return this.prisma.roleDefinition.create({
      data: {
        code,
        displayName: this.normalizeRoleDisplayName(body.displayName, code),
        description: this.normalizeRoleDescription(body.description),
        isSystem: false,
      },
    });
  }

  async adminUpdateRole(admin: any, currentCode: string, body: any) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeRoleCode(currentCode, true);
    const current = await this.prisma.roleDefinition.findUnique({
      where: { code },
    });
    if (!current) throw new NotFoundException('Khong tim thay role');

    const nextCode = body.code
      ? this.normalizeRoleCode(body.code, true)
      : current.code;
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Khong duoc doi ma role he thong');
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.roleDefinition.update({
        where: { code: current.code },
        data: {
          code: nextCode,
          displayName: this.normalizeRoleDisplayName(
            body.displayName ?? current.displayName,
            nextCode,
          ),
          description:
            body.description === undefined
              ? current.description
              : this.normalizeRoleDescription(body.description),
        },
      });

      if (nextCode !== current.code) {
        await tx.user.updateMany({
          where: { role: current.code },
          data: { role: nextCode },
        });
      }

      return updated;
    });
  }

  async adminDeleteRole(admin: any, codeInput: string) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeRoleCode(codeInput, true);
    const role = await this.prisma.roleDefinition.findUnique({
      where: { code },
    });
    if (!role) throw new NotFoundException('Khong tim thay role');
    if (role.isSystem) {
      throw new BadRequestException('Khong duoc xoa role he thong');
    }

    const assignedUsers = await this.prisma.user.count({
      where: { role: code },
    });
    if (assignedUsers > 0) {
      throw new BadRequestException('Role dang duoc gan cho user');
    }

    await this.prisma.roleDefinition.delete({ where: { code } });
    return { deleted: true, code };
  }

  async adminListStores(admin: any, q?: string) {
    this.assertAdmin(admin);
    const query = q?.trim();
    const stores = await this.prisma.store.findMany({
      where: query
        ? {
            OR: [
              { storeId: { contains: query, mode: 'insensitive' } },
              { storeName: { contains: query, mode: 'insensitive' } },
              {
                transferAccountNumber: {
                  contains: query,
                  mode: 'insensitive',
                },
              },
              { transferAccountName: { contains: query, mode: 'insensitive' } },
              { transferBankName: { contains: query, mode: 'insensitive' } },
            ],
          }
        : undefined,
      orderBy: { storeId: 'asc' },
      include: { _count: { select: { users: true } } },
    });
    return stores.map((store) => this.toStoreDto(store));
  }

  async adminCreateStore(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    const storeId = this.normalizeStoreCode(body.storeId);
    const storeName = this.normalizeRequiredText(
      body.storeName,
      'Tên store không được để trống',
      120,
    );

    const existing = await this.prisma.store.findUnique({
      where: { storeId },
    });
    if (existing) throw new BadRequestException('Store đã tồn tại');

    const store = await this.prisma.store.create({
      data: {
        storeId,
        storeName,
        ...this.normalizeStorePaymentFields(body),
      },
      include: { _count: { select: { users: true } } },
    });
    return this.toStoreDto(store);
  }

  async adminUpdateStore(admin: any, currentStoreId: string, body: any) {
    this.assertSuperAdmin(admin);
    const currentCode = this.normalizeStoreCode(currentStoreId);
    const current = await this.prisma.store.findUnique({
      where: { storeId: currentCode },
    });
    if (!current) throw new NotFoundException('Không tìm thấy store');

    const nextCode = body.storeId
      ? this.normalizeStoreCode(body.storeId)
      : current.storeId;
    if (nextCode !== current.storeId) {
      const existing = await this.prisma.store.findUnique({
        where: { storeId: nextCode },
      });
      if (existing) throw new BadRequestException('Store đã tồn tại');
    }

    const store = await this.prisma.store.update({
      where: { storeId: current.storeId },
      data: {
        storeId: nextCode,
        storeName:
          body.storeName === undefined
            ? current.storeName
            : this.normalizeRequiredText(
                body.storeName,
                'Tên store không được để trống',
                120,
              ),
        ...this.normalizeStorePaymentFields(body),
      },
      include: { _count: { select: { users: true } } },
    });
    return this.toStoreDto(store);
  }

  async adminDeleteStore(admin: any, storeIdInput: string) {
    this.assertSuperAdmin(admin);
    const storeId = this.normalizeStoreCode(storeIdInput);
    const store = await this.prisma.store.findUnique({
      where: { storeId },
      include: { _count: { select: { users: true } } },
    });
    if (!store) throw new NotFoundException('Không tìm thấy store');
    if (store._count.users > 0) {
      throw new BadRequestException('Store đang có user, không thể xóa');
    }

    await this.prisma.store.delete({ where: { storeId } });
    return { deleted: true, storeId };
  }

  private async seedDefaultRoles() {
    await Promise.all(
      DEFAULT_ROLE_DEFINITIONS.map((role) =>
        this.prisma.roleDefinition.upsert({
          where: { code: role.code },
          update: {
            displayName: role.displayName,
            description: role.description,
            isSystem: true,
          },
          create: { ...role, isSystem: true },
        }),
      ),
    );
  }

  private normalizeRoleCode(roleStr: string, strict = false) {
    const code = String(roleStr || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');

    if (!/^[A-Z][A-Z0-9_]{1,39}$/.test(code)) {
      if (strict) {
        throw new BadRequestException(
          'Ma role phai bat dau bang chu, toi da 40 ky tu',
        );
      }
      return STAFF_ROLE;
    }
    return code;
  }

  private normalizeRoleDisplayName(value: string, fallback: string) {
    const displayName = String(value || '').trim();
    if (!displayName) return fallback;
    return displayName.slice(0, 80);
  }

  private normalizeRoleDescription(value?: string | null) {
    const description = String(value || '').trim();
    return description ? description.slice(0, 180) : null;
  }

  private async ensureRoleExists(code: string) {
    await this.prisma.roleDefinition.upsert({
      where: { code },
      update: {},
      create: {
        code,
        displayName: code,
        description: null,
        isSystem: false,
      },
    });
  }

  private async resolveAssignableRole(roleInput: string) {
    const code = this.normalizeRoleCode(roleInput, true);
    const role = await this.prisma.roleDefinition.findUnique({
      where: { code },
    });
    if (!role) {
      throw new BadRequestException('Role khong ton tai');
    }
    return role.code;
  }

  private normalizeStoreCode(value: string) {
    const code = String(value || '')
      .trim()
      .toUpperCase();
    if (!/^[A-Z0-9][A-Z0-9_-]{1,39}$/.test(code)) {
      throw new BadRequestException('Mã store phải có 2-40 ký tự chữ hoặc số');
    }
    return code;
  }

  private normalizeRequiredText(
    value: string | undefined,
    message: string,
    maxLength: number,
  ) {
    const text = String(value || '').trim();
    if (!text) throw new BadRequestException(message);
    return text.slice(0, maxLength);
  }

  private normalizeOptionalText(value: string | undefined, maxLength: number) {
    if (value === undefined) return undefined;
    const text = String(value || '').trim();
    return text ? text.slice(0, maxLength) : null;
  }

  private normalizeStorePaymentFields(body: any) {
    return {
      transferAccountNumber: this.normalizeOptionalText(
        body.transferAccountNumber,
        80,
      ),
      transferAccountName: this.normalizeOptionalText(
        body.transferAccountName,
        120,
      ),
      transferBankName: this.normalizeOptionalText(body.transferBankName, 80),
      transferBankBin: this.normalizeOptionalText(body.transferBankBin, 20),
    };
  }

  private toStoreDto(store: any) {
    return {
      id: store.id,
      storeId: store.storeId,
      storeName: store.storeName,
      transferAccountNumber: store.transferAccountNumber,
      transferAccountName: store.transferAccountName,
      transferBankName: store.transferBankName,
      transferBankBin: store.transferBankBin,
      userCount: store._count?.users ?? 0,
    };
  }
}
