import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { BigQuery } from '@google-cloud/bigquery';
import { PrismaService } from '../prisma/prisma.service';
import { Cron, CronExpression } from '@nestjs/schedule';
import { getDataSyncSource } from '../config/env';
import { UploadService } from '../upload/upload.service';
import { encryptSecret } from '../common/secret-cipher';
import { PasswordResetService } from '../auth/password-reset.service';

const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';
const ADMIN_ROLE = 'ADMIN';
const MANAGER_ROLE = 'MANAGER';
const STAFF_ROLE = 'STAFF';

const STORE_SCOPE = 'STORE';
const MULTI_STORE_SCOPE = 'MULTI_STORE';
const REGION_SCOPE = 'REGION';
const NATIONAL_SCOPE = 'NATIONAL';
const ONLINE_SCOPE = 'ONLINE';

const WORK_SCOPE_TYPES = new Set([
  STORE_SCOPE,
  MULTI_STORE_SCOPE,
  REGION_SCOPE,
  NATIONAL_SCOPE,
  ONLINE_SCOPE,
]);

const DEFAULT_ROLE_DEFINITIONS = [
  {
    code: SUPER_ADMIN_ROLE,
    displayName: 'Super Admin',
    description: 'Toàn quyền hệ thống',
  },
  {
    code: ADMIN_ROLE,
    displayName: 'Admin',
    description: 'Quản lý người dùng theo phạm vi',
  },
  {
    code: MANAGER_ROLE,
    displayName: 'Manager',
    description: 'Nhóm quyền quản lý vận hành',
  },
  {
    code: STAFF_ROLE,
    displayName: 'Staff',
    description: 'Quyền thao tác hằng ngày',
  },
];

const DEFAULT_DEPARTMENT_DEFINITIONS = [
  {
    code: 'MANAGEMENT',
    displayName: 'Management',
    description: 'Quản lý vận hành showroom và bộ phận',
  },
  {
    code: 'SALES',
    displayName: 'Sales',
    description: 'Tư vấn và bán hàng',
  },
  {
    code: 'CASHIER',
    displayName: 'Cashier',
    description: 'Thu ngân và thanh toán tại quầy',
  },
  {
    code: 'TECHNICAL',
    displayName: 'Technical',
    description: 'Kỹ thuật và hỗ trợ sản phẩm',
  },
  {
    code: 'WAREHOUSE',
    displayName: 'Warehouse',
    description: 'Kho và điều phối hàng hóa',
  },
  {
    code: 'BACK_OFFICE',
    displayName: 'Back Office',
    description: 'Khối văn phòng hỗ trợ vận hành',
  },
  {
    code: 'EXECUTIVE',
    displayName: 'Executive',
    description: 'Ban điều hành và lãnh đạo',
  },
];

const DEFAULT_JOB_ROLE_DEFINITIONS = [
  {
    code: 'MANAGER',
    displayName: 'Manager',
    description: 'Quản lý SR hoặc bộ phận',
    departmentCode: 'MANAGEMENT',
  },
  {
    code: 'SALE',
    displayName: 'Sales Staff',
    description: 'Nhân viên bán hàng tại SR',
    departmentCode: 'SALES',
  },
  {
    code: 'SALE_ONLINE',
    displayName: 'Online Sales',
    description: 'Nhân viên sale online',
    departmentCode: 'SALES',
  },
  {
    code: 'CASHIER',
    displayName: 'Cashier Staff',
    description: 'Nhân viên thu ngân',
    departmentCode: 'CASHIER',
  },
  {
    code: 'TECHNICIAN',
    displayName: 'Technician',
    description: 'Nhân viên kỹ thuật',
    departmentCode: 'TECHNICAL',
  },
  {
    code: 'WAREHOUSE',
    displayName: 'Warehouse Staff',
    description: 'Nhân viên kho',
    departmentCode: 'WAREHOUSE',
  },
  {
    code: 'AREA_MANAGER',
    displayName: 'Area Manager',
    description: 'Quản lý khu vực',
    departmentCode: 'MANAGEMENT',
  },
  {
    code: 'REGIONAL_MANAGER',
    displayName: 'Regional Manager',
    description: 'Quản lý vùng/miền',
    departmentCode: 'MANAGEMENT',
  },
  {
    code: 'BACK_OFFICE',
    displayName: 'Back Office Staff',
    description: 'Nhân sự back office',
    departmentCode: 'BACK_OFFICE',
  },
  {
    code: 'BOD',
    displayName: 'BOD',
    description: 'Thành viên ban điều hành',
    departmentCode: 'EXECUTIVE',
  },
  {
    code: 'CEO',
    displayName: 'CEO',
    description: 'Tổng giám đốc',
    departmentCode: 'EXECUTIVE',
  },
];

