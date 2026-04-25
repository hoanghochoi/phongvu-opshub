import { Injectable, Logger } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UploadService {
  private readonly logger = new Logger(UploadService.name);

  // Base directory for images (same pattern as n8n: /data/app_images)
  private readonly baseDir = process.env.UPLOAD_BASE_DIR || '/data/app_images';
  private readonly baseUrl =
    process.env.IMAGE_BASE_URL || 'https://img.hoanghochoi.com';

  constructor(private prisma: PrismaService) {}

  async saveWarrantyImages(
    receipt: string,
    files: Express.Multer.File[],
  ): Promise<string[]> {
    const receiptDir = path.join(this.baseDir, receipt);

    if (!fs.existsSync(receiptDir)) {
      fs.mkdirSync(receiptDir, { recursive: true });
    }

    const links: string[] = [];

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
      const filename = `${receipt}-${i}${ext}`;
      const filePath = path.join(receiptDir, filename);

      fs.writeFileSync(filePath, file.buffer);
      links.push(`${this.baseUrl}/${receipt}/${filename}`);

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
    const feedbackDir = path.join(this.baseDir, 'feedback', feedbackId);

    if (!fs.existsSync(feedbackDir)) {
      fs.mkdirSync(feedbackDir, { recursive: true });
    }

    const links: string[] = [];

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
      const filename = `${feedbackId}-${i}${ext}`;
      const filePath = path.join(feedbackDir, filename);

      fs.writeFileSync(filePath, file.buffer);
      links.push(`${this.baseUrl}/feedback/${feedbackId}/${filename}`);

      this.logger.log(`Saved feedback image: ${filePath}`);
    }

    return links;
  }

  getLinksString(links: string[]): string {
    return links.join(';');
  }

  parseLinksString(linksStr: string): string[] {
    if (!linksStr) return [];
    return linksStr.split(';').filter((l) => l.trim().length > 0);
  }
}
