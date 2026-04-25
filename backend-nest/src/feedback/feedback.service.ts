import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UploadService } from '../upload/upload.service';

@Injectable()
export class FeedbackService {
  constructor(
    private prisma: PrismaService,
    private uploadService: UploadService,
  ) {}

  async create(
    userId: string,
    data: {
      content?: string;
      functionName?: string;
      description?: string;
      rating?: number;
    },
    files: Express.Multer.File[] = [],
  ) {
    const baseContent = this.buildContent(data);
    const feedback = await this.prisma.feedback.create({
      data: { userId, content: baseContent, rating: Number(data.rating ?? 5) },
    });

    if (files.length === 0) return feedback;

    const links = await this.uploadService.saveFeedbackImages(
      feedback.id,
      files,
    );
    return this.prisma.feedback.update({
      where: { id: feedback.id },
      data: {
        content: `${baseContent}\nHình ảnh: ${links.join(';')}`,
      },
    });
  }

  async getAll() {
    return this.prisma.feedback.findMany({
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { email: true, firstName: true } } },
    });
  }

  private buildContent(data: {
    content?: string;
    functionName?: string;
    description?: string;
  }) {
    if (data.content?.trim()) return data.content.trim();

    const parts = [
      data.functionName?.trim()
        ? `Chức năng: ${data.functionName.trim()}`
        : null,
      data.description?.trim() ? `Mô tả: ${data.description.trim()}` : null,
    ].filter(Boolean);

    return parts.join('\n') || 'Không có nội dung';
  }
}