@Injectable()
export class UserService implements OnModuleInit {
  private readonly logger = new Logger(UserService.name);
  private bigquery?: BigQuery;

  constructor(
    private prisma: PrismaService,
    private uploadService: UploadService,
    private passwordResetService: PasswordResetService,
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
    await this.seedDefaultPersonnelCatalog();

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
            workScopeType: this.defaultWorkScopeForRole(role),
          },
          create: {
            email,
            password: '',
            firstName: firstName || email.split('@')[0],
            lastName: lastName || null,
            role,
            status,
            storeId: storeUuid,
            workScopeType: this.defaultWorkScopeForRole(role),
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
    const personnel = await this.resolvePersonnelAssignment(body, {
      role,
      storeUuid,
    });

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
        ...personnel,
        branchLockedAt: storeUuid ? new Date() : null,
        profileCompletedAt: storeUuid ? new Date() : null,
      },
      include: { store: true },
    });
    this.logger.log(
      `Admin user created: email=${email} role=${role} scope=${personnel.workScopeType} personnelCode=${this.personnelCodeFor(user) ?? 'none'}`,
    );
    return this.toUserDto(user);
  }

  async adminUpdateUser(admin: any, userId: string, body: any) {
    this.assertAdmin(admin);
    const current = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { store: true },
    });
    if (!current) throw new NotFoundException('Không tìm thấy user');

    if (this.isScopedAdmin(admin) && current.storeId !== admin.storeId) {
      throw new ForbiddenException('Không có quyền sửa user ngoài chi nhánh');
    }

    const role = body.role
      ? await this.resolveAssignableRole(body.role)
      : current.role;
    this.assertRoleEditable(admin, role, current.role);
    const storeUuid =
      body.storeId !== undefined
        ? await this.resolveStoreForAdmin(admin, body.storeId)
        : current.storeId;
    const personnel = await this.resolvePersonnelAssignment(body, {
      current,
      role,
      storeUuid,
    });

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
        ...personnel,
        branchLockedAt: storeUuid
          ? (current.branchLockedAt ?? new Date())
          : null,
        profileCompletedAt: storeUuid
          ? (current.profileCompletedAt ?? new Date())
          : current.profileCompletedAt,
      },
      include: { store: true },
    });
    this.logger.log(
      `Admin user updated: id=${userId} role=${role} scope=${personnel.workScopeType} personnelCode=${this.personnelCodeFor(updated) ?? 'none'}`,
    );
    return this.toUserDto(updated);
  }

  async adminSendPasswordResetLink(admin: any, userId: string) {
    this.assertSuperAdmin(admin);
    const result = await this.passwordResetService.sendResetLinkForUserId(
      userId,
      { id: admin.id, email: admin.email },
    );
    this.logger.log(
      `Admin password reset link requested: admin=${admin.email || admin.id || 'unknown'} targetUserId=${userId}`,
    );
    return result;
  }
  private async resolveStoreForAdmin(admin: any, storeCode?: string) {
    const normalizedStoreCode = String(storeCode || '').trim();
    if (!normalizedStoreCode) return null;

    const store = await this.prisma.store.findUnique({
      where: { storeId: normalizedStoreCode },
    });
    if (!store) throw new BadRequestException('Chi nhánh không hợp lệ');
    if (this.isScopedAdmin(admin) && admin.storeId !== store.id) {
      throw new ForbiddenException('Chỉ được gán user vào chi nhánh của mình');
    }
    return store.id;
  }

  private assertAdmin(user: any) {
    if (
      user.role !== SUPER_ADMIN_ROLE &&
      user.role !== ADMIN_ROLE &&
      user.role !== MANAGER_ROLE
    ) {
      throw new ForbiddenException('Không có quyền quản trị user');
    }
  }

  private assertSuperAdmin(user: any) {
    if (user.role !== SUPER_ADMIN_ROLE) {
      throw new ForbiddenException('Chỉ SUPER_ADMIN được quản lý role');
    }
  }

  private assertRoleEditable(admin: any, role: string, currentRole?: string) {
    if (admin.role === SUPER_ADMIN_ROLE) {
      return;
    }
    if (!currentRole && role === STAFF_ROLE) {
      return;
    }
    if (currentRole && role === currentRole) {
      return;
    }
    throw new ForbiddenException('Chỉ SUPER_ADMIN được sửa role');
  }

  private adminScope(admin: any) {
    if (this.isScopedAdmin(admin)) {
      return admin.storeId
        ? { storeId: admin.storeId }
        : { id: '__NO_STORE__' };
    }
    return {};
  }

  private isScopedAdmin(user: any) {
    return user.role === ADMIN_ROLE || user.role === MANAGER_ROLE;
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
      departmentCode: user.departmentCode ?? null,
      jobRoleCode: user.jobRoleCode ?? null,
      workScopeType: this.effectiveWorkScope(user),
      personnelCode: this.personnelCodeFor(user),
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      mustSelectStore: this.mustSelectStore(user),
    };
  }

  private mustSelectStore(user: {
    role: string;
    workScopeType?: string | null;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    const hasStore = Boolean(user.storeId || user.store?.storeId);
    return this.effectiveWorkScope(user) === STORE_SCOPE && !hasStore;
  }

  async adminListRoles(admin: any) {
    this.assertAdmin(admin);
    await this.seedDefaultRoles();
    return this.prisma.roleDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
    });
  }

  async adminListDepartments(admin: any) {
    this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    return this.prisma.departmentDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
    });
  }

  async adminListJobRoles(admin: any) {
    this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    return this.prisma.jobRoleDefinition.findMany({
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
      throw new BadRequestException('Role đã tồn tại');
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
    if (!current) throw new NotFoundException('Không tìm thấy role');

    const nextCode = body.code
      ? this.normalizeRoleCode(body.code, true)
      : current.code;
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Không được đổi mã role hệ thống');
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
    if (!role) throw new NotFoundException('Không tìm thấy role');
    if (role.isSystem) {
      throw new BadRequestException('Không được xóa role hệ thống');
    }

    const assignedUsers = await this.prisma.user.count({
      where: { role: code },
    });
    if (assignedUsers > 0) {
      throw new BadRequestException('Role đang được gán cho người dùng');
    }

    await this.prisma.roleDefinition.delete({ where: { code } });
    return { deleted: true, code };
  }

  async adminListStores(admin: any, q?: string) {
    this.assertAdmin(admin);
    const query = q?.trim();
    const stores = await this.prisma.store.findMany({
      where: this.adminStoreScope(admin, query),
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
        ...this.normalizeMapVietinFields(body),
      },
      include: { _count: { select: { users: true } } },
    });
    return this.toStoreDto(store);
  }

  async adminUpdateStore(admin: any, currentStoreId: string, body: any) {
    const currentCode = this.normalizeStoreCode(currentStoreId);
    const current = await this.prisma.store.findUnique({
      where: { storeId: currentCode },
    });
    if (!current) throw new NotFoundException('Không tìm thấy store');

    if (this.isScopedAdmin(admin) && current.id !== admin.storeId) {
      throw new ForbiddenException('Không có quyền sửa showroom khác');
    } else if (!this.isScopedAdmin(admin)) {
      this.assertSuperAdmin(admin);
    }

    const nextCode = body.storeId
      ? this.normalizeStoreCode(body.storeId)
      : current.storeId;
    if (this.isScopedAdmin(admin) && nextCode !== current.storeId) {
      throw new ForbiddenException('Không có quyền đổi mã showroom');
    }
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
        ...this.normalizeMapVietinFields(body),
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

  private async seedDefaultPersonnelCatalog() {
    await Promise.all(
      DEFAULT_DEPARTMENT_DEFINITIONS.map((department) =>
        this.prisma.departmentDefinition.upsert({
          where: { code: department.code },
          update: {
            displayName: department.displayName,
            description: department.description,
            isSystem: true,
          },
          create: { ...department, isSystem: true },
        }),
      ),
    );

    await Promise.all(
      DEFAULT_JOB_ROLE_DEFINITIONS.map((jobRole) =>
        this.prisma.jobRoleDefinition.upsert({
          where: { code: jobRole.code },
          update: {
            displayName: jobRole.displayName,
            description: jobRole.description,
            departmentCode: jobRole.departmentCode,
            isSystem: true,
          },
          create: { ...jobRole, isSystem: true },
        }),
      ),
    );

    this.logger.log(
      `Personnel catalog seeded: departments=${DEFAULT_DEPARTMENT_DEFINITIONS.length}, jobRoles=${DEFAULT_JOB_ROLE_DEFINITIONS.length}`,
    );
  }

  private async resolvePersonnelAssignment(
    body: any,
    options: { current?: any; role: string; storeUuid?: string | null },
  ) {
    const departmentCode = await this.resolveDepartmentCode(
      body.departmentCode,
      options.current?.departmentCode ?? null,
    );
    const jobRoleCode = await this.resolveJobRoleCode(
      body.jobRoleCode,
      options.current?.jobRoleCode ?? null,
    );
    const workScopeType = this.resolveWorkScopeType(
      body.workScopeType,
      options.current?.workScopeType,
      options.role,
    );

    return { departmentCode, jobRoleCode, workScopeType };
  }

  private async resolveDepartmentCode(input: unknown, current?: string | null) {
    if (input === undefined) return current ?? null;
    const code = this.normalizePersonnelCode(
      input,
      'Mã phòng ban không hợp lệ',
    );
    if (!code) return null;
    const department = await this.prisma.departmentDefinition.findUnique({
      where: { code },
    });
    if (!department) {
      this.logger.warn(`Personnel validation failed: department=${code}`);
      throw new BadRequestException('Phòng ban không tồn tại');
    }
    return department.code;
  }

  private async resolveJobRoleCode(input: unknown, current?: string | null) {
    if (input === undefined) return current ?? null;
    const code = this.normalizePersonnelCode(
      input,
      'Mã chức danh không hợp lệ',
    );
    if (!code) return null;
    const jobRole = await this.prisma.jobRoleDefinition.findUnique({
      where: { code },
    });
    if (!jobRole) {
      this.logger.warn(`Personnel validation failed: jobRole=${code}`);
      throw new BadRequestException('Chức danh không tồn tại');
    }
    return jobRole.code;
  }

  private resolveWorkScopeType(
    input: unknown,
    current: string | null | undefined,
    role: string,
  ) {
    if (input === undefined) {
      return current || this.defaultWorkScopeForRole(role);
    }

    const scope = String(input || '')
      .trim()
      .toUpperCase();
    if (!scope) return this.defaultWorkScopeForRole(role);
    if (!WORK_SCOPE_TYPES.has(scope)) {
      this.logger.warn(`Personnel validation failed: workScopeType=${scope}`);
      throw new BadRequestException('Phạm vi làm việc không hợp lệ');
    }
    return scope;
  }

  private normalizePersonnelCode(input: unknown, message: string) {
    const code = String(input || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    if (!code) return null;
    if (!/^[A-Z][A-Z0-9_]{1,39}$/.test(code)) {
      throw new BadRequestException(message);
    }
    return code;
  }

  private defaultWorkScopeForRole(role: string) {
    if (role === SUPER_ADMIN_ROLE || role === ADMIN_ROLE) {
      return NATIONAL_SCOPE;
    }
    return STORE_SCOPE;
  }

  private effectiveWorkScope(user: {
    role: string;
    workScopeType?: string | null;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    const scope = String(user.workScopeType || '')
      .trim()
      .toUpperCase();
    if (WORK_SCOPE_TYPES.has(scope)) return scope;
    return this.defaultWorkScopeForRole(user.role);
  }

  private personnelCodeFor(user: {
    role: string;
    jobRoleCode?: string | null;
    workScopeType?: string | null;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    const jobRoleCode = String(user.jobRoleCode || '')
      .trim()
      .toUpperCase();
    if (!jobRoleCode) return null;
    const scope = this.effectiveWorkScope(user);
    if (scope === STORE_SCOPE) {
      const storeCode = user.store?.storeId || user.storeId;
      return storeCode ? `${jobRoleCode}_${storeCode}` : `${jobRoleCode}_STORE`;
    }
    if (scope === ONLINE_SCOPE) return jobRoleCode;
    return `${jobRoleCode}_${scope}`;
  }

  private normalizeRoleCode(roleStr: string, strict = false) {
    const code = String(roleStr || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');

    if (!/^[A-Z][A-Z0-9_]{1,39}$/.test(code)) {
      if (strict) {
        throw new BadRequestException(
          'Mã role phải bắt đầu bằng chữ, tối đa 40 ký tự',
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
      throw new BadRequestException('Role không tồn tại');
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

  private normalizeMapVietinFields(body: any) {
    const data: Record<string, string | null> = {};
    if (body.mapVietinUsername !== undefined) {
      data.mapVietinUsername = this.normalizeOptionalText(
        body.mapVietinUsername,
        120,
      ) as string | null;
    }
    if (body.mapVietinPassword !== undefined) {
      const password = String(body.mapVietinPassword || '').trim();
      if (password) {
        data.mapVietinPasswordCipher = encryptSecret(password);
      }
    }
    return data;
  }

  private adminStoreScope(
    admin: any,
    query?: string,
  ): Prisma.StoreWhereInput | undefined {
    const insensitive = Prisma.QueryMode.insensitive;
    const queryWhere = query
      ? {
          OR: [
            { storeId: { contains: query, mode: insensitive } },
            { storeName: { contains: query, mode: insensitive } },
            {
              transferAccountNumber: {
                contains: query,
                mode: insensitive,
              },
            },
            { transferAccountName: { contains: query, mode: insensitive } },
            { transferBankName: { contains: query, mode: insensitive } },
            { mapVietinUsername: { contains: query, mode: insensitive } },
          ],
        }
      : undefined;
    const scopeWhere = this.isScopedAdmin(admin)
      ? { id: admin.storeId || '__NO_STORE__' }
      : undefined;

    if (queryWhere && scopeWhere) return { AND: [scopeWhere, queryWhere] };
    return queryWhere || scopeWhere;
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
      mapVietinUsername: store.mapVietinUsername,
      hasMapVietinPassword: Boolean(store.mapVietinPasswordCipher),
      userCount: store._count?.users ?? 0,
    };
  }
}
