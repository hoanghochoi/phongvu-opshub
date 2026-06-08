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
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import {
  BREAK_GLASS_SUPER_ADMIN_EMAIL,
  BREAK_GLASS_SUPER_ADMIN_PASSWORD_HASH,
  LEGACY_SUPER_ADMIN_EMAIL,
} from '../auth/break-glass-admin.constants';

const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';
const ADMIN_ROLE = 'ADMIN';
const ADMIN_ACARE_ROLE = 'ADMIN_ACARE';
const MANAGER_ROLE = 'MANAGER';
const STAFF_ROLE = 'STAFF';
const ACARETEK_EMAIL_DOMAIN = 'acaretek.vn';

const STORE_SCOPE = 'STORE';
const AREA_SCOPE = 'AREA';
const REGION_SCOPE = 'REGION';
const NATIONAL_SCOPE = 'NATIONAL';

const WORK_SCOPE_TYPES = new Set([
  STORE_SCOPE,
  AREA_SCOPE,
  REGION_SCOPE,
  NATIONAL_SCOPE,
]);

const DEFAULT_REGION_CODE = 'CHUA_GAN';
const CHATSALE_REGION_CODE = 'CHATSALE';
const TELESALE_REGION_CODE = 'TELESALE';
const ORG_ROOT_PHONGVU_ID = 'org-domain-phongvu-vn';
const ORG_ROOT_ACARETEK_ID = 'org-domain-acaretek-vn';
const ORG_SUBDOMAIN_PHONGVU_ID = 'org-subdomain-phongvu-vn';
const ORG_TYPES = new Set([
  'ROOT_DOMAIN',
  'SUBDOMAIN',
  'BLOCK',
  'DEPARTMENT',
  'AREA',
  'SHOWROOM',
  'JOB_ROLE',
  'VIRTUAL_SCOPE',
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
    code: ADMIN_ACARE_ROLE,
    displayName: 'Admin ACare',
    description: 'Quan ly user thuoc domain acaretek.vn',
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
    code: 'STORE_MANAGER',
    displayName: 'Store Manager',
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
    code: 'CHATSALE',
    displayName: 'Chatsale',
    description: 'Nhan su chatsale',
    departmentCode: 'SALES',
  },
  {
    code: 'TELESALE',
    displayName: 'Telesale',
    description: 'Nhan su telesale',
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

const DEFAULT_REGION_DEFINITIONS = [
  {
    code: DEFAULT_REGION_CODE,
    displayName: 'Chua gan',
    abbreviation: DEFAULT_REGION_CODE,
    description: 'Vung/Mien mac dinh cho du lieu cu chua phan loai',
    isSystem: true,
  },
  {
    code: CHATSALE_REGION_CODE,
    displayName: 'Chatsale',
    abbreviation: CHATSALE_REGION_CODE,
    description: 'Scope ao tuong duong cap Mien cho doi Chatsale',
    isSystem: true,
  },
  {
    code: TELESALE_REGION_CODE,
    displayName: 'Telesale',
    abbreviation: TELESALE_REGION_CODE,
    description: 'Scope ao tuong duong cap Mien cho doi Telesale',
    isSystem: true,
  },
];

const DEFAULT_AREA_DEFINITIONS = DEFAULT_REGION_DEFINITIONS.map((region) => ({
  code: region.code,
  displayName: region.displayName,
  abbreviation: region.abbreviation,
  description: region.description,
  regionCode: region.code,
  isSystem: true,
}));

@Injectable()
export class UserService implements OnModuleInit {
  private readonly logger = new Logger(UserService.name);
  private bigquery?: BigQuery;

  constructor(
    private prisma: PrismaService,
    private uploadService: UploadService,
    private passwordResetService: PasswordResetService,
    private policyService: PolicyService,
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
    await this.seedDefaultOrganizationTree();
    await this.bootstrapBreakGlassSuperAdmin();

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
                areaCode: DEFAULT_REGION_CODE,
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
            regionCode: storeUuid ? DEFAULT_REGION_CODE : null,
            areaCode: storeUuid ? DEFAULT_REGION_CODE : null,
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
            regionCode: storeUuid ? DEFAULT_REGION_CODE : null,
            areaCode: storeUuid ? DEFAULT_REGION_CODE : null,
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
    const stores = await this.prisma.store.findMany({
      where: query
        ? {
            OR: [
              { storeId: { contains: query, mode: 'insensitive' } },
              { storeName: { contains: query, mode: 'insensitive' } },
            ],
          }
        : undefined,
      orderBy: { storeId: 'asc' },
      include: { area: { include: { region: true } } },
    });
    return stores.map((store) => this.toStoreDto(store));
  }

  async getProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.userDtoInclude(),
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
      include: this.userDtoInclude(),
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
      include: this.userDtoInclude(),
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
      include: this.userDtoInclude(),
    });
    if (!user) throw new NotFoundException('Không tìm thấy user');
    if (user.storeId || user.branchLockedAt) {
      throw new ForbiddenException('Chi nhánh đã được khóa và không thể đổi');
    }

    const store = await this.prisma.store.findUnique({
      where: { storeId: normalizedStoreCode },
      include: { area: true },
    });
    if (!store) throw new BadRequestException('Chi nhánh không hợp lệ');

    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: {
        storeId: store.id,
        areaCode: store.areaCode ?? DEFAULT_REGION_CODE,
        regionCode: store.area?.regionCode ?? DEFAULT_REGION_CODE,
        branchLockedAt: new Date(),
        profileCompletedAt: new Date(),
      },
      include: this.userDtoInclude(),
    });
    return this.toUserDto(updated);
  }

  async adminListUsers(admin: any, filters: any = {}) {
    await this.assertAdmin(admin);
    const query = String(filters.q || '').trim();
    const scope = this.adminScope(admin);
    const where = await this.adminUserWhere(scope, filters, query);
    this.logger.log(
      'Admin user list started: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' domainScope=' +
        this.adminDomainScopeLabel(admin) +
        ' query=' +
        (query || 'none') +
        ' feature=' +
        (filters.featureCode || 'none') +
        ' orgNodeId=' +
        (filters.orgNodeId || 'none'),
    );
    try {
      const users = await this.prisma.user.findMany({
        where,
        include: this.userDtoInclude(),
        orderBy: { createdAt: 'desc' },
        take: 200,
      });
      this.logger.log(
        'Admin user list completed: admin=' +
          (admin.email || admin.id || 'unknown') +
          ' role=' +
          admin.role +
          ' count=' +
          users.length +
          ' domainScope=' +
          this.adminDomainScopeLabel(admin),
      );
      return users.map((user) => this.toUserDto(user));
    } catch (error) {
      this.logger.error(
        'Admin user list failed: admin=' +
          (admin.email || admin.id || 'unknown') +
          ' role=' +
          admin.role +
          ' domainScope=' +
          this.adminDomainScopeLabel(admin),
        error,
      );
      throw error;
    }
  }

  async adminCreateUser(admin: any, body: any) {
    await this.assertAdmin(admin);
    const email = String(body.email || '')
      .trim()
      .toLowerCase();
    if (!email) throw new BadRequestException('Email không được để trống');
    this.assertEmailWithinAdminDomain(admin, email);

    const role = await this.resolveAssignableRole(body.role || STAFF_ROLE);
    await this.assertRoleEditable(admin, role);
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
      include: this.userDtoInclude(),
    });
    await this.syncUserFeatureAssignments(admin, user.id, body.featureCodes);
    const saved = await this.prisma.user.findUnique({
      where: { id: user.id },
      include: this.userDtoInclude(),
    });
    this.logger.log(
      `Admin user created: email=${email} role=${role} scope=${personnel.workScopeType} personnelCode=${this.personnelCodeFor(user) ?? 'none'}`,
    );
    return this.toUserDto(saved ?? user);
  }

  async adminUpdateUser(admin: any, userId: string, body: any) {
    await this.assertAdmin(admin);
    const current = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.userDtoInclude(),
    });
    if (!current) throw new NotFoundException('Không tìm thấy user');

    if (
      this.isScopedAdmin(admin) &&
      !this.userWithinAdminScope(admin, current)
    ) {
      this.logger.warn(
        'Admin user update blocked by scope: admin=' +
          (admin.email || admin.id || 'unknown') +
          ' role=' +
          admin.role +
          ' targetUserId=' +
          userId +
          ' targetEmail=' +
          current.email,
      );
      throw new ForbiddenException(
        'Khong co quyen sua user ngoai pham vi quan ly',
      );
    }

    const role = body.role
      ? await this.resolveAssignableRole(body.role)
      : current.role;
    await this.assertRoleEditable(admin, role, current.role);
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
      include: this.userDtoInclude(),
    });
    await this.syncUserFeatureAssignments(admin, userId, body.featureCodes);
    const saved = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.userDtoInclude(),
    });
    this.logger.log(
      `Admin user updated: id=${userId} role=${role} scope=${personnel.workScopeType} personnelCode=${this.personnelCodeFor(updated) ?? 'none'}`,
    );
    return this.toUserDto(saved ?? updated);
  }

  private async syncUserFeatureAssignments(
    admin: any,
    userId: string,
    featureCodesInput: unknown,
  ) {
    if (featureCodesInput === undefined) return;
    await this.assertSuperAdmin(admin);
    const featureCodes = this.normalizeFeatureCodeList(featureCodesInput);
    if (featureCodes.length > 0) await this.ensureFeaturesExist(featureCodes);
    await this.prisma.$transaction(async (tx) => {
      await tx.userFeatureAssignment.deleteMany({ where: { userId } });
      if (featureCodes.length === 0) return;
      await tx.userFeatureAssignment.createMany({
        data: featureCodes.map((featureCode) => ({
          userId,
          featureCode,
          enabled: true,
          assignedById: admin?.id ?? null,
          note: 'Assigned from user editor',
        })),
        skipDuplicates: true,
      });
    });
    this.logger.log(
      `User feature assignments saved: admin=${admin?.email || admin?.id || 'unknown'} targetUserId=${userId} count=${featureCodes.length}`,
    );
  }

  private normalizeFeatureCodeList(value: unknown) {
    const values = Array.isArray(value) ? value : [];
    return Array.from(
      new Set(
        values
          .map((item) => this.normalizeFeatureCode(item))
          .filter((code): code is string => Boolean(code)),
      ),
    );
  }

  private normalizeFeatureCode(value: unknown) {
    const code = String(value || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    if (!code) return null;
    if (!/^[A-Z][A-Z0-9_]{1,59}$/.test(code)) {
      throw new BadRequestException('Mã tính năng không hợp lệ');
    }
    return code;
  }

  private async ensureFeaturesExist(featureCodes: string[]) {
    const features = await this.prisma.featureDefinition.findMany({
      where: { code: { in: featureCodes } },
      select: { code: true },
    });
    const found = new Set(features.map((feature) => feature.code));
    const missing = featureCodes.filter(
      (featureCode) => !found.has(featureCode),
    );
    if (missing.length > 0) {
      throw new BadRequestException(
        'Tính năng không tồn tại: ' + missing.join(', '),
      );
    }
  }

  async adminSetUserPassword(admin: any, userId: string, newPassword: string) {
    await this.assertSuperAdmin(admin);
    const result = await this.passwordResetService.setPasswordForUserId(
      userId,
      newPassword,
      { id: admin.id, email: admin.email },
    );
    this.logger.log(
      `Admin password reset completed: admin=${admin.email || admin.id || 'unknown'} targetUserId=${userId}`,
    );
    return result;
  }

  async adminListOrganizationTree(admin: any) {
    await this.assertAdmin(admin);
    await this.seedDefaultOrganizationTree();
    return this.prisma.organizationNode.findMany({
      orderBy: [{ sortOrder: 'asc' }, { type: 'asc' }, { displayName: 'asc' }],
      include: {
        _count: {
          select: {
            children: true,
            users: true,
            stores: true,
            departments: true,
            jobRoles: true,
            regions: true,
            areas: true,
          },
        },
      },
    });
  }

  async adminCreateOrganizationNode(admin: any, body: any) {
    await this.assertSuperAdmin(admin);
    const data = await this.normalizeOrganizationNodeInput(body);
    const node = await this.prisma.organizationNode.create({ data });
    this.logger.log(
      `Organization node created: admin=${admin?.email || admin?.id || 'unknown'} nodeId=${node.id} type=${node.type} code=${node.code}`,
    );
    return node;
  }

  async adminUpdateOrganizationNode(admin: any, id: string, body: any) {
    await this.assertSuperAdmin(admin);
    const current = await this.prisma.organizationNode.findUnique({
      where: { id },
    });
    if (!current) throw new NotFoundException('Không tìm thấy node tổ chức');
    const data = await this.normalizeOrganizationNodeInput(body, current);
    if (current.isSystem) {
      if (
        data.code !== current.code ||
        data.type !== current.type ||
        data.parentId !== current.parentId
      ) {
        throw new BadRequestException(
          'Không được đổi mã, loại hoặc cha của node hệ thống',
        );
      }
    }
    if (data.parentId) await this.assertNoOrganizationCycle(id, data.parentId);
    const node = await this.prisma.organizationNode.update({
      where: { id },
      data,
    });
    this.logger.log(
      `Organization node updated: admin=${admin?.email || admin?.id || 'unknown'} nodeId=${id} type=${node.type} code=${node.code}`,
    );
    return node;
  }

  async adminDeleteOrganizationNode(admin: any, id: string) {
    await this.assertSuperAdmin(admin);
    const node = await this.prisma.organizationNode.findUnique({
      where: { id },
      include: { _count: { select: { children: true } } },
    });
    if (!node) throw new NotFoundException('Không tìm thấy node tổ chức');
    if (node.isSystem) {
      throw new BadRequestException('Không được xóa node tổ chức hệ thống');
    }
    const referenceCount = await this.organizationNodeReferenceCount(id);
    if (node._count.children > 0 || referenceCount > 0) {
      const updated = await this.prisma.organizationNode.update({
        where: { id },
        data: { isActive: false, loginAllowed: false },
      });
      this.logger.warn(
        `Organization node deactivated: admin=${admin?.email || admin?.id || 'unknown'} nodeId=${id} children=${node._count.children} references=${referenceCount}`,
      );
      return { deleted: false, deactivated: true, node: updated };
    }
    await this.prisma.organizationNode.delete({ where: { id } });
    this.logger.warn(
      `Organization node deleted: admin=${admin?.email || admin?.id || 'unknown'} nodeId=${id}`,
    );
    return { deleted: true, id };
  }

  private async normalizeOrganizationNodeInput(input: any, current?: any) {
    const type = this.normalizeOrganizationNodeType(
      input.type ?? current?.type,
    );
    const displayName = this.normalizeRequiredText(
      input.displayName ?? current?.displayName,
      'Tên node tổ chức không được để trống',
      120,
    );
    const emailDomain = ['ROOT_DOMAIN', 'SUBDOMAIN'].includes(type)
      ? this.normalizeRequiredEmailDomain(
          input.emailDomain ?? current?.emailDomain ?? displayName,
        )
      : null;
    if (emailDomain === 'hoanghochoi.com') {
      throw new BadRequestException(
        'Domain break-glass không thuộc cây tổ chức',
      );
    }
    const parentId = await this.resolveOrganizationParentId(
      type,
      input.parentId,
      current,
    );
    const code = input.code
      ? this.normalizeOrganizationNodeCode(input.code)
      : (current?.code ??
        this.organizationCodeFor(type, emailDomain ?? displayName));
    return {
      code,
      displayName,
      type,
      parentId,
      emailDomain,
      loginAllowed: ['ROOT_DOMAIN', 'SUBDOMAIN'].includes(type)
        ? input.loginAllowed !== undefined
          ? input.loginAllowed === true
          : (current?.loginAllowed ?? true)
        : false,
      isActive:
        input.isActive === undefined
          ? (current?.isActive ?? true)
          : input.isActive === true,
      sortOrder: this.normalizeSortOrder(input.sortOrder ?? current?.sortOrder),
    };
  }

  private normalizeOrganizationNodeType(value: unknown) {
    const type = String(value || '')
      .trim()
      .toUpperCase();
    if (!ORG_TYPES.has(type)) {
      throw new BadRequestException('Loại node tổ chức không hợp lệ');
    }
    return type;
  }

  private normalizeOrganizationNodeCode(value: unknown) {
    const code = String(value || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    if (!/^[A-Z][A-Z0-9_]{1,79}$/.test(code)) {
      throw new BadRequestException('Mã node tổ chức không hợp lệ');
    }
    return code;
  }

  private organizationCodeFor(type: string, value: string) {
    return this.normalizeOrganizationNodeCode(
      `${type}_${String(value).replace(/\.[a-z]+$/i, '')}`,
    );
  }

  private normalizeRequiredEmailDomain(value: unknown) {
    const domain = this.normalizeOptionalEmailDomain(value);
    if (!domain)
      throw new BadRequestException('Domain email không được để trống');
    return domain;
  }

  private async resolveOrganizationParentId(
    type: string,
    parentIdInput: unknown,
    current?: any,
  ) {
    if (type === 'ROOT_DOMAIN') return null;
    const parentId = String(parentIdInput ?? current?.parentId ?? '').trim();
    if (!parentId) {
      if (type === 'SUBDOMAIN') return ORG_ROOT_PHONGVU_ID;
      return ORG_ROOT_PHONGVU_ID;
    }
    const parent = await this.prisma.organizationNode.findUnique({
      where: { id: parentId },
      select: { id: true, isActive: true },
    });
    if (!parent || !parent.isActive) {
      throw new BadRequestException('Node cha không hợp lệ');
    }
    return parent.id;
  }

  private async assertNoOrganizationCycle(id: string, parentId: string) {
    if (id === parentId)
      throw new BadRequestException('Node không thể là cha của chính nó');
    let cursor: string | null = parentId;
    for (let i = 0; i < 50 && cursor; i += 1) {
      const parent: { id: string; parentId: string | null } | null =
        await this.prisma.organizationNode.findUnique({
          where: { id: cursor },
          select: { id: true, parentId: true },
        });
      if (!parent) return;
      if (parent.id === id || parent.parentId === id) {
        throw new BadRequestException('Cây tổ chức không được tạo vòng lặp');
      }
      cursor = parent.parentId;
    }
  }

  private async organizationNodeReferenceCount(id: string) {
    const [users, stores, departments, jobRoles, regions, areas] =
      await Promise.all([
        this.prisma.user.count({ where: { organizationNodeId: id } }),
        this.prisma.store.count({ where: { organizationNodeId: id } }),
        this.prisma.departmentDefinition.count({
          where: { organizationNodeId: id },
        }),
        this.prisma.jobRoleDefinition.count({
          where: { organizationNodeId: id },
        }),
        this.prisma.regionDefinition.count({
          where: { organizationNodeId: id },
        }),
        this.prisma.areaDefinition.count({ where: { organizationNodeId: id } }),
      ]);
    return users + stores + departments + jobRoles + regions + areas;
  }

  private normalizeSortOrder(value: unknown) {
    const parsed = Number(value ?? 0);
    if (!Number.isFinite(parsed)) return 0;
    return Math.max(0, Math.min(10000, Math.trunc(parsed)));
  }
  private async resolveStoreForAdmin(admin: any, storeCode?: string) {
    const normalizedStoreCode = String(storeCode || '').trim();
    if (!normalizedStoreCode) return null;

    const store = await this.prisma.store.findUnique({
      where: { storeId: normalizedStoreCode },
      include: { area: true },
    });
    if (!store) throw new BadRequestException('Chi nhánh không hợp lệ');
    if (
      this.isScopedAdmin(admin) &&
      !this.storeWithinAdminScope(admin, store)
    ) {
      throw new ForbiddenException('Chỉ được gán user trong phạm vi quản lý');
    }
    return store.id;
  }

  private async assertAdmin(user: any) {
    if (
      await this.policyService.canAccessPolicy(user, ADMIN_POLICY_CODES.ADMIN)
    ) {
      return;
    }
    throw new ForbiddenException('Không có quyền quản trị user');
  }

  private async assertSuperAdmin(user: any) {
    if (user.role === SUPER_ADMIN_ROLE) {
      return;
    }
    throw new ForbiddenException('Chỉ SUPER_ADMIN được quản lý role');
  }

  private async assertPolicy(user: any, policyCode: string, message: string) {
    if (await this.policyService.canAccessPolicy(user, policyCode)) {
      return;
    }
    throw new ForbiddenException(message);
  }

  private async assertRoleEditable(
    admin: any,
    role: string,
    currentRole?: string,
  ) {
    if (currentRole && role === currentRole) {
      return;
    }
    if (!currentRole && role === STAFF_ROLE) {
      return;
    }
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_USER_ROLE_EDIT,
      'Không có quyền sửa role',
    );
  }

  private adminScope(admin: any) {
    if (this.isScopedAdmin(admin)) {
      const scope = this.effectiveWorkScope(admin);
      const domainScope = this.adminDomainScope(admin);
      if (scope === NATIONAL_SCOPE) return domainScope;
      if (scope === REGION_SCOPE) {
        const locationScope = admin.regionCode
          ? {
              OR: [
                { regionCode: admin.regionCode },
                { store: { area: { regionCode: admin.regionCode } } },
              ],
            }
          : { id: '__NO_REGION__' };
        return this.combineUserScope(domainScope, locationScope);
      }
      if (scope === AREA_SCOPE) {
        const locationScope = admin.areaCode
          ? {
              OR: [
                { areaCode: admin.areaCode },
                { store: { areaCode: admin.areaCode } },
              ],
            }
          : { id: '__NO_AREA__' };
        return this.combineUserScope(domainScope, locationScope);
      }
      const locationScope = admin.storeId
        ? { storeId: admin.storeId }
        : { id: '__NO_STORE__' };
      return this.combineUserScope(domainScope, locationScope);
    }
    return {};
  }

  private isScopedAdmin(user: any) {
    return (
      user.role === ADMIN_ROLE ||
      user.role === ADMIN_ACARE_ROLE ||
      user.role === MANAGER_ROLE
    );
  }

  private storeWithinAdminScope(admin: any, store: any) {
    const scope = this.effectiveWorkScope(admin);
    if (scope === NATIONAL_SCOPE) return true;
    if (scope === REGION_SCOPE) {
      return Boolean(
        admin.regionCode && store.area?.regionCode === admin.regionCode,
      );
    }
    if (scope === AREA_SCOPE) {
      return Boolean(admin.areaCode && store.areaCode === admin.areaCode);
    }
    return Boolean(admin.storeId && admin.storeId === store.id);
  }

  private userWithinAdminScope(admin: any, user: any) {
    if (this.isAcareAdmin(admin) && !this.isAcaretekEmail(user.email)) {
      return false;
    }
    const scope = this.effectiveWorkScope(admin);
    if (scope === NATIONAL_SCOPE) return true;
    const userArea = this.areaForUser(user);
    const userRegion = this.regionForUser(user);
    if (scope === REGION_SCOPE) {
      return Boolean(
        admin.regionCode &&
        (user.regionCode === admin.regionCode ||
          userRegion?.code === admin.regionCode),
      );
    }
    if (scope === AREA_SCOPE) {
      return Boolean(
        admin.areaCode &&
        (user.areaCode === admin.areaCode || userArea?.code === admin.areaCode),
      );
    }
    return Boolean(admin.storeId && user.storeId === admin.storeId);
  }

  private userDtoInclude() {
    return {
      store: { include: { area: { include: { region: true } } } },
      region: true,
      area: { include: { region: true } },
      organizationNode: true,
      userFeatureAssignments: {
        where: { enabled: true },
        select: { featureCode: true },
        orderBy: { featureCode: Prisma.SortOrder.asc },
      },
    };
  }

  private async adminUserWhere(
    scope: Prisma.UserWhereInput,
    filters: any,
    query: string,
  ): Promise<Prisma.UserWhereInput> {
    const conditions: Prisma.UserWhereInput[] = [];
    if (Object.keys(scope).length > 0) conditions.push(scope);
    if (query) {
      conditions.push({
        OR: [
          { email: { contains: query, mode: 'insensitive' } },
          { firstName: { contains: query, mode: 'insensitive' } },
          { lastName: { contains: query, mode: 'insensitive' } },
        ],
      });
    }
    const domain = this.normalizeOptionalEmailDomain(filters.domain);
    if (domain) {
      conditions.push({
        email: { endsWith: '@' + domain, mode: Prisma.QueryMode.insensitive },
      });
    }
    const role = String(filters.role || '').trim();
    if (role) conditions.push({ role: this.normalizeRoleCode(role, true) });
    const status = String(filters.status || '')
      .trim()
      .toLowerCase();
    if (status === 'yes' || status === 'no') conditions.push({ status });
    const featureCode = String(filters.featureCode || '').trim();
    if (featureCode) {
      conditions.push({
        userFeatureAssignments: {
          some: {
            featureCode: this.normalizeRoleCode(featureCode, true),
            enabled: true,
          },
        },
      });
    }
    const orgNodeWhere = await this.userOrganizationNodeWhere(
      filters.orgNodeId,
    );
    if (orgNodeWhere) conditions.push(orgNodeWhere);
    return conditions.length > 0 ? { AND: conditions } : {};
  }

  private async userOrganizationNodeWhere(
    orgNodeIdInput: unknown,
  ): Promise<Prisma.UserWhereInput | null> {
    const orgNodeId = String(orgNodeIdInput || '').trim();
    if (!orgNodeId) return null;
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return { organizationNodeId: orgNodeId };
    const nodes: Array<{
      id: string;
      parentId: string | null;
      emailDomain: string | null;
    }> = await organizationNode.findMany({
      select: { id: true, parentId: true, emailDomain: true },
    });
    const ids = new Set<string>([orgNodeId]);
    let changed = true;
    while (changed) {
      changed = false;
      for (const node of nodes) {
        if (node.parentId && ids.has(node.parentId) && !ids.has(node.id)) {
          ids.add(node.id);
          changed = true;
        }
      }
    }
    const idList = Array.from(ids);
    const domains = nodes
      .filter((node: { id: string }) => ids.has(node.id))
      .map((node: { emailDomain: string | null }) =>
        this.normalizeOptionalEmailDomain(node.emailDomain),
      )
      .filter((domain: string | null): domain is string => Boolean(domain));
    return {
      OR: [
        { organizationNodeId: { in: idList } },
        { store: { organizationNodeId: { in: idList } } },
        { department: { organizationNodeId: { in: idList } } },
        { jobRole: { organizationNodeId: { in: idList } } },
        { region: { organizationNodeId: { in: idList } } },
        { area: { organizationNodeId: { in: idList } } },
        ...domains.map((domain: string) => ({
          email: { endsWith: '@' + domain, mode: Prisma.QueryMode.insensitive },
        })),
      ],
    };
  }

  private toUserDto(user: any) {
    const region = this.regionForUser(user);
    const area = this.areaForUser(user);
    return {
      id: user.id,
      email: user.email,
      emailDomain: this.emailDomainFromEmail(user.email),
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
      regionCode: region?.code ?? null,
      regionName: region?.displayName ?? null,
      regionAbbreviation: region?.abbreviation ?? null,
      areaCode: area?.code ?? null,
      areaName: area?.displayName ?? null,
      areaAbbreviation: area?.abbreviation ?? null,
      organizationNodeId: user.organizationNodeId ?? null,
      organizationNodeName: user.organizationNode?.displayName ?? null,
      featureCodes: this.featureCodesForUser(user),
      resolvedFeatureAccess: this.featureAccessMapForUser(user),
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
    await this.assertAdmin(admin);
    await this.seedDefaultRoles();
    return this.prisma.roleDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
    });
  }

  async adminListDepartments(admin: any) {
    await this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    return this.prisma.departmentDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
      include: {
        _count: { select: { users: true, featureAccessRules: true } },
      },
    });
  }

  async adminListJobRoles(admin: any) {
    await this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    return this.prisma.jobRoleDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
      include: {
        _count: { select: { users: true, featureAccessRules: true } },
      },
    });
  }

  async adminListRegions(admin: any) {
    await this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    const regions = await this.prisma.regionDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
      include: {
        _count: { select: { areas: true, featureAccessRules: true } },
      },
    });
    const userCounts = await Promise.all(
      regions.map((region) =>
        this.prisma.user.count({
          where: this.regionUserCountWhere(region.code),
        }),
      ),
    );
    return regions.map((region, index) => ({
      ...region,
      _count: { ...region._count, users: userCounts[index] },
    }));
  }

  async adminListAreas(admin: any, regionCodeInput?: string) {
    await this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    const regionCode = regionCodeInput
      ? this.normalizePersonnelCode(regionCodeInput, 'Mã Miền không hợp lệ')
      : null;
    const areas = await this.prisma.areaDefinition.findMany({
      where: regionCode ? { regionCode } : undefined,
      orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
      include: {
        region: true,
        _count: { select: { stores: true, featureAccessRules: true } },
      },
    });
    const userCounts = await Promise.all(
      areas.map((area) =>
        this.prisma.user.count({
          where: this.areaUserCountWhere(area.code),
        }),
      ),
    );
    return areas.map((area, index) => ({
      ...area,
      _count: { ...area._count, users: userCounts[index] },
    }));
  }

  async adminCreateRegion(admin: any, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_REGIONS,
      'Không có quyền tạo Miền',
    );
    const code = this.normalizePersonnelCode(
      body.code || body.abbreviation,
      'Mã Miền không hợp lệ',
    );
    if (!code) throw new BadRequestException('Mã Miền không được để trống');
    const existing = await this.prisma.regionDefinition.findUnique({
      where: { code },
    });
    if (existing) throw new BadRequestException('Miền đã tồn tại');
    const displayName = this.normalizeRequiredText(
      body.displayName,
      'Tên Miền không được để trống',
      80,
    );
    const abbreviation = this.normalizeCatalogAbbreviation(
      body.abbreviation || code,
    );
    return this.prisma.$transaction(async (tx) => {
      const region = await tx.regionDefinition.create({
        data: {
          code,
          displayName,
          abbreviation,
          description: this.normalizeRoleDescription(body.description),
          isSystem: false,
          isActive: body.isActive !== false,
        },
      });
      const sameCodeArea = await tx.areaDefinition.findUnique({
        where: { code },
      });
      if (!sameCodeArea) {
        await tx.areaDefinition.create({
          data: {
            code,
            displayName,
            abbreviation,
            description: 'Vùng mặc định cùng mã Miền',
            regionCode: code,
            isSystem: false,
            isActive: true,
          },
        });
      }
      return region;
    });
  }

  async adminUpdateRegion(admin: any, currentCodeInput: string, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_REGIONS,
      'Không có quyền sửa Miền',
    );
    const currentCode = this.normalizePersonnelCode(
      currentCodeInput,
      'Mã Miền không hợp lệ',
    );
    if (!currentCode) throw new BadRequestException('Mã Miền không hợp lệ');
    const current = await this.prisma.regionDefinition.findUnique({
      where: { code: currentCode },
    });
    if (!current) throw new NotFoundException('Không tìm thấy Miền');
    const nextCode = body.code
      ? this.normalizePersonnelCode(body.code, 'Mã Miền không hợp lệ')
      : current.code;
    if (!nextCode) throw new BadRequestException('Mã Miền không hợp lệ');
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Không được đổi mã Miền hệ thống');
    }
    return this.prisma.regionDefinition.update({
      where: { code: current.code },
      data: {
        code: nextCode,
        displayName:
          body.displayName === undefined
            ? current.displayName
            : this.normalizeRequiredText(
                body.displayName,
                'Tên Miền không được để trống',
                80,
              ),
        abbreviation:
          body.abbreviation === undefined
            ? current.abbreviation
            : this.normalizeCatalogAbbreviation(body.abbreviation),
        description:
          body.description === undefined
            ? current.description
            : this.normalizeRoleDescription(body.description),
        isActive:
          body.isActive === undefined
            ? current.isActive
            : body.isActive === true,
      },
    });
  }

  async adminDeleteRegion(admin: any, codeInput: string) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_REGIONS,
      'Không có quyền xóa Miền',
    );
    const code = this.normalizePersonnelCode(codeInput, 'Mã Miền không hợp lệ');
    if (!code) throw new BadRequestException('Mã Miền không hợp lệ');
    const region = await this.prisma.regionDefinition.findUnique({
      where: { code },
      include: {
        _count: {
          select: { areas: true, users: true, featureAccessRules: true },
        },
      },
    });
    if (!region) throw new NotFoundException('Không tìm thấy Miền');
    if (region.isSystem)
      throw new BadRequestException('Không được xóa Miền hệ thống');
    if (
      region._count.areas > 0 ||
      region._count.users > 0 ||
      region._count.featureAccessRules > 0
    ) {
      throw new BadRequestException('Miền đang được sử dụng, không thể xóa');
    }
    await this.prisma.regionDefinition.delete({ where: { code } });
    return { deleted: true, code };
  }

  async adminCreateArea(admin: any, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_REGIONS,
      'Không có quyền tạo Vùng',
    );
    const code = this.normalizePersonnelCode(
      body.code || body.abbreviation,
      'Mã Vùng không hợp lệ',
    );
    if (!code) throw new BadRequestException('Mã Vùng không được để trống');
    const regionCode = await this.resolveRegionCode(body.regionCode, null);
    if (!regionCode) throw new BadRequestException('Vui lòng chọn Miền');
    const existing = await this.prisma.areaDefinition.findUnique({
      where: { code },
    });
    if (existing) throw new BadRequestException('Vùng đã tồn tại');
    return this.prisma.areaDefinition.create({
      data: {
        code,
        displayName: this.normalizeRequiredText(
          body.displayName,
          'Tên Vùng không được để trống',
          80,
        ),
        abbreviation: this.normalizeCatalogAbbreviation(
          body.abbreviation || code,
        ),
        description: this.normalizeRoleDescription(body.description),
        regionCode,
        isSystem: false,
        isActive: body.isActive !== false,
      },
      include: { region: true },
    });
  }

  async adminUpdateArea(admin: any, currentCodeInput: string, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_REGIONS,
      'Không có quyền sửa Vùng',
    );
    const currentCode = this.normalizePersonnelCode(
      currentCodeInput,
      'Mã Vùng không hợp lệ',
    );
    if (!currentCode) throw new BadRequestException('Mã Vùng không hợp lệ');
    const current = await this.prisma.areaDefinition.findUnique({
      where: { code: currentCode },
    });
    if (!current) throw new NotFoundException('Không tìm thấy Vùng');
    const nextCode = body.code
      ? this.normalizePersonnelCode(body.code, 'Mã Vùng không hợp lệ')
      : current.code;
    if (!nextCode) throw new BadRequestException('Mã Vùng không hợp lệ');
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Không được đổi mã Vùng hệ thống');
    }
    const regionCode =
      body.regionCode === undefined
        ? current.regionCode
        : await this.resolveRegionCode(body.regionCode, current.regionCode);
    return this.prisma.areaDefinition.update({
      where: { code: current.code },
      data: {
        code: nextCode,
        displayName:
          body.displayName === undefined
            ? current.displayName
            : this.normalizeRequiredText(
                body.displayName,
                'Tên Vùng không được để trống',
                80,
              ),
        abbreviation:
          body.abbreviation === undefined
            ? current.abbreviation
            : this.normalizeCatalogAbbreviation(body.abbreviation),
        description:
          body.description === undefined
            ? current.description
            : this.normalizeRoleDescription(body.description),
        regionCode: regionCode ?? current.regionCode,
        isActive:
          body.isActive === undefined
            ? current.isActive
            : body.isActive === true,
      },
      include: { region: true },
    });
  }

  async adminDeleteArea(admin: any, codeInput: string) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_REGIONS,
      'Không có quyền xóa Vùng',
    );
    const code = this.normalizePersonnelCode(codeInput, 'Mã Vùng không hợp lệ');
    if (!code) throw new BadRequestException('Mã Vùng không hợp lệ');
    const area = await this.prisma.areaDefinition.findUnique({
      where: { code },
      include: {
        _count: {
          select: { stores: true, users: true, featureAccessRules: true },
        },
      },
    });
    if (!area) throw new NotFoundException('Không tìm thấy Vùng');
    if (area.isSystem)
      throw new BadRequestException('Không được xóa Vùng hệ thống');
    if (
      area._count.stores > 0 ||
      area._count.users > 0 ||
      area._count.featureAccessRules > 0
    ) {
      throw new BadRequestException('Vùng đang được sử dụng, không thể xóa');
    }
    await this.prisma.areaDefinition.delete({ where: { code } });
    return { deleted: true, code };
  }

  async adminCreateDepartment(admin: any, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_PERSONNEL,
      'Không có quyền tạo phòng ban',
    );
    const code = this.normalizePersonnelCode(
      body.code,
      'Mã phòng ban không hợp lệ',
    );
    if (!code)
      throw new BadRequestException('Mã phòng ban không được để trống');
    const existing = await this.prisma.departmentDefinition.findUnique({
      where: { code },
    });
    if (existing) throw new BadRequestException('Phòng ban đã tồn tại');
    return this.prisma.departmentDefinition.create({
      data: {
        code,
        displayName: this.normalizeRequiredText(
          body.displayName,
          'Tên phòng ban không được để trống',
          80,
        ),
        description: this.normalizeRoleDescription(body.description),
        isSystem: false,
        isActive: body.isActive !== false,
      },
    });
  }

  async adminUpdateDepartment(admin: any, currentCodeInput: string, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_PERSONNEL,
      'Không có quyền sửa phòng ban',
    );
    const currentCode = this.normalizePersonnelCode(
      currentCodeInput,
      'Mã phòng ban không hợp lệ',
    );
    if (!currentCode)
      throw new BadRequestException('Mã phòng ban không hợp lệ');
    const current = await this.prisma.departmentDefinition.findUnique({
      where: { code: currentCode },
    });
    if (!current) throw new NotFoundException('Không tìm thấy phòng ban');
    const nextCode = body.code
      ? this.normalizePersonnelCode(body.code, 'Mã phòng ban không hợp lệ')
      : current.code;
    if (!nextCode) throw new BadRequestException('Mã phòng ban không hợp lệ');
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Không được đổi mã phòng ban hệ thống');
    }
    return this.prisma.departmentDefinition.update({
      where: { code: current.code },
      data: {
        code: nextCode,
        displayName:
          body.displayName === undefined
            ? current.displayName
            : this.normalizeRequiredText(
                body.displayName,
                'Tên phòng ban không được để trống',
                80,
              ),
        description:
          body.description === undefined
            ? current.description
            : this.normalizeRoleDescription(body.description),
        isActive:
          body.isActive === undefined
            ? current.isActive
            : body.isActive === true,
      },
    });
  }

  async adminDeleteDepartment(admin: any, codeInput: string) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_PERSONNEL,
      'Không có quyền xóa phòng ban',
    );
    const code = this.normalizePersonnelCode(
      codeInput,
      'Mã phòng ban không hợp lệ',
    );
    if (!code) throw new BadRequestException('Mã phòng ban không hợp lệ');
    const department = await this.prisma.departmentDefinition.findUnique({
      where: { code },
      include: {
        _count: { select: { users: true, featureAccessRules: true } },
      },
    });
    if (!department) throw new NotFoundException('Không tìm thấy phòng ban');
    if (department.isSystem)
      throw new BadRequestException('Không được xóa phòng ban hệ thống');
    if (
      department._count.users > 0 ||
      department._count.featureAccessRules > 0
    ) {
      throw new BadRequestException(
        'Phòng ban đang được sử dụng, không thể xóa',
      );
    }
    await this.prisma.departmentDefinition.delete({ where: { code } });
    return { deleted: true, code };
  }

  async adminCreateJobRole(admin: any, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_PERSONNEL,
      'Không có quyền tạo chức danh',
    );
    const code = this.normalizePersonnelCode(
      body.code,
      'Mã chức danh không hợp lệ',
    );
    if (!code)
      throw new BadRequestException('Mã chức danh không được để trống');
    const existing = await this.prisma.jobRoleDefinition.findUnique({
      where: { code },
    });
    if (existing) throw new BadRequestException('Chức danh đã tồn tại');
    const departmentCode = await this.resolveDepartmentCode(
      body.departmentCode,
      null,
    );
    return this.prisma.jobRoleDefinition.create({
      data: {
        code,
        displayName: this.normalizeRequiredText(
          body.displayName,
          'Tên chức danh không được để trống',
          80,
        ),
        description: this.normalizeRoleDescription(body.description),
        departmentCode,
        isSystem: false,
        isActive: body.isActive !== false,
      },
    });
  }

  async adminUpdateJobRole(admin: any, currentCodeInput: string, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_PERSONNEL,
      'Không có quyền sửa chức danh',
    );
    const currentCode = this.normalizePersonnelCode(
      currentCodeInput,
      'Mã chức danh không hợp lệ',
    );
    if (!currentCode)
      throw new BadRequestException('Mã chức danh không hợp lệ');
    const current = await this.prisma.jobRoleDefinition.findUnique({
      where: { code: currentCode },
    });
    if (!current) throw new NotFoundException('Không tìm thấy chức danh');
    const nextCode = body.code
      ? this.normalizePersonnelCode(body.code, 'Mã chức danh không hợp lệ')
      : current.code;
    if (!nextCode) throw new BadRequestException('Mã chức danh không hợp lệ');
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Không được đổi mã chức danh hệ thống');
    }
    const departmentCode =
      body.departmentCode === undefined
        ? current.departmentCode
        : await this.resolveDepartmentCode(
            body.departmentCode,
            current.departmentCode,
          );
    return this.prisma.jobRoleDefinition.update({
      where: { code: current.code },
      data: {
        code: nextCode,
        displayName:
          body.displayName === undefined
            ? current.displayName
            : this.normalizeRequiredText(
                body.displayName,
                'Tên chức danh không được để trống',
                80,
              ),
        description:
          body.description === undefined
            ? current.description
            : this.normalizeRoleDescription(body.description),
        departmentCode,
        isActive:
          body.isActive === undefined
            ? current.isActive
            : body.isActive === true,
      },
    });
  }

  async adminDeleteJobRole(admin: any, codeInput: string) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_PERSONNEL,
      'Không có quyền xóa chức danh',
    );
    const code = this.normalizePersonnelCode(
      codeInput,
      'Mã chức danh không hợp lệ',
    );
    if (!code) throw new BadRequestException('Mã chức danh không hợp lệ');
    const jobRole = await this.prisma.jobRoleDefinition.findUnique({
      where: { code },
      include: {
        _count: { select: { users: true, featureAccessRules: true } },
      },
    });
    if (!jobRole) throw new NotFoundException('Không tìm thấy chức danh');
    if (jobRole.isSystem)
      throw new BadRequestException('Không được xóa chức danh hệ thống');
    if (jobRole._count.users > 0 || jobRole._count.featureAccessRules > 0) {
      throw new BadRequestException(
        'Chức danh đang được sử dụng, không thể xóa',
      );
    }
    await this.prisma.jobRoleDefinition.delete({ where: { code } });
    return { deleted: true, code };
  }

  async adminCreateRole(admin: any, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_ROLES,
      'Không có quyền tạo role',
    );
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
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_ROLES,
      'Không có quyền sửa role',
    );
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
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_ROLES,
      'Không có quyền xóa role',
    );
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
    await this.assertAdmin(admin);
    const query = q?.trim();
    const stores = await this.prisma.store.findMany({
      where: this.adminStoreScope(admin, query),
      orderBy: { storeId: 'asc' },
      include: {
        area: { include: { region: true } },
        _count: { select: { users: true } },
      },
    });
    return stores.map((store) => this.toStoreDto(store));
  }

  async adminCreateStore(admin: any, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_STORE_CREATE,
      'Không có quyền tạo SR',
    );
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

    const areaCode = await this.resolveAreaCodeForStore(body.areaCode);

    const store = await this.prisma.store.create({
      data: {
        storeId,
        storeName,
        areaCode,
        ...this.normalizeStorePaymentFields(body),
        ...this.normalizeMapVietinFields(body),
      },
      include: {
        area: { include: { region: true } },
        _count: { select: { users: true } },
      },
    });
    return this.toStoreDto(store);
  }

  async adminUpdateStore(admin: any, currentStoreId: string, body: any) {
    const currentCode = this.normalizeStoreCode(currentStoreId);
    const current = await this.prisma.store.findUnique({
      where: { storeId: currentCode },
      include: { area: true },
    });
    if (!current) throw new NotFoundException('Không tìm thấy store');
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_STORES,
      'Không có quyền sửa SR',
    );

    if (
      this.isScopedAdmin(admin) &&
      !this.storeWithinAdminScope(admin, current)
    ) {
      throw new ForbiddenException('Không có quyền sửa showroom khác');
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

    const nextAreaCode =
      body.areaCode === undefined
        ? current.areaCode
        : await this.resolveAreaCodeForStore(body.areaCode);
    if (nextAreaCode !== current.areaCode) {
      await this.assertPolicy(
        admin,
        ADMIN_POLICY_CODES.ADMIN_STORE_SCOPE_EDIT,
        'Không có quyền đổi Vùng/Miền của SR',
      );
    }

    const store = await this.prisma.$transaction(async (tx) => {
      const updatedStore = await tx.store.update({
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
          areaCode: nextAreaCode,
          ...this.normalizeStorePaymentFields(body),
          ...this.normalizeMapVietinFields(body),
        },
        include: {
          area: { include: { region: true } },
          _count: { select: { users: true } },
        },
      });

      if (nextAreaCode !== current.areaCode) {
        const regionCode = updatedStore.area?.regionCode ?? DEFAULT_REGION_CODE;
        const syncResult = await tx.user.updateMany({
          where: { storeId: current.id, workScopeType: STORE_SCOPE },
          data: { areaCode: updatedStore.areaCode, regionCode },
        });
        this.logger.log(
          `Store area changed: store=${updatedStore.storeId} area=${current.areaCode || 'null'}->${updatedStore.areaCode || 'null'} region=${regionCode} syncedUsers=${syncResult.count}`,
        );
      }

      return updatedStore;
    });
    return this.toStoreDto(store);
  }

  async adminDeleteStore(admin: any, storeIdInput: string) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_STORE_CREATE,
      'Không có quyền xóa SR',
    );
    const storeId = this.normalizeStoreCode(storeIdInput);
    const store = await this.prisma.store.findUnique({
      where: { storeId },
      include: {
        _count: { select: { users: true, featureAccessRules: true } },
      },
    });
    if (!store) throw new NotFoundException('Không tìm thấy store');
    if (store._count.users > 0) {
      throw new BadRequestException('Store đang có user, không thể xóa');
    }
    if (store._count.featureAccessRules > 0) {
      throw new BadRequestException(
        'Store đang có rule tính năng, không thể xóa',
      );
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
            isActive: true,
          },
          create: { ...department, isSystem: true, isActive: true },
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
            isActive: true,
          },
          create: { ...jobRole, isSystem: true, isActive: true },
        }),
      ),
    );

    await Promise.all(
      DEFAULT_REGION_DEFINITIONS.map((region) =>
        this.prisma.regionDefinition.upsert({
          where: { code: region.code },
          update: {
            displayName: region.displayName,
            abbreviation: region.abbreviation,
            description: region.description,
            isSystem: true,
            isActive: true,
          },
          create: { ...region, isActive: true },
        }),
      ),
    );

    await Promise.all(
      DEFAULT_AREA_DEFINITIONS.map((area) =>
        this.prisma.areaDefinition.upsert({
          where: { code: area.code },
          update: {
            displayName: area.displayName,
            abbreviation: area.abbreviation,
            description: area.description,
            regionCode: area.regionCode,
            isSystem: true,
            isActive: true,
          },
          create: { ...area, isActive: true },
        }),
      ),
    );

    this.logger.log(
      `Personnel catalog seeded: departments=${DEFAULT_DEPARTMENT_DEFINITIONS.length}, jobRoles=${DEFAULT_JOB_ROLE_DEFINITIONS.length}, regions=${DEFAULT_REGION_DEFINITIONS.length}, areas=${DEFAULT_AREA_DEFINITIONS.length}`,
    );
  }

  private featureCodesForUser(user: any) {
    const assignments = Array.isArray(user.userFeatureAssignments)
      ? user.userFeatureAssignments
      : [];
    return assignments
      .map((assignment: any) => String(assignment.featureCode || '').trim())
      .filter(Boolean);
  }

  private featureAccessMapForUser(user: any) {
    if (user.role === SUPER_ADMIN_ROLE) return undefined;
    return Object.fromEntries(
      this.featureCodesForUser(user).map((featureCode: string) => [
        featureCode,
        true,
      ]),
    );
  }

  private emailDomainFromEmail(email: unknown) {
    const value = String(email || '')
      .trim()
      .toLowerCase();
    const atIndex = value.lastIndexOf('@');
    return atIndex >= 0 ? value.slice(atIndex + 1) : null;
  }

  private normalizeOptionalEmailDomain(value: unknown) {
    const domain = String(value || '')
      .trim()
      .replace(/^@+/, '')
      .toLowerCase();
    if (!domain) return null;
    if (
      domain.length > 120 ||
      !/^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/.test(domain)
    ) {
      throw new BadRequestException('Domain email không hợp lệ');
    }
    return domain;
  }

  private async seedDefaultOrganizationTree() {
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.upsert) return;

    const phongVuRoot = await organizationNode.upsert({
      where: { code: 'DOMAIN_PHONGVU_VN' },
      update: {
        displayName: 'phongvu.vn',
        type: 'ROOT_DOMAIN',
        emailDomain: 'phongvu.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 10,
      },
      create: {
        id: ORG_ROOT_PHONGVU_ID,
        code: 'DOMAIN_PHONGVU_VN',
        displayName: 'phongvu.vn',
        type: 'ROOT_DOMAIN',
        emailDomain: 'phongvu.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 10,
      },
    });
    await organizationNode.upsert({
      where: { code: 'SUBDOMAIN_PHONGVU_VN' },
      update: {
        displayName: 'phongvu.vn',
        type: 'SUBDOMAIN',
        parentId: phongVuRoot.id,
        emailDomain: 'phongvu.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 11,
      },
      create: {
        id: ORG_SUBDOMAIN_PHONGVU_ID,
        code: 'SUBDOMAIN_PHONGVU_VN',
        displayName: 'phongvu.vn',
        type: 'SUBDOMAIN',
        parentId: phongVuRoot.id,
        emailDomain: 'phongvu.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 11,
      },
    });
    await organizationNode.upsert({
      where: { code: 'DOMAIN_ACARETEK_VN' },
      update: {
        displayName: 'acaretek.vn',
        type: 'ROOT_DOMAIN',
        emailDomain: 'acaretek.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 20,
      },
      create: {
        id: ORG_ROOT_ACARETEK_ID,
        code: 'DOMAIN_ACARETEK_VN',
        displayName: 'acaretek.vn',
        type: 'ROOT_DOMAIN',
        emailDomain: 'acaretek.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 20,
      },
    });
    this.logger.log('Organization root domains seeded');
  }

  private async bootstrapBreakGlassSuperAdmin() {
    await this.ensureRoleExists(SUPER_ADMIN_ROLE);
    const current = await this.prisma.user.findUnique({
      where: { email: BREAK_GLASS_SUPER_ADMIN_EMAIL },
      select: { id: true, password: true },
    });

    if (current) {
      await this.prisma.user.update({
        where: { id: current.id },
        data: {
          role: SUPER_ADMIN_ROLE,
          status: 'yes',
          workScopeType: NATIONAL_SCOPE,
          storeId: null,
          regionCode: null,
          areaCode: null,
          organizationNodeId: null,
          ...(current.password
            ? {}
            : { password: BREAK_GLASS_SUPER_ADMIN_PASSWORD_HASH }),
        },
      });
      this.logger.log(
        `Break-glass super admin verified: email=${BREAK_GLASS_SUPER_ADMIN_EMAIL} passwordSeeded=${!current.password}`,
      );
    } else {
      await this.prisma.user.create({
        data: {
          email: BREAK_GLASS_SUPER_ADMIN_EMAIL,
          password: BREAK_GLASS_SUPER_ADMIN_PASSWORD_HASH,
          firstName: 'Admin',
          lastName: 'Hoanghochoi',
          role: SUPER_ADMIN_ROLE,
          status: 'yes',
          workScopeType: NATIONAL_SCOPE,
          storeId: null,
          regionCode: null,
          areaCode: null,
          organizationNodeId: null,
          profileCompletedAt: new Date(),
        },
      });
      this.logger.log(
        `Break-glass super admin created: email=${BREAK_GLASS_SUPER_ADMIN_EMAIL}`,
      );
    }

    await this.retireLegacySuperAdmin();
  }

  private async retireLegacySuperAdmin() {
    const legacy = await this.prisma.user.findUnique({
      where: { email: LEGACY_SUPER_ADMIN_EMAIL },
      select: { id: true, email: true },
    });
    if (!legacy) return;

    const [warrantyCount, feedbackCount, fifoLogCount, vietQrCount] =
      await Promise.all([
        this.prisma.warranty.count({
          where: {
            OR: [{ createdById: legacy.id }, { handledById: legacy.id }],
          },
        }),
        this.prisma.feedback.count({ where: { userId: legacy.id } }),
        this.prisma.fifoLog.count({ where: { userId: legacy.id } }),
        this.prisma.vietQrPaymentIntent.count({
          where: { createdById: legacy.id },
        }),
      ]);
    const blockerCount =
      warrantyCount + feedbackCount + fifoLogCount + vietQrCount;
    const now = new Date();

    await this.prisma.$transaction(async (tx) => {
      await tx.userPlatformSession.updateMany({
        where: { userId: legacy.id, revokedAt: null },
        data: { revokedAt: now, revokedReason: 'LEGACY_SUPER_ADMIN_RETIRED' },
      });
      await tx.passwordResetToken.updateMany({
        where: { userId: legacy.id, consumedAt: null },
        data: { consumedAt: now },
      });
      await tx.emailVerificationCode.updateMany({
        where: { email: legacy.email, consumedAt: null },
        data: { consumedAt: now },
      });
      await tx.adminPolicyRule.deleteMany({ where: { userId: legacy.id } });
      await tx.featureAccessRule.deleteMany({ where: { userId: legacy.id } });
      await tx.userFeatureAssignment.deleteMany({
        where: { userId: legacy.id },
      });

      if (blockerCount === 0) {
        await tx.user.delete({ where: { id: legacy.id } });
        return;
      }

      await tx.user.update({
        where: { id: legacy.id },
        data: {
          email: `deleted-${legacy.id}@legacy-super-admin.local`,
          password: '',
          role: STAFF_ROLE,
          status: 'no',
          tokenVersion: { increment: 1 },
          storeId: null,
          workScopeType: NATIONAL_SCOPE,
          regionCode: null,
          areaCode: null,
          organizationNodeId: null,
        },
      });
    });

    this.logger.warn(
      `Legacy super admin retired: email=${LEGACY_SUPER_ADMIN_EMAIL} mode=${blockerCount === 0 ? 'deleted' : 'tombstoned'} blockers=${blockerCount}`,
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
    const scopeLocation = await this.resolveScopeLocation(body, {
      current: options.current,
      storeUuid: options.storeUuid,
      workScopeType,
    });

    return { departmentCode, jobRoleCode, workScopeType, ...scopeLocation };
  }

  private async resolveScopeLocation(
    body: any,
    options: {
      current?: any;
      storeUuid?: string | null;
      workScopeType: string;
    },
  ) {
    if (options.workScopeType === NATIONAL_SCOPE) {
      return { regionCode: null, areaCode: null };
    }

    if (options.workScopeType === STORE_SCOPE) {
      const store = options.storeUuid
        ? await this.prisma.store.findUnique({
            where: { id: options.storeUuid },
            include: { area: { include: { region: true } } },
          })
        : null;
      const areaCode = store?.areaCode ?? DEFAULT_REGION_CODE;
      const regionCode = store?.area?.regionCode ?? DEFAULT_REGION_CODE;
      return { regionCode, areaCode };
    }

    if (options.workScopeType === AREA_SCOPE) {
      const areaCode = await this.resolveAreaCode(
        body.areaCode,
        options.current?.areaCode ?? null,
      );
      if (!areaCode) throw new BadRequestException('Vui lòng chọn Vùng');
      const area = await this.prisma.areaDefinition.findUnique({
        where: { code: areaCode },
      });
      if (!area) throw new BadRequestException('Vùng không tồn tại');
      return { regionCode: area.regionCode, areaCode: area.code };
    }

    const regionCode = await this.resolveRegionCode(
      body.regionCode,
      options.current?.regionCode ?? null,
    );
    if (!regionCode) throw new BadRequestException('Vui lòng chọn Miền');
    const areaCode = await this.resolveOptionalAreaForRegion(
      body.areaCode,
      options.current?.areaCode ?? null,
      regionCode,
    );
    return { regionCode, areaCode };
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
    if (!department || !department.isActive) {
      this.logger.warn(`Personnel validation failed: department=${code}`);
      throw new BadRequestException('Phòng ban không tồn tại hoặc đã tắt');
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
    if (!jobRole || !jobRole.isActive) {
      this.logger.warn(`Personnel validation failed: jobRole=${code}`);
      throw new BadRequestException('Chức danh không tồn tại hoặc đã tắt');
    }
    return jobRole.code;
  }

  private async resolveRegionCode(input: unknown, current?: string | null) {
    if (input === undefined) return current ?? null;
    const code = this.normalizePersonnelCode(input, 'Mã Miền không hợp lệ');
    if (!code) return null;
    const region = await this.prisma.regionDefinition.findUnique({
      where: { code },
    });
    if (!region || !region.isActive) {
      this.logger.warn(`Personnel validation failed: region=${code}`);
      throw new BadRequestException('Miền không tồn tại hoặc đã tắt');
    }
    return region.code;
  }

  private async resolveAreaCode(input: unknown, current?: string | null) {
    if (input === undefined) return current ?? null;
    const code = this.normalizePersonnelCode(input, 'Mã Vùng không hợp lệ');
    if (!code) return null;
    const area = await this.prisma.areaDefinition.findUnique({
      where: { code },
    });
    if (!area || !area.isActive) {
      this.logger.warn(`Personnel validation failed: area=${code}`);
      throw new BadRequestException('Vùng không tồn tại hoặc đã tắt');
    }
    return area.code;
  }

  private async resolveOptionalAreaForRegion(
    input: unknown,
    current: string | null,
    regionCode: string,
  ) {
    const areaCode = await this.resolveAreaCode(input, current);
    if (!areaCode) {
      const defaultArea = await this.prisma.areaDefinition.findUnique({
        where: { code: regionCode },
      });
      return defaultArea?.regionCode === regionCode ? defaultArea.code : null;
    }
    const area = await this.prisma.areaDefinition.findUnique({
      where: { code: areaCode },
    });
    if (area?.regionCode !== regionCode) {
      throw new BadRequestException('Vùng không thuộc Miền đã chọn');
    }
    return area.code;
  }

  private async resolveAreaCodeForStore(input: unknown) {
    const code = this.normalizePersonnelCode(
      input || DEFAULT_REGION_CODE,
      'Mã Vùng không hợp lệ',
    );
    if (!code) return DEFAULT_REGION_CODE;
    const area = await this.prisma.areaDefinition.findUnique({
      where: { code },
    });
    if (!area || !area.isActive) {
      throw new BadRequestException('Vùng không tồn tại hoặc đã tắt');
    }
    return area.code;
  }

  private regionUserCountWhere(regionCode: string): Prisma.UserWhereInput {
    return {
      OR: [
        { AND: [{ regionCode }, { NOT: { workScopeType: STORE_SCOPE } }] },
        {
          AND: [
            { regionCode },
            { workScopeType: STORE_SCOPE },
            { storeId: null },
          ],
        },
        {
          workScopeType: STORE_SCOPE,
          store: { is: { area: { is: { regionCode } } } },
        },
      ],
    };
  }

  private areaUserCountWhere(areaCode: string): Prisma.UserWhereInput {
    return {
      OR: [
        { AND: [{ areaCode }, { NOT: { workScopeType: STORE_SCOPE } }] },
        {
          AND: [
            { areaCode },
            { workScopeType: STORE_SCOPE },
            { storeId: null },
          ],
        },
        { workScopeType: STORE_SCOPE, store: { is: { areaCode } } },
      ],
    };
  }

  private resolveWorkScopeType(
    input: unknown,
    current: string | null | undefined,
    role: string,
  ) {
    if (input === undefined) {
      const currentScope = String(current || '')
        .trim()
        .toUpperCase();
      return WORK_SCOPE_TYPES.has(currentScope)
        ? currentScope
        : this.defaultWorkScopeForRole(role);
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
    if (
      role === SUPER_ADMIN_ROLE ||
      role === ADMIN_ROLE ||
      role === ADMIN_ACARE_ROLE
    ) {
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
    store?: { storeId?: string | null; area?: any | null } | null;
    region?: any | null;
    area?: any | null;
  }) {
    const jobRoleCode = String(user.jobRoleCode || '')
      .trim()
      .toUpperCase();
    if (!jobRoleCode) return null;
    const scope = this.effectiveWorkScope(user);
    const area = this.areaForUser(user);
    const region = this.regionForUser(user);
    const areaAbbr = this.scopeAbbreviation(area?.abbreviation || area?.code);
    const regionAbbr = this.scopeAbbreviation(
      region?.abbreviation || region?.code,
    );
    if (scope === STORE_SCOPE) {
      const storeCode = this.scopeAbbreviation(user.store?.storeId || 'STORE');
      return `${jobRoleCode}_${storeCode}_${areaAbbr}_${regionAbbr}`;
    }
    if (scope === AREA_SCOPE) {
      return `${jobRoleCode}_${areaAbbr}_${areaAbbr}_${regionAbbr}`;
    }
    if (scope === REGION_SCOPE) {
      return `${jobRoleCode}_${regionAbbr}_${regionAbbr}_${regionAbbr}`;
    }
    return `${jobRoleCode}_NATIONAL_NATIONAL_NATIONAL`;
  }

  private areaForUser(user: any) {
    if (this.effectiveWorkScope(user) === STORE_SCOPE) {
      return user?.store?.area ?? user?.area ?? null;
    }
    return user?.area ?? user?.store?.area ?? null;
  }

  private regionForUser(user: any) {
    if (this.effectiveWorkScope(user) === STORE_SCOPE) {
      const storeArea = user?.store?.area ?? null;
      return storeArea?.region ?? user?.region ?? user?.area?.region ?? null;
    }
    const area = this.areaForUser(user);
    return user?.region ?? area?.region ?? user?.store?.area?.region ?? null;
  }

  private scopeAbbreviation(value?: string | null) {
    const code = String(value || DEFAULT_REGION_CODE)
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    return code || DEFAULT_REGION_CODE;
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

  private normalizeCatalogAbbreviation(value: unknown) {
    const abbreviation = String(value || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    if (!/^[A-Z0-9][A-Z0-9_]{0,39}$/.test(abbreviation)) {
      throw new BadRequestException('Viết tắt không hợp lệ');
    }
    return abbreviation;
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

  private isAcareAdmin(user: any) {
    return user?.role === ADMIN_ACARE_ROLE;
  }

  private isAcaretekEmail(email: unknown) {
    return String(email || '')
      .trim()
      .toLowerCase()
      .endsWith('@' + ACARETEK_EMAIL_DOMAIN);
  }

  private adminDomainScope(admin: any): Prisma.UserWhereInput {
    if (!this.isAcareAdmin(admin)) return {};
    return {
      email: {
        endsWith: '@' + ACARETEK_EMAIL_DOMAIN,
        mode: Prisma.QueryMode.insensitive,
      },
    };
  }

  private combineUserScope(
    domainScope: Prisma.UserWhereInput,
    locationScope: Prisma.UserWhereInput,
  ): Prisma.UserWhereInput {
    if (Object.keys(domainScope).length === 0) return locationScope;
    return { AND: [domainScope, locationScope] };
  }

  private adminDomainScopeLabel(admin: any) {
    return this.isAcareAdmin(admin) ? ACARETEK_EMAIL_DOMAIN : 'all';
  }

  private assertEmailWithinAdminDomain(admin: any, email: string) {
    if (!this.isAcareAdmin(admin) || this.isAcaretekEmail(email)) return;
    this.logger.warn(
      'Admin user create blocked by email domain: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' targetDomain=' +
        (email.split('@').pop() || 'invalid'),
    );
    throw new ForbiddenException(
      'ADMIN_ACARE chi duoc quan ly user domain acaretek.vn',
    );
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
    const scopeWhere = this.adminStoreScopeWhere(admin);

    if (queryWhere && scopeWhere) return { AND: [scopeWhere, queryWhere] };
    return queryWhere || scopeWhere;
  }

  private adminStoreScopeWhere(admin: any): Prisma.StoreWhereInput | undefined {
    if (!this.isScopedAdmin(admin)) return undefined;
    const scope = this.effectiveWorkScope(admin);
    if (scope === NATIONAL_SCOPE) return undefined;
    if (scope === REGION_SCOPE) {
      return admin.regionCode
        ? { area: { regionCode: admin.regionCode } }
        : { id: '__NO_REGION__' };
    }
    if (scope === AREA_SCOPE) {
      return admin.areaCode
        ? { areaCode: admin.areaCode }
        : { id: '__NO_AREA__' };
    }
    return { id: admin.storeId || '__NO_STORE__' };
  }

  private toStoreDto(store: any) {
    const area = store.area ?? null;
    const region = area?.region ?? null;
    return {
      id: store.id,
      storeId: store.storeId,
      storeName: store.storeName,
      areaCode: area?.code ?? store.areaCode ?? null,
      areaName: area?.displayName ?? null,
      areaAbbreviation: area?.abbreviation ?? null,
      regionCode: region?.code ?? null,
      regionName: region?.displayName ?? null,
      regionAbbreviation: region?.abbreviation ?? null,
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
