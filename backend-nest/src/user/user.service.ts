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
import { Role } from '@prisma/client';

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

  onModuleInit() {
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
        const role = this.parseRole(
          String(row.role || 'STAFF')
            .trim()
            .toUpperCase(),
        );
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

  // -------------------------------------------------------
  // Parse role string to valid Prisma Role enum
  // -------------------------------------------------------
  private parseRole(
    roleStr: string,
  ): 'SUPER_ADMIN' | 'ADMIN' | 'MANAGER' | 'STAFF' {
    const validRoles = ['SUPER_ADMIN', 'ADMIN', 'MANAGER', 'STAFF'] as const;
    if (validRoles.includes(roleStr as any)) {
      return roleStr as (typeof validRoles)[number];
    }
    return 'STAFF'; // Default
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

    const role = this.parseRole(String(body.role || 'STAFF').toUpperCase());
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

    if (admin.role === Role.ADMIN && current.storeId !== admin.storeId) {
      throw new ForbiddenException('Không có quyền sửa user ngoài chi nhánh');
    }

    const role = body.role
      ? this.parseRole(String(body.role).toUpperCase())
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
    if (admin.role === Role.ADMIN && admin.storeId !== store.id) {
      throw new ForbiddenException(
        'Admin chỉ được gán user vào chi nhánh của mình',
      );
    }
    return store.id;
  }

  private assertAdmin(user: any) {
    if (user.role !== Role.SUPER_ADMIN && user.role !== Role.ADMIN) {
      throw new ForbiddenException('Không có quyền quản trị user');
    }
  }

  private assertRoleEditable(admin: any, role: Role | string) {
    if (admin.role === Role.ADMIN && role === Role.SUPER_ADMIN) {
      throw new ForbiddenException('Admin không được gán quyền SUPER_ADMIN');
    }
  }

  private adminScope(admin: any) {
    if (admin.role === Role.ADMIN) {
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
      user.role !== Role.SUPER_ADMIN && user.role !== Role.ADMIN && !hasStore
    );
  }
}
