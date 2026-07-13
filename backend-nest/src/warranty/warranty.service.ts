import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';

const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';

type WarrantyReadScope = { kind: 'ALL' } | { kind: 'STORE'; storeId: string };

@Injectable()
export class WarrantyService {
  private readonly logger = new Logger(WarrantyService.name);

  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
    private policyService: PolicyService,
  ) {}

  async createWarranty(userId: string, data: any) {
    return this.prisma.warranty.create({
      data: {
        receipt: data.receipt,
        customerName: data.customerName,
        customerPhone: data.customerPhone,
        productName: data.productName,
        serialNumber: data.serialNumber,
        issue: data.issue,
        note: data.note,
        imageLinks: data.imageLinks,
        createdById: userId,
      },
    });
  }

  async getAllWarranties(user: any) {
    const scope = await this.resolveReadScope(user, 'list');
    this.logger.log(
      `Warranty list started: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)}`,
    );

    const warranties = await this.prisma.warranty.findMany({
      where: this.scopeWhere(scope),
      orderBy: { createdAt: 'desc' },
      include: {
        createdBy: { select: { id: true, firstName: true, role: true } },
        handledBy: { select: { id: true, firstName: true, role: true } },
      },
    });

    this.logger.log(
      `Warranty list succeeded: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)} count=${warranties.length}`,
    );
    return warranties.map((warranty) => this.formatWarrantyForApp(warranty));
  }

  async searchByReceipt(user: any, receipt: string) {
    const scope = await this.resolveReadScope(user, 'search');
    const normalizedReceipt = String(receipt || '').trim();
    this.logger.log(
      `Warranty search started: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)} receiptLength=${normalizedReceipt.length}`,
    );

    const warranties = await this.prisma.warranty.findMany({
      where: this.mergeWhere(this.scopeWhere(scope), {
        receipt: { contains: normalizedReceipt, mode: 'insensitive' },
      }),
      orderBy: { createdAt: 'desc' },
      include: {
        createdBy: { select: { firstName: true } },
      },
    });

    this.logger.log(
      `Warranty search succeeded: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)} count=${warranties.length}`,
    );
    return warranties.map((warranty) => this.formatWarrantyForApp(warranty));
  }

  async getByReceipt(user: any, receipt: string) {
    const scope = await this.resolveReadScope(user, 'detail');
    const normalizedReceipt = String(receipt || '').trim();
    if (!normalizedReceipt) {
      this.logger.warn(
        `Warranty detail failed: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)} reason=missing_receipt`,
      );
      throw new BadRequestException('Receipt is required');
    }

    this.logger.log(
      `Warranty detail started: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)} receiptLength=${normalizedReceipt.length}`,
    );

    const warranty = await this.prisma.warranty.findFirst({
      where: this.mergeWhere(this.scopeWhere(scope), {
        receipt: normalizedReceipt,
      }),
      include: {
        createdBy: { select: { firstName: true } },
        handledBy: { select: { firstName: true } },
      },
    });

    if (!warranty) {
      this.logger.warn(
        `Warranty detail failed: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)} reason=not_found receiptLength=${normalizedReceipt.length}`,
      );
      throw new NotFoundException('Khong tim thay bien nhan');
    }

    this.logger.log(
      `Warranty detail succeeded: userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)}`,
    );
    return this.formatWarrantyForApp(warranty);
  }

  async getWarrantyById(user: any, id: string) {
    const scope = await this.resolveReadScope(user, 'detailById');
    this.logger.log(
      `Warranty detail by id started: warrantyId=${id} userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)}`,
    );

    const warranty = await this.prisma.warranty.findFirst({
      where: this.mergeWhere(this.scopeWhere(scope), { id }),
      include: {
        createdBy: { select: { firstName: true } },
        handledBy: { select: { firstName: true } },
      },
    });

    if (!warranty) {
      this.logger.warn(
        `Warranty detail by id failed: warrantyId=${id} userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)} reason=not_found`,
      );
      throw new NotFoundException('Warranty not found');
    }
    this.logger.log(
      `Warranty detail by id succeeded: warrantyId=${id} userId=${user?.id ?? 'unknown'} scope=${this.scopeLogValue(scope)}`,
    );
    return warranty;
  }

  async updateWarrantyStatus(
    user: any,
    id: string,
    userId: string,
    status: any,
  ) {
    const scope = await this.resolveReadScope(user, 'updateStatus');
    this.logger.log(
      `Warranty status update started: warrantyId=${id} userId=${userId} scope=${this.scopeLogValue(scope)} status=${status}`,
    );

    const existing = await this.prisma.warranty.findFirst({
      where: this.mergeWhere(this.scopeWhere(scope), { id }),
      select: {
        id: true,
        createdById: true,
        createdBy: { select: { store: { select: { storeId: true } } } },
      },
    });
    if (!existing) {
      this.logger.warn(
        `Warranty status update failed: warrantyId=${id} userId=${userId} scope=${this.scopeLogValue(scope)} status=${status} reason=not_found`,
      );
      throw new NotFoundException('Warranty not found');
    }

    const updated = await this.prisma.warranty.update({
      where: { id },
      data: { status, handledById: userId },
    });

    const occurredAt = new Date().toISOString();
    const storeCode = existing.createdBy?.store?.storeId?.trim().toUpperCase();
    await this.redisService.publishMessage('WARRANTY_STATUS_UPDATED', {
      schemaVersion: 1,
      type: 'WARRANTY_EVENT',
      eventId: 'warranty:' + id + ':' + occurredAt,
      occurredAt,
      audience: {
        storeCodes: storeCode ? [storeCode] : [],
        recipientUserIds: Array.from(
          new Set([existing.createdById, userId].filter(Boolean)),
        ),
        roles: ['SUPER_ADMIN'],
        featureCodes: [FEATURE_KEYS.WARRANTY],
      },
      payload: {
        warrantyId: id,
        newStatus: status,
        handledBy: userId,
        timestamp: occurredAt,
      },
    });

    this.logger.log(
      `Warranty status updated: warrantyId=${id} userId=${userId} scope=${this.scopeLogValue(scope)} status=${status}`,
    );
    return updated;
  }

  private async resolveReadScope(
    user: any,
    source: string,
  ): Promise<WarrantyReadScope> {
    if (user?.role === SUPER_ADMIN_ROLE) {
      return { kind: 'ALL' };
    }

    if (!user?.storeId) {
      this.logger.warn(
        `Warranty access denied: userId=${user?.id ?? 'unknown'} source=${source} reason=missing_store`,
      );
      throw new ForbiddenException('Tai khoan chua duoc gan showroom');
    }

    return { kind: 'STORE', storeId: user.storeId };
  }

  private scopeWhere(scope: WarrantyReadScope): Prisma.WarrantyWhereInput {
    if (scope.kind === 'ALL') return {};
    return { createdBy: { storeId: scope.storeId } };
  }

  private scopeLogValue(scope: WarrantyReadScope) {
    if (scope.kind === 'ALL') return 'ALL';
    return `STORE:${scope.storeId}`;
  }

  private mergeWhere(
    ...parts: Prisma.WarrantyWhereInput[]
  ): Prisma.WarrantyWhereInput {
    const compact = parts.filter((part) => Object.keys(part).length > 0);
    if (compact.length === 0) return {};
    if (compact.length === 1) return compact[0];
    return { AND: compact };
  }

  private formatWarrantyForApp(warranty: any) {
    return {
      ...warranty,
      user: warranty.createdBy?.firstName ?? 'N/A',
      date: warranty.createdAt?.toISOString?.() ?? warranty.createdAt,
      images: warranty.imageLinks
        ? warranty.imageLinks
            .split(';')
            .map((link: string) => link.trim())
            .filter((link: string) => link.length > 0)
        : [],
    };
  }
}
