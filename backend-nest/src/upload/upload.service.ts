import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UploadService {
  private readonly logger = new Logger(UploadService.name);

  // Base directory for images.
  private readonly baseDir = process.env.UPLOAD_BASE_DIR || '/data/app_images';
  private readonly baseUrl =
    process.env.IMAGE_BASE_URL || 'https://img.example.com';

  constructor(private prisma: PrismaService) {}

  async saveWarrantyImages(
    receipt: string,
    files: Express.Multer.File[],
  ): Promise<string[]> {
    const safeReceipt = this.getSafePathSegment(receipt, 'receipt');
    const receiptDir = this.getPathInsideBase(safeReceipt);

    await fs.promises.mkdir(receiptDir, { recursive: true });

    const links: string[] = [];

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const ext = this.getSafeImageExtension(file.originalname);
      const filename = `${safeReceipt}-${i}${ext}`;
      const filePath = path.join(receiptDir, filename);

      await fs.promises.writeFile(filePath, file.buffer);
      links.push(`${this.baseUrl}/${safeReceipt}/${filename}`);

      this.logger.log(`Saved image: ${filePath}`);
    }

    return links;
  }

  async upsertWarrantyRecord(receipt: string, links: string[], userId: string) {
    const linksStr = this.getLinksString(links);

    return this.prisma.warranty.upsert({
      where: { receipt },
      update: {
        imageLinks: linksStr,
      },
      create: {
        receipt,
        imageLinks: linksStr,
        createdById: userId,
      },
    });
  }

  async saveFeedbackImages(
    feedbackId: string,
    files: Express.Multer.File[],
  ): Promise<string[]> {
    const safeFeedbackId = this.getSafePathSegment(feedbackId, 'feedbackId');
    const feedbackDir = this.getPathInsideBase('feedback', safeFeedbackId);

    await fs.promises.mkdir(feedbackDir, { recursive: true });

    const links: string[] = [];

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const ext = this.getSafeImageExtension(file.originalname);
      const filename = `${safeFeedbackId}-${i}${ext}`;
      const filePath = path.join(feedbackDir, filename);

      await fs.promises.writeFile(filePath, file.buffer);
      links.push(`${this.baseUrl}/feedback/${safeFeedbackId}/${filename}`);

      this.logger.log(`Saved feedback image: ${filePath}`);
    }

    return links;
  }

  getLinksString(links: string[]): string {
    return links.join(';');
  }

  parseLinksString(linksStr: string): string[] {
    if (!linksStr) return [];
    return linksStr
      .split(';')
      .map((link) => link.trim())
      .filter((link) => link.length > 0);
  }

  private getSafePathSegment(value: string, fieldName: string): string {
    const trimmed = value?.trim();
    if (!trimmed || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(trimmed)) {
      throw new BadRequestException(`${fieldName} không hợp lệ`);
    }
    return trimmed;
  }

  private getPathInsideBase(...segments: string[]): string {
    const basePath = path.resolve(this.baseDir);
    const targetPath = path.resolve(basePath, ...segments);

    if (
      targetPath !== basePath &&
      !targetPath.startsWith(basePath + path.sep)
    ) {
      throw new BadRequestException('Đường dẫn upload không hợp lệ');
    }
    return targetPath;
  }

  private getSafeImageExtension(filename: string): string {
    const ext = path.extname(filename).toLowerCase();
    const allowedExtensions = new Set([
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.heif',
    ]);
    return allowedExtensions.has(ext) ? ext : '.jpg';
  }
}
