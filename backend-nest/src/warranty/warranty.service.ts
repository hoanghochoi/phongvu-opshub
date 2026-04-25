import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class WarrantyService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
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
        imageLinks: data.imageLinks, // semicolon-separated image URLs
        createdById: userId,
      },
    });
  }

  async getAllWarranties() {
    const warranties = await this.prisma.warranty.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        createdBy: { select: { id: true, firstName: true, role: true } },
        handledBy: { select: { id: true, firstName: true, role: true } },
      },
    });

    return warranties.map((warranty) => this.formatWarrantyForApp(warranty));
  }

  async searchByReceipt(receipt: string) {
    const warranties = await this.prisma.warranty.findMany({
      where: { receipt: { contains: receipt, mode: 'insensitive' } },
      orderBy: { createdAt: 'desc' },
      include: {
        createdBy: { select: { firstName: true } },
      },
    });

    return warranties.map((warranty) => this.formatWarrantyForApp(warranty));
  }

  async getByReceipt(receipt: string) {
    const warranty = await this.prisma.warranty.findUnique({
      where: { receipt },
      include: {
        createdBy: { select: { firstName: true } },
        handledBy: { select: { firstName: true } },
      },
    });

    if (!warranty) {
      throw new NotFoundException('Không tìm thấy biên nhận');
    }

    return this.formatWarrantyForApp(warranty);
  }

  async getWarrantyById(id: string) {
    const warranty = await this.prisma.warranty.findUnique({
      where: { id },
      include: {
        createdBy: { select: { firstName: true } },
        handledBy: { select: { firstName: true } },
      },
    });

    if (!warranty) throw new NotFoundException('Warranty not found');
    return warranty;
  }

  async updateWarrantyStatus(id: string, userId: string, status: any) {
    const updated = await this.prisma.warranty.update({
      where: { id },
      data: { status, handledById: userId },
    });

    await this.redisService.publishMessage('WARRANTY_STATUS_UPDATED', {
      warrantyId: id,
      newStatus: status,
      handledBy: userId,
      timestamp: new Date().toISOString(),
    });

    return updated;
  }

  private formatWarrantyForApp(warranty: any) {
    return {
      ...warranty,
      user: warranty.createdBy?.firstName ?? 'N/A',
      date: warranty.createdAt?.toISOString?.() ?? warranty.createdAt,
      images: warranty.imageLinks
        ? warranty.imageLinks.split(';').filter((link: string) => link.trim())
        : [],
    };
  }
}
