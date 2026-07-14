import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { createHash } from 'crypto';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import { getAvatarUploadMaxBytes } from './image-upload.options';
import {
  PRIVATE_MEDIA_OWNER,
  PrivateMediaService,
} from './private-media.service';

@Injectable()
export class UploadService {
  private readonly logger = new Logger(UploadService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly privateMediaService: PrivateMediaService,
  ) {}

  async saveWarrantyImages(
    receipt: string,
    files: Express.Multer.File[],
    userId: string,
  ): Promise<string[]> {
    const startedAt = Date.now();
    const safeReceipt = this.getSafePathSegment(receipt, 'Mã biên nhận');
    const safeFiles = this.requireFileArray(files);
    this.logger.log(
      `Warranty image upload started: userIdHash=${this.logId(userId)} receiptLength=${safeReceipt.length} fileCount=${safeFiles.length}`,
    );

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, storeId: true, role: true },
    });
    if (!user) {
      throw new ForbiddenException('Phiên làm việc không còn hợp lệ.');
    }

    const warranty = await this.prisma.warranty.upsert({
      where: { receipt: safeReceipt },
      update: {},
      create: { receipt: safeReceipt, createdById: userId },
      select: {
        id: true,
        createdById: true,
        imageLinks: true,
        createdBy: { select: { storeId: true } },
      },
    });
    if (
      !isSuperAdminRole(user.role) &&
      (!user.storeId || warranty.createdBy.storeId !== user.storeId)
    ) {
      this.logger.warn(
        `Warranty image upload denied: userIdHash=${this.logId(userId)} warrantyIdHash=${this.logId(warranty.id)} reason=store_scope`,
      );
      throw new ForbiddenException(
        'Bạn không có quyền cập nhật ảnh cho biên nhận này.',
      );
    }

    const urls = await this.privateMediaService.saveImages({
      ownerFeature: PRIVATE_MEDIA_OWNER.WARRANTY,
      ownerRecordId: warranty.id,
      uploaderId: userId,
      files: safeFiles,
    });
    try {
      await this.prisma.warranty.update({
        where: { id: warranty.id },
        data: { imageLinks: this.getLinksString(urls) },
      });
    } catch (error) {
      await this.privateMediaService.discardUrls(urls);
      throw error;
    }
    const previousUrls = this.parseLinksString(warranty.imageLinks || '').filter(
      (url) => !urls.includes(url),
    );
    await this.privateMediaService.discardUrls(previousUrls);

    this.logger.log(
      `Warranty image upload succeeded: userIdHash=${this.logId(userId)} warrantyIdHash=${this.logId(warranty.id)} fileCount=${urls.length} durationMs=${Date.now() - startedAt}`,
    );
    return urls;
  }

  async saveFeedbackImages(
    feedbackId: string,
    files: Express.Multer.File[],
    uploaderId: string,
  ): Promise<string[]> {
    const safeFeedbackId = this.getSafePathSegment(feedbackId, 'Mã góp ý');
    return this.privateMediaService.saveImages({
      ownerFeature: PRIVATE_MEDIA_OWNER.FEEDBACK,
      ownerRecordId: safeFeedbackId,
      uploaderId,
      files,
    });
  }

  async saveUserAvatar(
    userId: string,
    file: Express.Multer.File,
  ): Promise<string> {
    const safeUserId = this.getSafePathSegment(userId, 'Mã người dùng');
    const [url] = await this.privateMediaService.saveImages({
      ownerFeature: PRIVATE_MEDIA_OWNER.AVATAR,
      ownerRecordId: safeUserId,
      uploaderId: safeUserId,
      files: [file],
      maxBytesPerFile: getAvatarUploadMaxBytes(),
    });
    if (!url) {
      throw new BadRequestException('Vui lòng chọn ảnh đại diện.');
    }
    return url;
  }

  async saveHelpContentImage(
    pageKey: string | null | undefined,
    file: Express.Multer.File,
  ): Promise<string> {
    const safePageKey = this.getSafePathSegment(
      pageKey?.trim() || 'general',
      'Mã trang hướng dẫn',
    );
    return this.privateMediaService.savePublicHelpImage(safePageKey, file);
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

  async discardPrivateMedia(urls: string[]) {
    await this.privateMediaService.discardUrls(urls);
  }

  private getSafePathSegment(value: unknown, fieldLabel: string): string {
    const trimmed = typeof value === 'string' ? value.trim() : '';
    if (!trimmed || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(trimmed)) {
      throw new BadRequestException(`${fieldLabel} không hợp lệ.`);
    }
    return trimmed;
  }

  private requireFileArray(value: unknown): Express.Multer.File[] {
    if (!Array.isArray(value)) {
      throw new BadRequestException('Danh sách ảnh tải lên không hợp lệ.');
    }
    return value;
  }

  private logId(value: unknown): string {
    const safeValue = typeof value === 'string' ? value : 'unknown';
    return createHash('sha256').update(safeValue).digest('hex').slice(0, 12);
  }
}
