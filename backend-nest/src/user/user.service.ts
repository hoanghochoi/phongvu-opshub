import {
  BadRequestException,
  ForbiddenException,
  GoneException,
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
const USER_ROLE = 'USER';
const ADMIN_PHONGVU_ROLE = 'ADMIN_PHONGVU';
const ADMIN_ACARE_ROLE = 'ADMIN_ACARE';
const MANAGER_ROLE = 'MANAGER';
const STAFF_ROLE = 'STAFF';
const ACARE_EMAIL_DOMAIN = 'acare.vn';

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
const ORG_ROOT_ACARE_ID = 'org-domain-acare-vn';
const ORG_TYPE_LV0_DOMAIN = 'LV0_DOMAIN';
const ORG_TYPE_LV1_BLOCK = 'LV1_BLOCK';
const ORG_TYPE_LV2_DEPARTMENT = 'LV2_DEPARTMENT';
const ORG_TYPE_LV2_REGION = 'LV2_REGION';
const ORG_TYPE_LV3_AREA = 'LV3_AREA';
const ORG_TYPE_LV3_UNIT = 'LV3_UNIT';
const ORG_TYPE_LV4_STORE = 'LV4_STORE';
const ORG_TYPE_LV5_POSITION = 'LV5_POSITION';
const ORG_TYPES = new Set([
  ORG_TYPE_LV0_DOMAIN,
  ORG_TYPE_LV1_BLOCK,
  ORG_TYPE_LV2_DEPARTMENT,
  ORG_TYPE_LV2_REGION,
  ORG_TYPE_LV3_AREA,
  ORG_TYPE_LV3_UNIT,
  ORG_TYPE_LV4_STORE,
  ORG_TYPE_LV5_POSITION,
]);
const RUNTIME_ORG_TREE_NODE_TYPES = new Set([
  ORG_TYPE_LV0_DOMAIN,
  ORG_TYPE_LV4_STORE,
  ORG_TYPE_LV5_POSITION,
]);
const ORG_TYPE_LEVELS: Record<string, number> = {
  [ORG_TYPE_LV0_DOMAIN]: 0,
  [ORG_TYPE_LV1_BLOCK]: 1,
  [ORG_TYPE_LV2_DEPARTMENT]: 2,
  [ORG_TYPE_LV2_REGION]: 2,
  [ORG_TYPE_LV3_AREA]: 3,
  [ORG_TYPE_LV3_UNIT]: 3,
  [ORG_TYPE_LV4_STORE]: 4,
  [ORG_TYPE_LV5_POSITION]: 5,
};
const LEGACY_ORG_TYPE_ALIASES: Record<string, string | null> = {
  ROOT_DOMAIN: ORG_TYPE_LV0_DOMAIN,
  BLOCK: ORG_TYPE_LV1_BLOCK,
  DEPARTMENT: ORG_TYPE_LV2_DEPARTMENT,
  REGION: ORG_TYPE_LV2_REGION,
  AREA: ORG_TYPE_LV3_AREA,
  VIRTUAL_SCOPE: ORG_TYPE_LV3_UNIT,
  SHOWROOM: ORG_TYPE_LV4_STORE,
  JOB_ROLE: ORG_TYPE_LV5_POSITION,
  SUBDOMAIN: null,
};
const ROLE_ALIASES: Record<string, string> = {
  [ADMIN_PHONGVU_ROLE]: ADMIN_ROLE,
  [ADMIN_ACARE_ROLE]: ADMIN_ROLE,
  [MANAGER_ROLE]: ADMIN_ROLE,
  [STAFF_ROLE]: USER_ROLE,
};

const DEFAULT_ROLE_DEFINITIONS = [
  {
    code: SUPER_ADMIN_ROLE,
    displayName: 'Super Admin',
    description: 'Toàn quyền hệ thống',
  },
  {
    code: ADMIN_ROLE,
    displayName: 'Admin',
    description: 'Quản trị theo phạm vi cây tổ chức',
  },
  {
    code: USER_ROLE,
    displayName: 'User',
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
    code: 'SA',
    displayName: 'Nhân viên Bán hàng',
    description: 'Vị trí bán hàng tại cửa hàng',
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
    code: 'CASH',
    displayName: 'Nhân viên Thu ngân',
    description: 'Vị trí thu ngân tại cửa hàng',
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

const DEFAULT_STORE_POSITION_DEFINITIONS = [
  {
    suffix: 'STORE_MANAGER',
    businessCode: 'STORE_MANAGER',
    displayName: 'Quản lý Cửa hàng',
    description: 'Vị trí quản lý cửa hàng',
    departmentCode: 'MANAGEMENT',
    sortOrder: 10,
  },
  {
    suffix: 'SA',
    businessCode: 'SA',
    displayName: 'Nhân viên Bán hàng',
    description: 'Vị trí bán hàng tại cửa hàng',
    departmentCode: 'SALES',
    sortOrder: 20,
  },
  {
    suffix: 'TECHNICIAN',
    businessCode: 'TECHNICIAN',
    displayName: 'Kỹ thuật viên',
    description: 'Vị trí kỹ thuật tại cửa hàng',
    departmentCode: 'TECHNICAL',
    sortOrder: 30,
  },
  {
    suffix: 'CASH',
    businessCode: 'CASH',
    displayName: 'Nhân viên Thu ngân',
    description: 'Vị trí thu ngân tại cửa hàng',
    departmentCode: 'CASHIER',
    sortOrder: 40,
  },
  {
    suffix: 'WAREHOUSE',
    businessCode: 'WAREHOUSE',
    displayName: 'Nhân viên Kho',
    description: 'Vị trí kho tại cửa hàng',
    departmentCode: 'WAREHOUSE',
    sortOrder: 50,
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
    await this.syncStoreOrganizationNodes('module-init');
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
          String(row.role || USER_ROLE)
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
        const relationData = {
          storeUuid,
          regionCode: storeUuid ? DEFAULT_REGION_CODE : null,
          areaCode: storeUuid ? DEFAULT_REGION_CODE : null,
        };

        await this.prisma.user.upsert({
          where: { email },
          update: {
            firstName: firstName || undefined,
            lastName: lastName || undefined,
            role,
            status,
            workScopeType: this.defaultWorkScopeForRole(role),
            ...this.userRelationMutationData(relationData, {
              disconnectNulls: true,
            }),
          },
          create: {
            email,
            password: '',
            firstName: firstName || email.split('@')[0],
            lastName: lastName || null,
            role,
            status,
            workScopeType: this.defaultWorkScopeForRole(role),
            ...this.userRelationMutationData(relationData),
          },
        });

        syncedCount++;
      }

      this.logger.log(
        `User sync complete: ${syncedCount} users synced, ${storeCreatedCount} new stores created`,
      );
      if (storeCreatedCount > 0) {
        await this.syncStoreOrganizationNodes('bigquery-user-sync');
      }
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
    void userId;
    void storeCode;
    throw new GoneException(
      'Luồng tự chọn SR đã ngừng. Vui lòng liên hệ super_admin để được gán node tổ chức.',
    );
  }

  async adminListUsers(admin: any, filters: any = {}) {
    await this.assertAdmin(admin);
    const query = String(filters.q || '').trim();
    const scope = await this.adminScope(admin);
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
    await this.assertEmailWithinAdminDomain(admin, email);

    const role = await this.resolveAssignableRole(body.role || USER_ROLE);
    await this.assertRoleEditable(admin, role);
    const workScopeType = await this.resolveWorkScopeTypeForAssignment(
      body,
      null,
      role,
    );
    const storeUuid = await this.resolveUserAssignmentStoreUuid(admin, body, {
      workScopeType,
    });
    const personnel = await this.resolvePersonnelAssignment(admin, body, {
      role,
      storeUuid,
      workScopeType,
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
        workScopeType: personnel.workScopeType,
        ...this.userRelationMutationData({
          storeUuid,
          departmentCode: personnel.departmentCode,
          jobRoleCode: personnel.jobRoleCode,
          regionCode: personnel.regionCode,
          areaCode: personnel.areaCode,
          organizationNodeId: personnel.organizationNodeId,
        }),
        branchLockedAt: storeUuid ? new Date() : null,
        profileCompletedAt: storeUuid ? new Date() : null,
      },
      include: this.userDtoInclude(),
    });
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
      this.normalizeRoleCode(current.role) === SUPER_ADMIN_ROLE
    ) {
      throw new ForbiddenException('Không có quyền sửa tài khoản SUPER_ADMIN');
    }

    if (
      this.isScopedAdmin(admin) &&
      !(await this.userWithinAdminScope(admin, current))
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
      : this.normalizeRoleCode(current.role, true);
    await this.assertRoleEditable(admin, role, current.role);
    const workScopeType = await this.resolveWorkScopeTypeForAssignment(
      body,
      current,
      role,
    );
    const storeUuid = await this.resolveUserAssignmentStoreUuid(admin, body, {
      current,
      workScopeType,
    });
    const personnel = await this.resolvePersonnelAssignment(admin, body, {
      current,
      role,
      storeUuid,
      workScopeType,
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
        workScopeType: personnel.workScopeType,
        ...this.userRelationMutationData(
          {
            storeUuid,
            departmentCode: personnel.departmentCode,
            jobRoleCode: personnel.jobRoleCode,
            regionCode: personnel.regionCode,
            areaCode: personnel.areaCode,
            organizationNodeId: personnel.organizationNodeId,
          },
          { disconnectNulls: true },
        ),
        branchLockedAt: storeUuid
          ? (current.branchLockedAt ?? new Date())
          : null,
        profileCompletedAt: storeUuid
          ? (current.profileCompletedAt ?? new Date())
          : current.profileCompletedAt,
      },
      include: this.userDtoInclude(),
    });
    const saved = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.userDtoInclude(),
    });
    this.logger.log(
      `Admin user updated: id=${userId} role=${role} scope=${personnel.workScopeType} personnelCode=${this.personnelCodeFor(updated) ?? 'none'}`,
    );
    return this.toUserDto(saved ?? updated);
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

  async adminSetUserPassword(admin: any, userId: string, newPassword: string) {
    await this.assertAdmin(admin);
    const target = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.userDtoInclude(),
    });
    if (!target) throw new NotFoundException('Không tìm thấy user');

    if (
      this.normalizeRoleCode(target.role) === SUPER_ADMIN_ROLE &&
      this.normalizeRoleCode(admin.role) !== SUPER_ADMIN_ROLE
    ) {
      throw new ForbiddenException('Không được reset mật khẩu SUPER_ADMIN');
    }
    if (this.normalizeRoleCode(admin.role) !== SUPER_ADMIN_ROLE) {
      if (!this.isDomainAdmin(admin)) {
        throw new ForbiddenException('Không có quyền reset mật khẩu user');
      }
      if (!(await this.userWithinAdminScope(admin, target))) {
        throw new ForbiddenException(
          'Không có quyền reset mật khẩu user ngoài phạm vi quản lý',
        );
      }
    }

    this.logger.log(
      'Admin password reset started: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' targetUserId=' +
        userId +
        ' targetRole=' +
        target.role,
    );
    const result = await this.passwordResetService.setPasswordForUserId(
      userId,
      newPassword,
      { id: admin.id, email: admin.email },
    );
    this.logger.log(
      'Admin password reset completed: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' targetUserId=' +
        userId,
    );
    return result;
  }

  async adminListOrganizationTree(admin: any) {
    await this.assertAdmin(admin);
    return this.listOrganizationTreeForAdmin(
      admin,
      'admin-list-organization-tree',
    );
  }

  async adminListUserScopeTree(admin: any) {
    await this.assertAdmin(admin);
    return this.listOrganizationTreeForAdmin(
      admin,
      'admin-list-user-scope-tree',
    );
  }

  async adminListPolicyScopeTree(admin: any) {
    await this.assertAdmin(admin);
    return this.listOrganizationTreeForAdmin(
      admin,
      'admin-list-policy-scope-tree',
    );
  }

  private async listOrganizationTreeForAdmin(admin: any, source: string) {
    await this.seedDefaultOrganizationTree();
    await this.syncStoreOrganizationNodes(source);
    const where = await this.adminOrganizationNodeScopeWhere(admin);
    const nodes = await this.prisma.organizationNode.findMany({
      where: {
        AND: [
          { isActive: true },
          { type: { not: 'SUBDOMAIN' } },
          ...(where ? [where] : []),
        ],
      },
      orderBy: [{ sortOrder: 'asc' }, { type: 'asc' }, { displayName: 'asc' }],
      include: {
        stores: { take: 1, orderBy: { storeId: 'asc' } },
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
    return nodes.map((node) => this.toOrganizationNodeDto(node));
  }

  async adminCreateOrganizationNode(admin: any, body: any) {
    await this.assertSuperAdmin(admin);
    const data = await this.normalizeOrganizationNodeInput(body);
    const node = await this.prisma.$transaction(async (tx) => {
      const created = await tx.organizationNode.create({ data });
      if (this.isLegacyCatalogNodeType(created.type)) {
        await this.syncLegacyCatalogFromOrganizationNode(tx, created);
      }
      if (this.isStoreNodeType(created.type)) {
        await this.syncShowroomStoreFromNode(tx, created, body, null);
      }
      return this.findOrganizationNodeForDto(tx, created.id);
    });
    this.logger.log(
      `Organization node created: admin=${admin?.email || admin?.id || 'unknown'} nodeId=${node.id} type=${node.type} code=${node.code}`,
    );
    return node;
  }

  async adminUpdateOrganizationNode(admin: any, id: string, body: any) {
    const current = await this.prisma.organizationNode.findUnique({
      where: { id },
      include: { stores: { take: 1, orderBy: { storeId: 'asc' } } },
    });
    if (!current) throw new NotFoundException('Không tìm thấy node tổ chức');

    if (this.isDomainAdmin(admin) && this.isStoreNodeType(current.type)) {
      return this.updateShowroomMapCredentialFromTree(admin, current, body);
    }

    await this.assertSuperAdmin(admin);
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
    const node = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.organizationNode.update({
        where: { id },
        data,
      });
      if (this.isLegacyCatalogNodeType(updated.type)) {
        await this.syncLegacyCatalogFromOrganizationNode(tx, updated);
      }
      if (this.isStoreNodeType(updated.type)) {
        await this.syncShowroomStoreFromNode(tx, updated, body, current);
      }
      return this.findOrganizationNodeForDto(tx, id);
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
    const references = await this.organizationNodeReferenceCounts(id);
    const blockers: string[] = [];
    if (node._count.children > 0) {
      blockers.push(node._count.children + ' node con');
    }
    if (references.users > 0) blockers.push(references.users + ' user');
    if (references.stores > 0) blockers.push(references.stores + ' SR');
    if (references.departments > 0) {
      blockers.push(references.departments + ' phòng ban');
    }
    if (references.jobRoles > 0) {
      blockers.push(references.jobRoles + ' chức danh');
    }
    if (references.regions > 0) blockers.push(references.regions + ' Miền');
    if (references.areas > 0) blockers.push(references.areas + ' Vùng');
    if (references.featureRules > 0) {
      blockers.push(references.featureRules + ' rule tính năng');
    }
    if (references.nodeFeatureAssignments > 0) {
      blockers.push(
        references.nodeFeatureAssignments + ' quyền tính năng node',
      );
    }
    if (references.policyRules > 0) {
      blockers.push(references.policyRules + ' rule policy');
    }
    if (blockers.length > 0) {
      this.logger.warn(
        'Organization node delete blocked: admin=' +
          (admin?.email || admin?.id || 'unknown') +
          ' nodeId=' +
          id +
          ' blockers=' +
          blockers.join('|'),
      );
      throw new BadRequestException(
        'Không thể xóa node tổ chức vì còn ' + blockers.join(', '),
      );
    }
    await this.prisma.organizationNode.delete({ where: { id } });
    this.logger.warn(
      'Organization node deleted: admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' nodeId=' +
        id,
    );
    return { deleted: true, id };
  }

  private async normalizeOrganizationNodeInput(input: any, current?: any) {
    const type = this.normalizeOrganizationNodeType(
      input.type ?? current?.type,
    );
    if (!RUNTIME_ORG_TREE_NODE_TYPES.has(type)) {
      throw new BadRequestException(
        'Cây tổ chức runtime chỉ hỗ trợ Lv0 Domain, Lv4 Cửa hàng và Lv5 Vị trí',
      );
    }
    const displayName = this.normalizeRequiredText(
      input.displayName ?? input.storeName ?? current?.displayName,
      'Tên node tổ chức không được để trống',
      120,
    );
    const emailDomain = this.isDomainNodeType(type)
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
    const businessCode = this.normalizeOrganizationBusinessCode(
      input.businessCode ??
        input.storeId ??
        current?.businessCode ??
        input.code,
      type,
    );
    const code = input.code
      ? this.normalizeOrganizationNodeCode(input.code)
      : (current?.code ??
        (await this.organizationCodeFor(
          type,
          businessCode ?? emailDomain ?? displayName,
          parentId,
        )));
    return {
      code,
      displayName,
      businessCode,
      abbreviation: this.normalizeOptionalText(
        input.abbreviation ?? current?.abbreviation,
        40,
      ),
      description: this.normalizeOptionalText(
        input.description ?? current?.description,
        180,
      ),
      type,
      parentId,
      emailDomain,
      loginAllowed: this.isDomainNodeType(type)
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
    const rawType = String(value || '')
      .trim()
      .toUpperCase();
    const type = LEGACY_ORG_TYPE_ALIASES.hasOwnProperty(rawType)
      ? LEGACY_ORG_TYPE_ALIASES[rawType]
      : rawType;
    if (!type) {
      throw new BadRequestException(
        'Sub-domain đã được gộp vào Lv0 domain, vui lòng chọn node Lv0-Lv5',
      );
    }
    if (!ORG_TYPES.has(type)) {
      throw new BadRequestException('Loại node tổ chức không hợp lệ');
    }
    return type;
  }

  private organizationNodeLevel(type: string) {
    const normalizedType = this.normalizeOrganizationNodeType(type);
    return ORG_TYPE_LEVELS[normalizedType];
  }

  private isDomainNodeType(type: string) {
    return this.normalizeOrganizationNodeType(type) === ORG_TYPE_LV0_DOMAIN;
  }

  private isStoreNodeType(type: string) {
    return this.normalizeOrganizationNodeType(type) === ORG_TYPE_LV4_STORE;
  }

  private isLegacyRegionNodeType(type: string) {
    return this.normalizeOrganizationNodeType(type) === ORG_TYPE_LV2_REGION;
  }

  private isLegacyAreaNodeType(type: string) {
    return this.normalizeOrganizationNodeType(type) === ORG_TYPE_LV3_AREA;
  }

  private isLegacyDepartmentNodeType(type: string) {
    return this.normalizeOrganizationNodeType(type) === ORG_TYPE_LV2_DEPARTMENT;
  }

  private isLegacyPositionNodeType(type: string) {
    return this.normalizeOrganizationNodeType(type) === ORG_TYPE_LV5_POSITION;
  }

  private isLegacyCatalogNodeType(type: string) {
    return (
      this.isLegacyRegionNodeType(type) ||
      this.isLegacyAreaNodeType(type) ||
      this.isLegacyDepartmentNodeType(type) ||
      this.isLegacyPositionNodeType(type)
    );
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

  private normalizeOrganizationBusinessCode(value: unknown, type: string) {
    const text = String(value || '').trim();
    if (!text) {
      if (
        [ORG_TYPE_LV2_REGION, ORG_TYPE_LV3_AREA, ORG_TYPE_LV4_STORE].includes(
          type,
        )
      ) {
        throw new BadRequestException('Mã nghiệp vụ không được để trống');
      }
      return null;
    }
    const maxLength = type === ORG_TYPE_LV4_STORE ? 40 : 80;
    return text.slice(0, maxLength);
  }

  private async organizationCodeFor(
    type: string,
    value: string,
    parentId?: string | null,
  ) {
    const normalized = this.normalizeOrganizationNodeCode(
      String(value).replace(/\.[a-z]+$/i, ''),
    );
    if (type === ORG_TYPE_LV4_STORE) return 'STORE_' + normalized;
    if ([ORG_TYPE_LV2_REGION, ORG_TYPE_LV3_AREA].includes(type)) {
      const prefix = await this.organizationDomainPrefixForParent(parentId);
      return `${type}_${prefix}_${normalized}`;
    }
    return this.normalizeOrganizationNodeCode(`${type}_${normalized}`);
  }

  private async organizationDomainPrefixForParent(parentId?: string | null) {
    if (!parentId) return 'PHONGVU';
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return 'PHONGVU';
    const nodes: Array<{ id: string; parentId: string | null }> =
      await organizationNode.findMany({ select: { id: true, parentId: true } });
    const byId = new Map(nodes.map((node) => [node.id, node]));
    let cursor = byId.get(parentId) ?? null;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      if (cursor.id === ORG_ROOT_ACARE_ID) return 'ACARE';
      if (cursor.id === ORG_ROOT_PHONGVU_ID) return 'PHONGVU';
      cursor = cursor.parentId ? (byId.get(cursor.parentId) ?? null) : null;
    }
    return parentId === ORG_ROOT_ACARE_ID ? 'ACARE' : 'PHONGVU';
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
    if (type === ORG_TYPE_LV0_DOMAIN) return null;
    const parentId = String(parentIdInput ?? current?.parentId ?? '').trim();
    if (!parentId) {
      throw new BadRequestException('Node cha không được để trống');
    }
    const parent = await this.prisma.organizationNode.findUnique({
      where: { id: parentId },
      select: { id: true, type: true, isActive: true },
    });
    if (!parent || !parent.isActive) {
      throw new BadRequestException('Node cha không hợp lệ');
    }
    this.assertOrganizationParentType(type, parent.type);
    return parent.id;
  }

  private assertOrganizationParentType(type: string, parentType: string) {
    const childType = this.normalizeOrganizationNodeType(type);
    const normalizedParentType = this.normalizeOrganizationNodeType(parentType);
    if (
      childType === ORG_TYPE_LV4_STORE &&
      normalizedParentType === ORG_TYPE_LV0_DOMAIN
    )
      return;
    if (
      childType === ORG_TYPE_LV5_POSITION &&
      normalizedParentType === ORG_TYPE_LV4_STORE
    )
      return;
    throw new BadRequestException(
      `${this.organizationNodeTypeLabel(type)} phải nằm dưới node cấp cao hơn`,
    );
  }

  private organizationNodeTypeLabel(type: string) {
    const labels: Record<string, string> = {
      [ORG_TYPE_LV0_DOMAIN]: 'Lv0 Domain',
      [ORG_TYPE_LV1_BLOCK]: 'Lv1 Khối',
      [ORG_TYPE_LV2_DEPARTMENT]: 'Lv2 Phòng/Bộ phận',
      [ORG_TYPE_LV2_REGION]: 'Lv2 Miền',
      [ORG_TYPE_LV3_AREA]: 'Lv3 Vùng',
      [ORG_TYPE_LV3_UNIT]: 'Lv3 Bộ phận',
      [ORG_TYPE_LV4_STORE]: 'Lv4 Cửa hàng',
      [ORG_TYPE_LV5_POSITION]: 'Lv5 Vị trí',
    };
    const normalizedType = this.normalizeOrganizationNodeType(type);
    return labels[normalizedType] ?? normalizedType;
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

  private async organizationNodeReferenceCounts(id: string) {
    const [
      users,
      stores,
      departments,
      jobRoles,
      regions,
      areas,
      featureRules,
      nodeFeatureAssignments,
      policyRules,
    ] = await Promise.all([
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
      this.prisma.featureAccessRule.count({
        where: { organizationNodeId: id },
      }),
      (this.prisma as any).organizationNodeFeatureAssignment?.count
        ? (this.prisma as any).organizationNodeFeatureAssignment.count({
            where: { scopeRootNodeId: id },
          })
        : Promise.resolve(0),
      this.prisma.adminPolicyRule.count({
        where: { organizationNodeId: id },
      }),
    ]);
    return {
      users,
      stores,
      departments,
      jobRoles,
      regions,
      areas,
      featureRules,
      nodeFeatureAssignments,
      policyRules,
    };
  }

  private toOrganizationNodeDto(node: any) {
    const store = Array.isArray(node.stores) ? node.stores[0] : null;
    const type = this.normalizeOrganizationNodeType(node.type);
    const isStore = type === ORG_TYPE_LV4_STORE;
    return {
      id: node.id,
      code: node.code,
      displayName: node.displayName,
      businessCode: node.businessCode ?? null,
      abbreviation: node.abbreviation ?? null,
      description: node.description ?? null,
      type,
      level: this.organizationNodeLevel(type),
      parentId: node.parentId ?? null,
      emailDomain: node.emailDomain ?? null,
      loginAllowed: node.loginAllowed === true,
      isSystem: node.isSystem === true,
      isActive: node.isActive !== false,
      sortOrder: node.sortOrder ?? 0,
      storeId: isStore ? (store?.storeId ?? node.businessCode ?? null) : null,
      storeName: isStore ? (store?.storeName ?? node.displayName) : null,
      transferAccountNumber: store?.transferAccountNumber ?? null,
      transferAccountName: store?.transferAccountName ?? null,
      transferBankName: store?.transferBankName ?? null,
      transferBankBin: store?.transferBankBin ?? null,
      mapVietinUsername: store?.mapVietinUsername ?? null,
      hasMapVietinPassword: Boolean(store?.mapVietinPasswordCipher),
      _count: node._count,
    };
  }

  private async toRegionShimDto(node: any) {
    const descendantIds = await this.organizationDescendantIds(node.id);
    const [areaCount, storeCount, userCount, featureRules] = await Promise.all([
      this.prisma.organizationNode.count({
        where: { parentId: node.id, type: ORG_TYPE_LV3_AREA },
      }),
      this.prisma.store.count({
        where: { organizationNodeId: { in: descendantIds } },
      }),
      this.prisma.user.count({
        where: (await this.userOrganizationNodeWhere(node.id)) ?? {
          organizationNodeId: node.id,
        },
      }),
      this.prisma.featureAccessRule.count({
        where: { organizationNodeId: node.id },
      }),
    ]);
    const code =
      node.businessCode ?? this.legacyCodeFromOrganizationCode(node.code);
    return {
      id: node.id,
      code,
      displayName: node.displayName,
      abbreviation: node.abbreviation ?? code,
      description: node.description ?? '',
      organizationNodeId: node.id,
      isSystem: node.isSystem === true,
      isActive: node.isActive !== false,
      _count: {
        areas: areaCount,
        stores: storeCount,
        users: userCount,
        featureAccessRules: featureRules,
      },
    };
  }

  private async toAreaShimDto(node: any) {
    const parent = node.parentId
      ? await this.prisma.organizationNode.findUnique({
          where: { id: node.parentId },
        })
      : null;
    const code =
      node.businessCode ?? this.legacyCodeFromOrganizationCode(node.code);
    const regionCode = parent
      ? (parent.businessCode ??
        this.legacyCodeFromOrganizationCode(parent.code))
      : '';
    const [storeCount, userCount, featureRules] = await Promise.all([
      this.prisma.store.count({ where: { organizationNodeId: node.id } }),
      this.prisma.user.count({
        where: (await this.userOrganizationNodeWhere(node.id)) ?? {
          organizationNodeId: node.id,
        },
      }),
      this.prisma.featureAccessRule.count({
        where: { organizationNodeId: node.id },
      }),
    ]);
    return {
      id: node.id,
      code,
      displayName: node.displayName,
      abbreviation: node.abbreviation ?? code,
      description: node.description ?? '',
      regionCode,
      region: parent
        ? {
            id: parent.id,
            code: regionCode,
            displayName: parent.displayName,
            abbreviation: parent.abbreviation ?? regionCode,
          }
        : null,
      organizationNodeId: node.id,
      isSystem: node.isSystem === true,
      isActive: node.isActive !== false,
      _count: {
        stores: storeCount,
        users: userCount,
        featureAccessRules: featureRules,
      },
    };
  }

  private async findOrganizationNodeForDto(client: any, id: string) {
    const node = await client.organizationNode.findUnique({
      where: { id },
      include: {
        stores: { take: 1, orderBy: { storeId: 'asc' } },
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
    if (!node) throw new NotFoundException('Không tìm thấy node tổ chức');
    return this.toOrganizationNodeDto(node);
  }

  private async syncShowroomStoreFromNode(
    client: any,
    node: any,
    body: any,
    previousNode?: any | null,
  ) {
    const location = await this.organizationLocationForShowroomNode(
      client,
      node,
    );
    const storeCode = this.normalizeStoreCode(
      body.storeId || body.businessCode || node.businessCode,
    );
    const storeName = this.normalizeRequiredText(
      body.storeName || body.displayName || node.displayName,
      'Tên store không được để trống',
      120,
    );
    let currentStore = Array.isArray(previousNode?.stores)
      ? previousNode.stores[0]
      : null;
    if (!currentStore) {
      currentStore = await client.store.findFirst({
        where: { organizationNodeId: node.id },
      });
    }
    if (!currentStore) {
      const existing = await client.store.findUnique({
        where: { storeId: storeCode },
      });
      if (
        existing?.organizationNodeId &&
        existing.organizationNodeId !== node.id
      ) {
        throw new BadRequestException('SR đã được gắn với node tổ chức khác');
      }
      currentStore = existing;
    }
    if (currentStore && currentStore.storeId !== storeCode) {
      const duplicate = await client.store.findUnique({
        where: { storeId: storeCode },
      });
      if (duplicate && duplicate.id !== currentStore.id) {
        throw new BadRequestException('Store đã tồn tại');
      }
    }

    const data = {
      storeId: storeCode,
      storeName,
      areaCode: location.areaCode ?? currentStore?.areaCode ?? null,
      organizationNodeId: node.id,
      ...this.normalizeStorePaymentFields(body),
      ...this.normalizeMapVietinFields(body),
    };
    const store = currentStore
      ? await client.store.update({
          where: { id: currentStore.id },
          data,
        })
      : await client.store.create({ data });

    await this.ensureDefaultStorePositionNodes(client, node);
    const defaultUserNodeId = await this.defaultStoreCashNodeIdForClient(
      client,
      node.id,
    );
    const storeSubtreeIds = await this.organizationDescendantIdsForClient(
      client,
      node.id,
    );

    await client.user.updateMany({
      where: {
        storeId: store.id,
        workScopeType: STORE_SCOPE,
        OR: [
          { organizationNodeId: null },
          { organizationNodeId: { notIn: storeSubtreeIds } },
        ],
      },
      data: {
        organizationNodeId: defaultUserNodeId ?? node.id,
        jobRoleCode: 'CASH',
        areaCode: location.areaCode ?? store.areaCode ?? null,
        regionCode: location.regionCode,
      },
    });
    return store;
  }

  private async syncLegacyCatalogFromOrganizationNode(client: any, node: any) {
    const businessCode = this.normalizePersonnelCode(
      node.businessCode || this.legacyCodeFromOrganizationCode(node.code),
      'Mã nghiệp vụ không hợp lệ',
    );
    if (!businessCode)
      throw new BadRequestException('Mã nghiệp vụ không hợp lệ');
    const displayName = this.normalizeRequiredText(
      node.displayName,
      'Tên node tổ chức không được để trống',
      120,
    );
    const abbreviation = this.normalizeCatalogAbbreviation(
      node.abbreviation || businessCode,
    );
    if (this.isLegacyDepartmentNodeType(node.type)) {
      await client.departmentDefinition.upsert({
        where: { code: businessCode },
        update: {
          displayName,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isActive: node.isActive !== false,
        },
        create: {
          code: businessCode,
          displayName,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isSystem: node.isSystem === true,
          isActive: node.isActive !== false,
        },
      });
      return;
    }
    if (this.isLegacyPositionNodeType(node.type)) {
      const departmentCode = await this.departmentCodeForPositionNode(
        client,
        node,
      );
      await client.jobRoleDefinition.upsert({
        where: { code: businessCode },
        update: {
          displayName,
          description: node.description ?? null,
          departmentCode,
          isActive: node.isActive !== false,
        },
        create: {
          code: businessCode,
          displayName,
          description: node.description ?? null,
          departmentCode,
          organizationNodeId: null,
          isSystem: node.isSystem === true,
          isActive: node.isActive !== false,
        },
      });
      return;
    }
    if (this.isLegacyRegionNodeType(node.type)) {
      await client.regionDefinition.upsert({
        where: { code: businessCode },
        update: {
          displayName,
          abbreviation,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isActive: node.isActive !== false,
        },
        create: {
          code: businessCode,
          displayName,
          abbreviation,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isSystem: node.isSystem === true,
          isActive: node.isActive !== false,
        },
      });
      return;
    }
    if (!this.isLegacyAreaNodeType(node.type)) return;
    const parent = node.parentId
      ? await client.organizationNode.findUnique({
          where: { id: node.parentId },
        })
      : null;
    if (!parent || !this.isLegacyRegionNodeType(parent.type)) {
      throw new BadRequestException('Vùng phải nằm dưới Miền');
    }
    await this.syncLegacyCatalogFromOrganizationNode(client, parent);
    const regionCode = this.normalizePersonnelCode(
      parent.businessCode || this.legacyCodeFromOrganizationCode(parent.code),
      'Mã Miền không hợp lệ',
    );
    if (!regionCode) throw new BadRequestException('Mã Miền không hợp lệ');
    await client.areaDefinition.upsert({
      where: { code: businessCode },
      update: {
        displayName,
        abbreviation,
        description: node.description ?? null,
        regionCode,
        organizationNodeId: node.id,
        isActive: node.isActive !== false,
      },
      create: {
        code: businessCode,
        displayName,
        abbreviation,
        description: node.description ?? null,
        regionCode,
        organizationNodeId: node.id,
        isSystem: node.isSystem === true,
        isActive: node.isActive !== false,
      },
    });
  }

  private async ensureDefaultStorePositionNodes(client: any, storeNode: any) {
    const organizationNode = client.organizationNode;
    if (!organizationNode?.upsert) return;
    const storeCode = this.normalizeStoreCode(
      storeNode.businessCode ||
        this.legacyCodeFromOrganizationCode(storeNode.code),
    );
    for (const position of DEFAULT_STORE_POSITION_DEFINITIONS) {
      const code = this.normalizeOrganizationNodeCode(
        `STORE_${storeCode}_POS_${position.suffix}`,
      );
      const data = {
        code,
        displayName: position.displayName,
        businessCode: position.businessCode,
        abbreviation: position.businessCode,
        description: position.description,
        type: ORG_TYPE_LV5_POSITION,
        parentId: storeNode.id,
        emailDomain: null,
        loginAllowed: false,
        isSystem: true,
        isActive: storeNode.isActive !== false,
        sortOrder: position.sortOrder,
      };
      const existing = organizationNode.findFirst
        ? await organizationNode.findFirst({
            where: {
              parentId: storeNode.id,
              type: ORG_TYPE_LV5_POSITION,
              businessCode: position.businessCode,
            },
          })
        : null;
      const node = existing?.id
        ? await organizationNode.update({
            where: { id: existing.id },
            data,
          })
        : await organizationNode.upsert({
            where: { code },
            update: data,
            create: data,
          });
      await this.syncLegacyCatalogFromOrganizationNode(client, node);
    }
  }

  private async defaultStoreCashNodeIdForClient(
    client: any,
    storeNodeId?: string | null,
  ) {
    if (!storeNodeId) return null;
    const organizationNode = client.organizationNode;
    if (!organizationNode?.findFirst) return storeNodeId;
    const cashNode = await organizationNode.findFirst({
      where: {
        parentId: storeNodeId,
        type: ORG_TYPE_LV5_POSITION,
        businessCode: 'CASH',
        isActive: true,
      },
      select: { id: true },
    });
    return cashNode?.id ?? storeNodeId;
  }

  private async defaultStoreCashNodeIdForStore(store: any) {
    return this.defaultStoreCashNodeIdForClient(
      this.prisma,
      store?.organizationNodeId ?? null,
    );
  }

  private async organizationDescendantIdsForClient(
    client: any,
    rootId: string,
  ) {
    const organizationNode = client.organizationNode;
    if (!organizationNode?.findMany) return [rootId];
    const nodes: Array<{ id: string; parentId: string | null }> =
      await organizationNode.findMany({
        select: { id: true, parentId: true },
      });
    const children = new Map<string, string[]>();
    for (const node of nodes) {
      if (!node.parentId) continue;
      const list = children.get(node.parentId) ?? [];
      list.push(node.id);
      children.set(node.parentId, list);
    }
    const result: string[] = [];
    const queue = [rootId];
    for (let guard = 0; queue.length > 0 && guard < 10000; guard += 1) {
      const current = queue.shift()!;
      if (result.includes(current)) continue;
      result.push(current);
      queue.push(...(children.get(current) ?? []));
    }
    return result;
  }

  private async departmentCodeForPositionNode(client: any, node: any) {
    const defaultPosition = DEFAULT_STORE_POSITION_DEFINITIONS.find(
      (position) => position.businessCode === node.businessCode,
    );
    const ancestorDepartment = await this.nearestAncestorNodeOfType(
      client,
      node,
      ORG_TYPE_LV2_DEPARTMENT,
    );
    if (ancestorDepartment) {
      await this.syncLegacyCatalogFromOrganizationNode(
        client,
        ancestorDepartment,
      );
      return this.legacyPersonnelCodeFromOrganizationNode(
        ancestorDepartment,
        'Mã phòng ban không hợp lệ',
      );
    }
    return defaultPosition?.departmentCode ?? null;
  }

  private async nearestAncestorNodeOfType(
    client: any,
    node: any,
    type: string,
  ) {
    const organizationNode = client.organizationNode;
    if (!organizationNode?.findUnique) return null;
    let parentId = node.parentId;
    for (let guard = 0; parentId && guard < 50; guard += 1) {
      const parent = await organizationNode.findUnique({
        where: { id: parentId },
      });
      if (!parent) return null;
      if (this.normalizeOrganizationNodeType(parent.type) === type) {
        return parent;
      }
      parentId = parent.parentId;
    }
    return null;
  }

  private async updateShowroomMapCredentialFromTree(
    admin: any,
    node: any,
    body: any,
  ) {
    const store = Array.isArray(node.stores) ? node.stores[0] : null;
    if (!store) throw new BadRequestException('Showroom chưa được gắn SR');
    if (!(await this.storeWithinAdminScope(admin, store))) {
      throw new ForbiddenException('Không có quyền sửa showroom khác');
    }
    const protectedChanges = this.scopedShowroomProtectedChanges(
      body,
      node,
      store,
    );
    if (protectedChanges.length > 0) {
      throw new ForbiddenException(
        'ADMIN theo phạm vi chỉ được sửa tài khoản/pass MAP; không được sửa ' +
          protectedChanges.join(', '),
      );
    }
    const mapData = this.normalizeMapVietinFields(body);
    if (Object.keys(mapData).length > 0) {
      await this.prisma.store.update({
        where: { id: store.id },
        data: mapData,
      });
    }
    this.logger.log(
      'Showroom MAP credential updated from tree: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' nodeId=' +
        node.id +
        ' store=' +
        store.storeId +
        ' mapUsernameChanged=' +
        (body.mapVietinUsername !== undefined) +
        ' mapPasswordProvided=' +
        Boolean(String(body.mapVietinPassword || '').trim()),
    );
    return this.findOrganizationNodeForDto(this.prisma, node.id);
  }

  private scopedShowroomProtectedChanges(body: any, node: any, store: any) {
    const changes: string[] = [];
    const compareText = (
      key: string,
      currentValue: unknown,
      label: string,
      maxLength: number,
    ) => {
      if (body[key] === undefined) return;
      const nextValue =
        this.normalizeOptionalText(body[key], maxLength) ?? null;
      const currentText = currentValue === undefined ? null : currentValue;
      if (nextValue !== currentText) changes.push(label);
    };
    compareText('code', node.code, 'mã node', 80);
    compareText('businessCode', node.businessCode, 'mã SR', 80);
    compareText('storeId', store.storeId, 'mã SR', 80);
    compareText('displayName', node.displayName, 'tên showroom', 120);
    compareText('storeName', store.storeName, 'tên SR', 120);
    compareText('parentId', node.parentId, 'Vùng/Miền', 80);
    compareText(
      'transferAccountNumber',
      store.transferAccountNumber,
      'số tài khoản nhận tiền',
      80,
    );
    compareText(
      'transferAccountName',
      store.transferAccountName,
      'tên tài khoản nhận tiền',
      120,
    );
    compareText(
      'transferBankName',
      store.transferBankName,
      'ngân hàng nhận tiền',
      80,
    );
    compareText('transferBankBin', store.transferBankBin, 'BIN ngân hàng', 20);
    if (
      body.isActive !== undefined &&
      (body.isActive === true) !== node.isActive
    ) {
      changes.push('trạng thái');
    }
    if (body.sortOrder !== undefined) {
      const sortOrder = this.normalizeSortOrder(body.sortOrder);
      if (sortOrder !== (node.sortOrder ?? 0)) changes.push('thứ tự');
    }
    return Array.from(new Set(changes));
  }

  private async organizationLocationForShowroomNode(client: any, node: any) {
    if (!this.isStoreNodeType(node.type)) {
      return {
        areaCode: null as string | null,
        regionCode: null as string | null,
      };
    }
    const nodes: Array<{
      id: string;
      parentId: string | null;
      type: string;
      code: string;
      businessCode: string | null;
    }> = await client.organizationNode.findMany({
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
      },
    });
    const byId = new Map(nodes.map((item) => [item.id, item]));
    const ancestors: typeof nodes = [];
    let cursor = byId.get(node.id) ?? node;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      ancestors.push(cursor);
      cursor = cursor.parentId ? (byId.get(cursor.parentId) ?? null) : null;
    }
    const areaNode = ancestors.find((item) =>
      this.isLegacyAreaNodeType(item.type),
    );
    const regionNode = ancestors.find((item) =>
      this.isLegacyRegionNodeType(item.type),
    );
    return {
      areaCode: this.legacyPersonnelCodeFromOrganizationNode(
        areaNode,
        'Mã Vùng không hợp lệ',
      ),
      regionCode: this.legacyPersonnelCodeFromOrganizationNode(
        regionNode,
        'Mã Miền không hợp lệ',
      ),
    };
  }

  private legacyPersonnelCodeFromOrganizationNode(
    node:
      | {
          businessCode?: string | null;
          code: string;
        }
      | null
      | undefined,
    message: string,
  ) {
    if (!node) return null;
    return this.normalizePersonnelCode(
      node.businessCode || this.legacyCodeFromOrganizationCode(node.code),
      message,
    );
  }

  private legacyCodeFromOrganizationCode(code: string) {
    return String(code || '')
      .replace(/^(LV2_REGION|LV3_AREA|REGION|AREA)_(PHONGVU|ACARE)_/i, '')
      .replace(/^STORE_/i, '')
      .trim()
      .toUpperCase();
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
      !(await this.storeWithinAdminScope(admin, store))
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
    const current = currentRole ? this.normalizeRoleCode(currentRole) : null;
    if (current && role === current) {
      return;
    }
    if (!currentRole && role === USER_ROLE) {
      return;
    }
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_USER_ROLE_EDIT,
      'Không có quyền sửa role',
    );
  }

  private async adminScope(admin: any) {
    if (this.isScopedAdmin(admin)) {
      const scope = this.effectiveWorkScope(admin);
      const domainScope = await this.adminDomainScope(admin);
      if (scope === NATIONAL_SCOPE) return domainScope;
      if (admin.organizationNodeId) {
        const organizationScope = await this.userOrganizationNodeWhere(
          admin.organizationNodeId,
        );
        if (organizationScope) {
          return this.combineUserScope(domainScope, organizationScope);
        }
      }
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
    return this.isDomainAdmin(user);
  }

  private isDomainAdmin(user: any) {
    return this.normalizeRoleCode(user?.role) === ADMIN_ROLE;
  }

  private isPhongVuAdmin(user: any) {
    return this.adminOrgRootId(user) === ORG_ROOT_PHONGVU_ID;
  }

  private adminOrgRootId(admin: any) {
    if (this.normalizeRoleCode(admin?.role) !== ADMIN_ROLE) return null;
    if (admin?.organizationNodeId === ORG_ROOT_ACARE_ID)
      return ORG_ROOT_ACARE_ID;
    if (admin?.organizationNodeId === ORG_ROOT_PHONGVU_ID)
      return ORG_ROOT_PHONGVU_ID;
    if (this.isAcaretekEmail(admin?.email)) return ORG_ROOT_ACARE_ID;
    return ORG_ROOT_PHONGVU_ID;
  }

  private async organizationDescendantIds(rootId: string) {
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return [rootId];
    const nodes: Array<{ id: string; parentId: string | null }> =
      await organizationNode.findMany({ select: { id: true, parentId: true } });
    const ids = new Set<string>([rootId]);
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
    return Array.from(ids);
  }

  private async organizationUserScopeForRoot(rootId: string) {
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany)
      return this.fallbackUserDomainScope(rootId);
    return (
      (await this.userOrganizationNodeWhere(rootId)) ??
      this.fallbackUserDomainScope(rootId)
    );
  }

  private fallbackUserDomainScope(rootId: string): Prisma.UserWhereInput {
    const insensitive = Prisma.QueryMode.insensitive;
    if (rootId === ORG_ROOT_ACARE_ID) {
      return {
        email: { endsWith: '@' + ACARE_EMAIL_DOMAIN, mode: insensitive },
      };
    }
    if (rootId === ORG_ROOT_PHONGVU_ID) {
      return {
        OR: [
          { email: { endsWith: '@phongvu.vn', mode: insensitive } },
          { email: { contains: '@phongvu-', mode: insensitive } },
        ],
      };
    }
    return {};
  }

  private async adminStoreOrganizationScope(
    admin: any,
  ): Promise<Prisma.StoreWhereInput | undefined> {
    const rootId = this.adminOrgRootId(admin);
    if (!rootId) return undefined;
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return undefined;
    const organizationNodeIds = await this.organizationDescendantIds(rootId);
    return { organizationNodeId: { in: organizationNodeIds } };
  }

  private async adminOrganizationNodeScopeWhere(
    admin: any,
  ): Promise<Prisma.OrganizationNodeWhereInput | undefined> {
    const rootId = this.adminOrgRootId(admin);
    if (!rootId) return undefined;
    const organizationNodeIds = await this.organizationDescendantIds(rootId);
    return { id: { in: organizationNodeIds } };
  }

  private combineStoreScope(
    organizationScope: Prisma.StoreWhereInput | undefined,
    locationScope: Prisma.StoreWhereInput | undefined,
  ): Prisma.StoreWhereInput | undefined {
    if (organizationScope && locationScope) {
      return { AND: [organizationScope, locationScope] };
    }
    return organizationScope || locationScope;
  }

  private async storeWithinAdminScope(admin: any, store: any) {
    const organizationScope = await this.adminStoreOrganizationScope(admin);
    if (organizationScope) {
      const organizationNodeIds = (organizationScope.organizationNodeId as any)
        ?.in as string[] | undefined;
      if (
        !store?.organizationNodeId ||
        !organizationNodeIds?.includes(store.organizationNodeId)
      ) {
        return false;
      }
    }

    const scope = this.effectiveWorkScope(admin);
    if (scope === NATIONAL_SCOPE) return true;
    if (admin.organizationNodeId && store?.organizationNodeId) {
      const organizationNodeIds = await this.organizationDescendantIds(
        admin.organizationNodeId,
      );
      return organizationNodeIds.includes(store.organizationNodeId);
    }
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

  private async userWithinAdminScope(admin: any, user: any) {
    const scope = await this.adminScope(admin);
    if (Object.keys(scope).length === 0) return true;
    const count = await this.prisma.user.count({
      where: { AND: [{ id: user.id }, scope] },
    });
    return count > 0;
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

  private userRelationMutationData(
    input: {
      storeUuid?: string | null;
      departmentCode?: string | null;
      jobRoleCode?: string | null;
      regionCode?: string | null;
      areaCode?: string | null;
      organizationNodeId?: string | null;
    },
    options: { disconnectNulls?: boolean } = {},
  ) {
    const data: Record<string, unknown> = {};
    this.assignOptionalRelation(data, 'store', input.storeUuid, 'id', options);
    this.assignOptionalRelation(
      data,
      'department',
      input.departmentCode,
      'code',
      options,
    );
    this.assignOptionalRelation(
      data,
      'jobRole',
      input.jobRoleCode,
      'code',
      options,
    );
    this.assignOptionalRelation(
      data,
      'region',
      input.regionCode,
      'code',
      options,
    );
    this.assignOptionalRelation(data, 'area', input.areaCode, 'code', options);
    this.assignOptionalRelation(
      data,
      'organizationNode',
      input.organizationNodeId,
      'id',
      options,
    );
    return data;
  }

  private assignOptionalRelation(
    data: Record<string, unknown>,
    relation: string,
    value: string | null | undefined,
    field: string,
    options: { disconnectNulls?: boolean },
  ) {
    if (value === undefined) return;
    if (value) {
      data[relation] = { connect: { [field]: value } };
      return;
    }
    if (options.disconnectNulls) data[relation] = { disconnect: true };
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
      const featureWhere =
        await this.userFeatureNodeAssignmentWhere(featureCode);
      if (featureWhere) conditions.push(featureWhere);
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

  private async userFeatureNodeAssignmentWhere(
    featureCodeInput: unknown,
  ): Promise<Prisma.UserWhereInput | null> {
    const featureCode = this.normalizeFeatureCode(featureCodeInput);
    if (!featureCode) return null;
    const assignmentModel = (this.prisma as any)
      .organizationNodeFeatureAssignment;
    if (!assignmentModel?.findMany)
      return { id: '__NO_NODE_FEATURE_ASSIGNMENT__' };
    const assignments: Array<{
      scopeRootNodeId: string;
      nodeType: string;
      nodeKey: string;
    }> = await assignmentModel.findMany({
      where: { featureCode, enabled: true },
      select: {
        scopeRootNodeId: true,
        nodeType: true,
        nodeKey: true,
      },
    });
    if (assignments.length === 0) {
      return { id: '__NO_NODE_FEATURE_ASSIGNMENT__' };
    }
    const nodes = await this.prisma.organizationNode.findMany({
      where: { isActive: true },
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
      },
    });
    const matchingNodeIds = new Set<string>();
    for (const assignment of assignments) {
      const descendantIds = await this.organizationDescendantIds(
        assignment.scopeRootNodeId,
      );
      for (const node of nodes) {
        if (
          descendantIds.includes(node.id) &&
          this.nodeFeatureType(node.type) ===
            this.nodeFeatureType(assignment.nodeType) &&
          this.nodeFeatureKey(node) === this.nodeFeatureKey(assignment.nodeKey)
        ) {
          matchingNodeIds.add(node.id);
        }
      }
    }
    if (matchingNodeIds.size === 0) {
      return { id: '__NO_NODE_FEATURE_ASSIGNMENT__' };
    }
    return { organizationNodeId: { in: Array.from(matchingNodeIds) } };
  }

  private nodeFeatureType(value: unknown) {
    const type = String(value || '')
      .trim()
      .toUpperCase();
    switch (type) {
      case 'ROOT_DOMAIN':
        return 'LV0_DOMAIN';
      case 'BLOCK':
        return 'LV1_BLOCK';
      case 'DEPARTMENT':
        return 'LV2_DEPARTMENT';
      case 'REGION':
        return 'LV2_REGION';
      case 'AREA':
        return 'LV3_AREA';
      case 'VIRTUAL_SCOPE':
        return 'LV3_UNIT';
      case 'SHOWROOM':
        return 'LV4_STORE';
      case 'JOB_ROLE':
        return 'LV5_POSITION';
      default:
        return type;
    }
  }

  private nodeFeatureKey(value: unknown) {
    if (typeof value === 'object' && value !== null) {
      const node = value as {
        businessCode?: string | null;
        code?: string | null;
      };
      return String(node.businessCode || node.code || '')
        .trim()
        .toUpperCase();
    }
    return String(value || '')
      .trim()
      .toUpperCase();
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
      assignmentPending: this.assignmentPending(user),
      mustSelectStore: this.mustSelectStore(user),
    };
  }

  private mustSelectStore(user: {
    role: string;
    workScopeType?: string | null;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    return false;
  }

  private assignmentPending(user: {
    role: string;
    organizationNodeId?: string | null;
  }) {
    const role = this.normalizeRoleCode(user.role, true);
    if (role === SUPER_ADMIN_ROLE || role === ADMIN_ROLE) return false;
    return !user.organizationNodeId;
  }

  async adminListRoles(admin: any) {
    await this.assertAdmin(admin);
    await this.seedDefaultRoles();
    return this.prisma.roleDefinition.findMany({
      where: { code: { in: [SUPER_ADMIN_ROLE, ADMIN_ROLE, USER_ROLE] } },
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

  adminRetiredTreeApi(admin: any, route: string) {
    this.logger.warn(
      'Retired admin tree API hit: route=' +
        route +
        ' admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' role=' +
        (admin?.role || 'unknown'),
    );
    throw new GoneException(
      'API Vùng/Miền/SR cũ đã ngưng sử dụng. Vui lòng dùng /admin/org-tree.',
    );
  }

  async adminListRegions(admin: any) {
    await this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    await this.seedDefaultOrganizationTree();
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) {
      return this.adminListRegionsLegacy();
    }
    this.logger.warn(
      'Deprecated admin regions route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown'),
    );
    const scopeWhere = await this.adminOrganizationNodeScopeWhere(admin);
    const nodes = await this.prisma.organizationNode.findMany({
      where: { AND: [{ type: 'REGION' }, ...(scopeWhere ? [scopeWhere] : [])] },
      orderBy: [{ isSystem: 'desc' }, { businessCode: 'asc' }],
    });
    return Promise.all(nodes.map((node) => this.toRegionShimDto(node)));
  }

  async adminListAreas(admin: any, regionCodeInput?: string) {
    await this.assertAdmin(admin);
    await this.seedDefaultPersonnelCatalog();
    await this.seedDefaultOrganizationTree();
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) {
      return this.adminListAreasLegacy(regionCodeInput);
    }
    this.logger.warn(
      'Deprecated admin areas route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown'),
    );
    const regionCode = regionCodeInput
      ? this.normalizePersonnelCode(regionCodeInput, 'Mã Miền không hợp lệ')
      : null;
    const scopeWhere = await this.adminOrganizationNodeScopeWhere(admin);
    const regionNode = regionCode
      ? await this.prisma.organizationNode.findFirst({
          where: {
            AND: [
              { type: 'REGION', businessCode: regionCode },
              ...(scopeWhere ? [scopeWhere] : []),
            ],
          },
        })
      : null;
    const nodes = await this.prisma.organizationNode.findMany({
      where: {
        AND: [
          { type: 'AREA' },
          ...(regionCode
            ? [{ parentId: regionNode?.id ?? '__NO_REGION__' }]
            : []),
          ...(scopeWhere ? [scopeWhere] : []),
        ],
      },
      orderBy: [{ isSystem: 'desc' }, { businessCode: 'asc' }],
    });
    return Promise.all(nodes.map((node) => this.toAreaShimDto(node)));
  }

  private async adminListRegionsLegacy() {
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

  private async adminListAreasLegacy(regionCodeInput?: string) {
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
    this.logger.warn(
      'Deprecated admin region create route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown'),
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
    this.logger.warn(
      'Deprecated admin region update route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' region=' +
        currentCode,
    );
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
    this.logger.warn(
      'Deprecated admin region delete route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' region=' +
        code,
    );
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
    this.logger.warn(
      'Deprecated admin area create route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' area=' +
        code,
    );
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
    this.logger.warn(
      'Deprecated admin area update route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' area=' +
        currentCode,
    );
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
    this.logger.warn(
      'Deprecated admin area delete route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' area=' +
        code,
    );
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
    throw new GoneException('Quyền hệ thống cố định: SUPER_ADMIN, ADMIN, USER');
  }

  async adminUpdateRole(admin: any, currentCode: string, body: any) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_ROLES,
      'Không có quyền sửa role',
    );
    throw new GoneException('Quyền hệ thống cố định: SUPER_ADMIN, ADMIN, USER');
  }

  async adminDeleteRole(admin: any, codeInput: string) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_ROLES,
      'Không có quyền xóa role',
    );
    throw new GoneException('Quyền hệ thống cố định: SUPER_ADMIN, ADMIN, USER');
  }

  async adminListStores(admin: any, q?: string) {
    await this.assertAdmin(admin);
    this.logger.warn(
      'Deprecated admin stores route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown'),
    );
    const query = q?.trim();
    const stores = await this.prisma.store.findMany({
      where: await this.adminStoreScope(admin, query),
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
    this.logger.warn(
      'Deprecated admin store create route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' store=' +
        storeId,
    );
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

    const store = await this.prisma.$transaction(async (tx) => {
      const createdStore = await tx.store.create({
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
      const syncResult = await this.syncStoreOrganizationNode(
        tx,
        createdStore,
        'admin-create-store',
      );
      return syncResult.store;
    });
    this.logger.log(
      'Store created: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' store=' +
        store.storeId,
    );
    return this.toStoreDto(store);
  }

  async adminUpdateStore(admin: any, currentStoreId: string, body: any) {
    const currentCode = this.normalizeStoreCode(currentStoreId);
    this.logger.warn(
      'Deprecated admin store update route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' store=' +
        currentCode,
    );
    const current = await this.prisma.store.findUnique({
      where: { storeId: currentCode },
      include: {
        area: { include: { region: true } },
        _count: { select: { users: true } },
      },
    });
    if (!current) throw new NotFoundException('Không tìm thấy store');
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_STORES,
      'Không có quyền sửa SR',
    );

    if (
      this.isScopedAdmin(admin) &&
      !(await this.storeWithinAdminScope(admin, current))
    ) {
      throw new ForbiddenException('Không có quyền sửa showroom khác');
    }

    if (this.isDomainAdmin(admin)) {
      const protectedChanges = await this.scopedStoreProtectedChanges(
        body,
        current,
      );
      if (protectedChanges.length > 0) {
        throw new ForbiddenException(
          'ADMIN theo phạm vi chỉ được sửa tài khoản/pass MAP; không được sửa ' +
            protectedChanges.join(', '),
        );
      }
      const mapData = this.normalizeMapVietinFields(body);
      if (Object.keys(mapData).length === 0) {
        return this.toStoreDto(current);
      }
      const updatedStore = await this.prisma.store.update({
        where: { storeId: current.storeId },
        data: mapData,
        include: {
          area: { include: { region: true } },
          _count: { select: { users: true } },
        },
      });
      this.logger.log(
        'Store MAP credential updated: admin=' +
          (admin.email || admin.id || 'unknown') +
          ' role=' +
          admin.role +
          ' store=' +
          updatedStore.storeId +
          ' mapUsernameChanged=' +
          (body.mapVietinUsername !== undefined) +
          ' mapPasswordProvided=' +
          Boolean(String(body.mapVietinPassword || '').trim()),
      );
      return this.toStoreDto(updatedStore);
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

    const result = await this.prisma.$transaction(async (tx) => {
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
        this.logger.log(
          'Store legacy area changed: store=' +
            updatedStore.storeId +
            ' area=' +
            (current.areaCode || 'null') +
            '->' +
            (updatedStore.areaCode || 'null') +
            ' region=' +
            regionCode,
        );
      }

      const organizationSync = await this.syncStoreOrganizationNode(
        tx,
        {
          ...updatedStore,
          organizationNodeId:
            updatedStore.organizationNodeId ?? current.organizationNodeId,
        },
        'admin-update-store',
      );
      if (organizationSync.nodeId) {
        const defaultUserNodeId =
          organizationSync.defaultUserNodeId ?? organizationSync.nodeId;
        const storeSubtreeIds = await this.organizationDescendantIdsForClient(
          tx,
          organizationSync.nodeId,
        );
        await tx.user.updateMany({
          where: {
            storeId: current.id,
            workScopeType: STORE_SCOPE,
            OR: [
              { organizationNodeId: null },
              { organizationNodeId: { notIn: storeSubtreeIds } },
            ],
          },
          data: {
            organizationNodeId: defaultUserNodeId,
            jobRoleCode: 'CASH',
            areaCode: organizationSync.location.areaCode,
            regionCode: organizationSync.location.regionCode,
          },
        });
      }
      return { store: organizationSync.store, organizationSync };
    });
    const store = result.store;

    this.logger.log(
      'Store updated: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' store=' +
        store.storeId,
    );
    return this.toStoreDto(store);
  }

  async adminDeleteStore(admin: any, storeIdInput: string) {
    await this.assertPolicy(
      admin,
      ADMIN_POLICY_CODES.ADMIN_STORE_CREATE,
      'Không có quyền xóa SR',
    );
    const storeId = this.normalizeStoreCode(storeIdInput);
    this.logger.warn(
      'Deprecated admin store delete route used: deprecatedRoute=true admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' store=' +
        storeId,
    );
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

  private async syncStoreOrganizationNodes(source: string) {
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.upsert || !this.prisma.store?.findMany) return;

    const startedAt = Date.now();
    this.logger.log('Store organization sync started: source=' + source);
    const stores =
      (await this.prisma.store.findMany({
        orderBy: { storeId: 'asc' },
        include: { area: { include: { region: true } } },
      })) ?? [];
    let syncedCount = 0;
    let locationSyncedUserCount = 0;
    let relinkedUserCount = 0;

    try {
      for (const store of stores) {
        await this.prisma.$transaction(async (tx) => {
          const syncResult = await this.syncStoreOrganizationNode(
            tx,
            store,
            source,
          );
          if (syncResult.nodeId) {
            const storeSubtreeIds =
              await this.organizationDescendantIdsForClient(
                tx,
                syncResult.nodeId,
              );
            const locationSync = await tx.user.updateMany({
              where: { storeId: store.id, workScopeType: STORE_SCOPE },
              data: {
                areaCode: syncResult.location.areaCode,
                regionCode: syncResult.location.regionCode,
              },
            });
            const relinkResult = await tx.user.updateMany({
              where: {
                storeId: store.id,
                workScopeType: STORE_SCOPE,
                OR: [
                  { organizationNodeId: null },
                  { organizationNodeId: { notIn: storeSubtreeIds } },
                ],
              },
              data: {
                organizationNodeId:
                  syncResult.defaultUserNodeId ?? syncResult.nodeId,
                jobRoleCode: 'CASH',
              },
            });
            locationSyncedUserCount += locationSync.count;
            relinkedUserCount += relinkResult.count;
          }
        });
        syncedCount += 1;
      }
      this.logger.log(
        'Store organization sync completed: source=' +
          source +
          ' stores=' +
          stores.length +
          ' synced=' +
          syncedCount +
          ' userLocationSynced=' +
          locationSyncedUserCount +
          ' userRelinked=' +
          relinkedUserCount +
          ' durationMs=' +
          (Date.now() - startedAt),
      );
    } catch (error) {
      this.logger.error(
        'Store organization sync failed: source=' +
          source +
          ' stores=' +
          stores.length +
          ' synced=' +
          syncedCount,
        error instanceof Error ? error.stack : String(error),
      );
      throw error;
    }
  }

  private async syncStoreOrganizationNode(
    client: any,
    store: any,
    source: string,
  ) {
    const organizationNode = client.organizationNode;
    if (!organizationNode?.upsert || !client.store?.update) {
      return {
        store,
        nodeId: null,
        defaultUserNodeId: null,
        parentId: null,
        linked: false,
        moved: false,
        location: {
          areaCode: null as string | null,
          regionCode: null as string | null,
        },
      };
    }

    const storeCode = this.normalizeStoreCode(store.storeId);
    const nodeCode = this.normalizeOrganizationNodeCode('STORE_' + storeCode);
    const domain = this.organizationDomainForStore(store);
    let existingNode: any = null;
    if (store.organizationNodeId && organizationNode.findUnique) {
      existingNode = await organizationNode.findUnique({
        where: { id: store.organizationNodeId },
        select: { id: true, parentId: true, type: true, isSystem: true },
      });
      if (
        existingNode &&
        (existingNode.isSystem || !this.isStoreNodeType(existingNode.type))
      ) {
        existingNode = null;
      }
    }
    if (!existingNode && organizationNode.findUnique) {
      existingNode = await organizationNode.findUnique({
        where: { code: nodeCode },
        select: { id: true, parentId: true, type: true, isSystem: true },
      });
      if (
        existingNode &&
        (existingNode.isSystem || !this.isStoreNodeType(existingNode.type))
      ) {
        existingNode = null;
      }
    }
    const parentId = existingNode?.parentId ?? domain.baseParentId;
    const displayName = this.normalizeRequiredText(
      store.storeName || storeCode,
      'Tên store không được để trống',
      120,
    );
    const nodeData = {
      code: nodeCode,
      displayName,
      businessCode: storeCode,
      abbreviation: storeCode,
      description: displayName,
      type: ORG_TYPE_LV4_STORE,
      parentId,
      emailDomain: null,
      loginAllowed: false,
      isSystem: false,
      isActive: true,
      sortOrder: domain.sortBase + 300,
    };

    const node = existingNode?.id
      ? await organizationNode.update({
          where: { id: existingNode.id },
          data: nodeData,
        })
      : await organizationNode.upsert({
          where: { code: nodeCode },
          update: nodeData,
          create: nodeData,
        });

    const linked = store.organizationNodeId !== node.id;
    if (linked && store.id) {
      await client.store.update({
        where: { id: store.id },
        data: { organizationNodeId: node.id },
      });
    }
    await this.ensureDefaultStorePositionNodes(client, node);
    const defaultUserNodeId = await this.defaultStoreCashNodeIdForClient(
      client,
      node.id,
    );

    if (
      source !== 'admin-list-organization-tree' &&
      (linked || existingNode?.parentId !== parentId)
    ) {
      this.logger.log(
        'Store organization node synced: source=' +
          source +
          ' store=' +
          storeCode +
          ' nodeId=' +
          node.id +
          ' parentId=' +
          parentId +
          ' linked=' +
          linked +
          ' moved=' +
          (existingNode?.parentId !== parentId),
      );
    }

    return {
      store: { ...store, organizationNodeId: node.id },
      nodeId: node.id,
      defaultUserNodeId,
      parentId,
      linked,
      moved: existingNode?.parentId !== parentId,
      location: await this.organizationLocationForShowroomNode(client, node),
    };
  }

  private organizationDomainForStore(store: any) {
    const storeCode = String(store?.storeId || '')
      .trim()
      .toUpperCase();
    const storeName = String(store?.storeName || '').trim().toLowerCase();
    const areaCode = String(store?.areaCode || '').trim().toUpperCase();
    const isAcare =
      storeCode.startsWith('AC') ||
      storeCode.startsWith('AP') ||
      areaCode === 'ACARE' ||
      storeName.startsWith('acare');
    return {
      baseParentId: isAcare ? ORG_ROOT_ACARE_ID : ORG_ROOT_PHONGVU_ID,
      sortBase: isAcare ? 20000 : 10000,
    };
  }

  private async seedDefaultOrganizationTree() {
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.upsert) return;

    await organizationNode.upsert({
      where: { code: 'DOMAIN_PHONGVU_VN' },
      update: {
        displayName: 'phongvu.vn',
        businessCode: 'phongvu.vn',
        abbreviation: 'PV',
        description: 'Domain đăng nhập Phong Vũ',
        type: ORG_TYPE_LV0_DOMAIN,
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
        businessCode: 'phongvu.vn',
        abbreviation: 'PV',
        description: 'Domain đăng nhập Phong Vũ',
        type: ORG_TYPE_LV0_DOMAIN,
        emailDomain: 'phongvu.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 10,
      },
    });
    await organizationNode.upsert({
      where: { code: 'DOMAIN_ACARE_VN' },
      update: {
        displayName: 'acare.vn',
        businessCode: 'ACARE_VN',
        abbreviation: 'ACARE',
        description: 'Domain đăng nhập A Care',
        type: ORG_TYPE_LV0_DOMAIN,
        emailDomain: 'acare.vn',
        loginAllowed: true,
        isSystem: true,
        isActive: true,
        sortOrder: 20,
      },
      create: {
        id: ORG_ROOT_ACARE_ID,
        code: 'DOMAIN_ACARE_VN',
        displayName: 'acare.vn',
        businessCode: 'ACARE_VN',
        abbreviation: 'ACARE',
        description: 'Domain đăng nhập A Care',
        type: ORG_TYPE_LV0_DOMAIN,
        emailDomain: 'acare.vn',
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
          ...this.userRelationMutationData(
            {
              storeUuid: null,
              regionCode: null,
              areaCode: null,
              organizationNodeId: null,
            },
            { disconnectNulls: true },
          ),
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
          role: USER_ROLE,
          status: 'no',
          tokenVersion: { increment: 1 },
          workScopeType: NATIONAL_SCOPE,
          ...this.userRelationMutationData(
            {
              storeUuid: null,
              regionCode: null,
              areaCode: null,
              organizationNodeId: null,
            },
            { disconnectNulls: true },
          ),
        },
      });
    });

    this.logger.warn(
      `Legacy super admin retired: email=${LEGACY_SUPER_ADMIN_EMAIL} mode=${blockerCount === 0 ? 'deleted' : 'tombstoned'} blockers=${blockerCount}`,
    );
  }

  private async resolveUserAssignmentStoreUuid(
    admin: any,
    body: any,
    options: { current?: any; workScopeType: string },
  ) {
    if (options.workScopeType !== STORE_SCOPE) return null;
    if (body.organizationNodeId === undefined) {
      if (options.current && body.workScopeType === undefined) {
        return options.current.storeId ?? null;
      }
      throw new BadRequestException('Vui lòng chọn showroom trên cây tổ chức');
    }

    const scopeLocation = await this.resolveScopeLocationFromOrganizationNode(
      admin,
      body.organizationNodeId,
      STORE_SCOPE,
    );
    const store = await this.prisma.store.findFirst({
      where: { organizationNodeId: scopeLocation.storeNodeId },
      include: { area: { include: { region: true } } },
    });
    if (!store) {
      throw new BadRequestException('Showroom chưa được gắn SR');
    }
    if (
      this.isScopedAdmin(admin) &&
      !(await this.storeWithinAdminScope(admin, store))
    ) {
      throw new ForbiddenException('Chỉ được gán user trong phạm vi quản lý');
    }
    return store.id;
  }

  private async resolvePersonnelAssignment(
    admin: any,
    body: any,
    options: {
      current?: any;
      role: string;
      storeUuid?: string | null;
      workScopeType: string;
    },
  ) {
    const treePersonnel =
      body.organizationNodeId !== undefined
        ? await this.resolvePersonnelCodesFromOrganizationNode(
            body.organizationNodeId,
          )
        : null;
    const departmentCode = treePersonnel
      ? treePersonnel.departmentCode
      : await this.resolveDepartmentCode(
          body.departmentCode,
          options.current?.departmentCode ?? null,
        );
    const jobRoleCode = treePersonnel
      ? treePersonnel.jobRoleCode
      : await this.resolveJobRoleCode(
          body.jobRoleCode,
          options.current?.jobRoleCode ?? null,
        );
    const scopeLocation = await this.resolveScopeLocation(admin, body, {
      current: options.current,
      storeUuid: options.storeUuid,
      role: options.role,
      workScopeType: options.workScopeType,
    });

    return {
      departmentCode,
      jobRoleCode,
      workScopeType: options.workScopeType,
      ...scopeLocation,
    };
  }

  private async resolveScopeLocation(
    admin: any,
    body: any,
    options: {
      current?: any;
      role: string;
      storeUuid?: string | null;
      workScopeType: string;
    },
  ) {
    if (options.workScopeType === NATIONAL_SCOPE) {
      if (body.organizationNodeId === undefined) {
        if (options.current && body.workScopeType === undefined) {
          return {
            regionCode: null,
            areaCode: null,
            organizationNodeId: options.current.organizationNodeId ?? null,
          };
        }
        if (options.role === SUPER_ADMIN_ROLE) {
          return { regionCode: null, areaCode: null, organizationNodeId: null };
        }
        throw new BadRequestException('Vui lòng chọn domain gốc');
      }

      const nodeId = String(body.organizationNodeId || '').trim();
      if (!nodeId) {
        if (options.role === SUPER_ADMIN_ROLE) {
          return { regionCode: null, areaCode: null, organizationNodeId: null };
        }
        throw new BadRequestException('Vui lòng chọn domain gốc');
      }

      return this.resolveScopeLocationFromOrganizationNode(
        admin,
        nodeId,
        NATIONAL_SCOPE,
      );
    }

    if (options.workScopeType === STORE_SCOPE) {
      if (body.organizationNodeId !== undefined) {
        const scopeLocation =
          await this.resolveScopeLocationFromOrganizationNode(
            admin,
            body.organizationNodeId,
            STORE_SCOPE,
          );
        const store = options.storeUuid
          ? await this.prisma.store.findUnique({
              where: { id: options.storeUuid },
              include: { area: { include: { region: true } } },
            })
          : null;
        return {
          ...scopeLocation,
          areaCode:
            scopeLocation.areaCode ?? store?.areaCode ?? DEFAULT_REGION_CODE,
          regionCode:
            scopeLocation.regionCode ??
            store?.area?.regionCode ??
            DEFAULT_REGION_CODE,
        };
      }
      const store = options.storeUuid
        ? await this.prisma.store.findUnique({
            where: { id: options.storeUuid },
            include: {
              area: { include: { region: true } },
              organizationNode: true,
            },
          })
        : null;
      const areaCode = store?.areaCode ?? DEFAULT_REGION_CODE;
      const regionCode = store?.area?.regionCode ?? DEFAULT_REGION_CODE;
      const organizationNodeId =
        (await this.defaultStoreCashNodeIdForStore(store)) ??
        store?.organizationNodeId ??
        null;
      return {
        regionCode,
        areaCode,
        organizationNodeId,
        storeNodeId: store?.organizationNodeId ?? null,
      };
    }

    if (body.organizationNodeId === undefined) {
      if (options.current && body.workScopeType === undefined) {
        return {
          regionCode: options.current.regionCode ?? null,
          areaCode: options.current.areaCode ?? null,
          organizationNodeId: options.current.organizationNodeId ?? null,
        };
      }
      throw new BadRequestException('Vui lòng chọn node tổ chức');
    }

    return this.resolveScopeLocationFromOrganizationNode(
      admin,
      body.organizationNodeId,
      options.workScopeType,
    );
  }

  private async resolveScopeLocationFromOrganizationNode(
    admin: any,
    nodeIdInput: unknown,
    workScopeType: string,
  ) {
    const nodeId = String(nodeIdInput || '').trim();
    if (!nodeId) throw new BadRequestException('Vui lòng chọn node tổ chức');
    const context = await this.organizationScopeContext(nodeId);
    if (workScopeType === STORE_SCOPE && !context.storeNodeId) {
      throw new BadRequestException('Vui lòng chọn node showroom');
    }
    await this.assertOrganizationNodeAssignableByAdmin(
      admin,
      context.organizationNodeId,
    );
    if (
      workScopeType === NATIONAL_SCOPE &&
      !context.regionCode &&
      !context.areaCode
    ) {
      return {
        regionCode: null,
        areaCode: null,
        organizationNodeId: context.organizationNodeId,
        storeNodeId: context.storeNodeId,
      };
    }
    return {
      regionCode: context.regionCode,
      areaCode: context.areaCode,
      organizationNodeId: context.organizationNodeId,
      storeNodeId: context.storeNodeId,
    };
  }

  private async resolvePersonnelCodesFromOrganizationNode(
    nodeIdInput: unknown,
  ) {
    const nodeId = String(nodeIdInput || '').trim();
    if (!nodeId) return { departmentCode: null, jobRoleCode: null };
    const context = await this.organizationScopeContext(nodeId);
    const departmentCode = context.departmentCode
      ? await this.resolveDepartmentCode(context.departmentCode, null)
      : null;
    const jobRoleCode = context.jobRoleCode
      ? await this.resolveJobRoleCode(context.jobRoleCode, null)
      : null;
    return { departmentCode, jobRoleCode };
  }

  private async assertOrganizationNodeAssignableByAdmin(
    admin: any,
    nodeId: string,
  ) {
    const rootId = this.adminOrgRootId(admin);
    if (!rootId) return;
    const organizationNodeIds = await this.organizationDescendantIds(rootId);
    if (organizationNodeIds.includes(nodeId)) return;
    this.logger.warn(
      'Admin user scope assignment blocked by domain: admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' role=' +
        admin?.role +
        ' nodeId=' +
        nodeId +
        ' allowedRootId=' +
        rootId,
    );
    throw new ForbiddenException('Chỉ được gán user trong phạm vi quản lý');
  }

  private async organizationScopeContext(nodeId: string) {
    const nodes: Array<{
      id: string;
      parentId: string | null;
      type: string;
      code: string;
      businessCode: string | null;
      isActive: boolean;
    }> = await this.prisma.organizationNode.findMany({
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
        isActive: true,
      },
    });
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const node = byId.get(nodeId);
    if (!node || !node.isActive) {
      throw new BadRequestException('Node tổ chức không tồn tại hoặc đã tắt');
    }
    const ancestors: typeof nodes = [];
    let cursor: (typeof nodes)[number] | null = node;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      ancestors.push(cursor);
      cursor = cursor.parentId ? (byId.get(cursor.parentId) ?? null) : null;
    }
    const businessCodeFor = (type: string) => {
      const item = ancestors.find(
        (ancestor) =>
          this.normalizeOrganizationNodeType(ancestor.type) === type,
      );
      if (!item) return null;
      if (type === ORG_TYPE_LV4_STORE) {
        return this.normalizeStoreCode(
          item.businessCode ?? this.legacyCodeFromOrganizationCode(item.code),
        );
      }
      return this.legacyPersonnelCodeFromOrganizationNode(
        item,
        'Mã nghiệp vụ không hợp lệ',
      );
    };
    const storeNode = ancestors.find(
      (ancestor) =>
        this.normalizeOrganizationNodeType(ancestor.type) ===
        ORG_TYPE_LV4_STORE,
    );
    const jobRoleCode = businessCodeFor(ORG_TYPE_LV5_POSITION);
    const defaultPosition = DEFAULT_STORE_POSITION_DEFINITIONS.find(
      (position) => position.businessCode === jobRoleCode,
    );
    return {
      organizationNodeId: node.id,
      nodeType: this.normalizeOrganizationNodeType(node.type),
      departmentCode:
        businessCodeFor(ORG_TYPE_LV2_DEPARTMENT) ??
        defaultPosition?.departmentCode ??
        null,
      jobRoleCode,
      regionCode: businessCodeFor(ORG_TYPE_LV2_REGION),
      areaCode: businessCodeFor(ORG_TYPE_LV3_AREA),
      storeCode: businessCodeFor(ORG_TYPE_LV4_STORE),
      storeNodeId: storeNode?.id ?? null,
    };
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

  private async resolveWorkScopeTypeForAssignment(
    body: any,
    current: any | null,
    role: string,
  ) {
    if (body.workScopeType !== undefined) {
      return this.resolveWorkScopeType(
        body.workScopeType,
        current?.workScopeType,
        role,
      );
    }
    if (body.organizationNodeId !== undefined) {
      const nodeId = String(body.organizationNodeId || '').trim();
      if (!nodeId) return this.defaultWorkScopeForRole(role);
      const context = await this.organizationScopeContext(nodeId);
      return this.workScopeTypeFromOrganizationContext(context);
    }
    return this.resolveWorkScopeType(undefined, current?.workScopeType, role);
  }

  private workScopeTypeFromOrganizationContext(context: {
    nodeType: string;
    regionCode?: string | null;
    areaCode?: string | null;
    storeNodeId?: string | null;
  }) {
    if (context.storeNodeId || context.nodeType === ORG_TYPE_LV4_STORE) {
      return STORE_SCOPE;
    }
    if (context.nodeType === ORG_TYPE_LV5_POSITION && context.storeNodeId) {
      return STORE_SCOPE;
    }
    if (context.nodeType === ORG_TYPE_LV3_AREA || context.areaCode) {
      return AREA_SCOPE;
    }
    if (
      context.nodeType === ORG_TYPE_LV2_REGION ||
      context.nodeType === ORG_TYPE_LV2_DEPARTMENT ||
      context.regionCode
    ) {
      return REGION_SCOPE;
    }
    return NATIONAL_SCOPE;
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
    const normalizedRole = this.normalizeRoleCode(role);
    if (normalizedRole === SUPER_ADMIN_ROLE || normalizedRole === ADMIN_ROLE) {
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
      return USER_ROLE;
    }
    const normalized = ROLE_ALIASES[code] ?? code;
    if (![SUPER_ADMIN_ROLE, ADMIN_ROLE, USER_ROLE].includes(normalized)) {
      if (strict) throw new BadRequestException('Role hệ thống không hợp lệ');
      return USER_ROLE;
    }
    if (normalized !== code) {
      this.logger.warn(
        `Legacy role alias normalized: input=${code} normalized=${normalized}`,
      );
    }
    return normalized;
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
    const normalizedCode = this.normalizeRoleCode(code, true);
    await this.prisma.roleDefinition.upsert({
      where: { code: normalizedCode },
      update: {},
      create: {
        code: normalizedCode,
        displayName: normalizedCode,
        description: null,
        isSystem: true,
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
    return this.adminOrgRootId(user) === ORG_ROOT_ACARE_ID;
  }

  private isAcaretekEmail(email: unknown) {
    return String(email || '')
      .trim()
      .toLowerCase()
      .endsWith('@' + ACARE_EMAIL_DOMAIN);
  }

  private async adminDomainScope(admin: any): Promise<Prisma.UserWhereInput> {
    const rootId = this.adminOrgRootId(admin);
    if (!rootId) return {};
    return this.organizationUserScopeForRoot(rootId);
  }

  private combineUserScope(
    domainScope: Prisma.UserWhereInput,
    locationScope: Prisma.UserWhereInput,
  ): Prisma.UserWhereInput {
    if (Object.keys(domainScope).length === 0) return locationScope;
    return { AND: [domainScope, locationScope] };
  }

  private adminDomainScopeLabel(admin: any) {
    const rootId = this.adminOrgRootId(admin);
    if (rootId === ORG_ROOT_PHONGVU_ID) return 'phongvu.vn';
    if (rootId === ORG_ROOT_ACARE_ID) return ACARE_EMAIL_DOMAIN;
    return 'all';
  }

  private async emailDomainBelongsToRoot(domain: unknown, rootId: string) {
    const normalizedDomain = this.normalizeOptionalEmailDomain(domain);
    if (!normalizedDomain) return false;

    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) {
      if (rootId === ORG_ROOT_ACARE_ID) {
        return normalizedDomain === ACARE_EMAIL_DOMAIN;
      }
      if (rootId === ORG_ROOT_PHONGVU_ID) {
        return (
          normalizedDomain === 'phongvu.vn' ||
          normalizedDomain.startsWith('phongvu-')
        );
      }
      return false;
    }

    const ids = new Set(await this.organizationDescendantIds(rootId));
    const nodes: Array<{ id: string; emailDomain: string | null }> =
      await organizationNode.findMany({
        select: { id: true, emailDomain: true },
      });
    return nodes.some((node) => {
      if (!ids.has(node.id)) return false;
      const nodeDomain = this.normalizeOptionalEmailDomain(node.emailDomain);
      return nodeDomain === normalizedDomain;
    });
  }

  private async assertEmailWithinAdminDomain(admin: any, email: string) {
    if (!this.isDomainAdmin(admin)) return;
    const rootId = this.adminOrgRootId(admin);
    const emailDomain = this.emailDomainFromEmail(email);
    if (rootId && (await this.emailDomainBelongsToRoot(emailDomain, rootId))) {
      return;
    }

    const scopeLabel = this.adminDomainScopeLabel(admin);
    this.logger.warn(
      'Admin user create blocked by email domain: admin=' +
        (admin.email || admin.id || 'unknown') +
        ' role=' +
        admin.role +
        ' targetDomain=' +
        (emailDomain || 'invalid') +
        ' allowedScope=' +
        scopeLabel,
    );
    throw new ForbiddenException(
      admin.role + ' chỉ được quản lý user thuộc ' + scopeLabel,
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

  private async scopedStoreProtectedChanges(body: any, current: any) {
    const changes: string[] = [];
    if (body.storeId !== undefined) {
      const nextCode = this.normalizeStoreCode(body.storeId);
      if (nextCode !== current.storeId) changes.push('mã SR');
    }
    if (body.storeName !== undefined) {
      const nextName = this.normalizeRequiredText(
        body.storeName,
        'Tên store không được để trống',
        120,
      );
      if (nextName !== current.storeName) changes.push('tên SR');
    }
    if (body.areaCode !== undefined) {
      const nextAreaCode = await this.resolveAreaCodeForStore(body.areaCode);
      if (nextAreaCode !== current.areaCode) changes.push('Vùng/Miền');
    }

    const optionalTextChanged = (
      key: string,
      label: string,
      maxLength: number,
    ) => {
      if (body[key] === undefined) return;
      const nextValue =
        this.normalizeOptionalText(body[key], maxLength) ?? null;
      const currentValue = current[key] ?? null;
      if (nextValue !== currentValue) changes.push(label);
    };
    optionalTextChanged('transferAccountNumber', 'số tài khoản nhận tiền', 80);
    optionalTextChanged('transferAccountName', 'tên tài khoản nhận tiền', 120);
    optionalTextChanged('transferBankName', 'ngân hàng nhận tiền', 80);
    optionalTextChanged('transferBankBin', 'BIN ngân hàng', 20);
    return changes;
  }

  private async adminStoreScope(
    admin: any,
    query?: string,
  ): Promise<Prisma.StoreWhereInput | undefined> {
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
    const scopeWhere = await this.adminStoreScopeWhere(admin);

    if (queryWhere && scopeWhere) return { AND: [scopeWhere, queryWhere] };
    return queryWhere || scopeWhere;
  }

  private async adminStoreScopeWhere(
    admin: any,
  ): Promise<Prisma.StoreWhereInput | undefined> {
    if (!this.isScopedAdmin(admin)) return undefined;
    const organizationScope = await this.adminStoreOrganizationScope(admin);
    const scope = this.effectiveWorkScope(admin);
    if (scope === NATIONAL_SCOPE) {
      return this.combineStoreScope(organizationScope, undefined);
    }
    if (admin.organizationNodeId) {
      const organizationNodeIds = await this.organizationDescendantIds(
        admin.organizationNodeId,
      );
      return this.combineStoreScope(organizationScope, {
        organizationNodeId: { in: organizationNodeIds },
      });
    }
    if (scope === REGION_SCOPE) {
      const locationScope = admin.regionCode
        ? { area: { regionCode: admin.regionCode } }
        : { id: '__NO_REGION__' };
      return this.combineStoreScope(organizationScope, locationScope);
    }
    if (scope === AREA_SCOPE) {
      const locationScope = admin.areaCode
        ? { areaCode: admin.areaCode }
        : { id: '__NO_AREA__' };
      return this.combineStoreScope(organizationScope, locationScope);
    }
    return this.combineStoreScope(organizationScope, {
      id: admin.storeId || '__NO_STORE__',
    });
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
      organizationNodeId: store.organizationNodeId ?? null,
      userCount: store._count?.users ?? 0,
    };
  }
}
