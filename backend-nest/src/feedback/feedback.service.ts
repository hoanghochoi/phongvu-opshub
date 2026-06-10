import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UploadService } from '../upload/upload.service';

@Injectable()
export class FeedbackService {
  private readonly logger = new Logger(FeedbackService.name);

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

  async getAll(admin: any) {
    if (admin?.role !== 'SUPER_ADMIN') {
      this.logger.warn(
        'Feedback admin list blocked: user=' +
          (admin?.email || admin?.id || 'unknown') +
          ' role=' +
          (admin?.role || 'unknown'),
      );
      throw new ForbiddenException(
        'Chỉ SUPER_ADMIN được xem danh sách phản hồi',
      );
    }
    this.logger.log(
      'Feedback admin list started: admin=' +
        (admin?.email || admin?.id || 'unknown'),
    );
    const feedback = await this.prisma.feedback.findMany({
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { email: true, firstName: true } } },
    });
    this.logger.log(
      'Feedback admin list completed: admin=' +
        (admin?.email || admin?.id || 'unknown') +
        ' count=' +
        feedback.length,
    );
    return feedback;
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
