import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { createHash, randomUUID } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import sharp from 'sharp';
import { isSuperAdminRole } from '../common/system-role';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  getImageUploadAggregateMaxBytes,
  getImageUploadMaxBytes,
  getPrivateUploadTempDir,
} from './image-upload.options';

export const PRIVATE_MEDIA_OWNER = {
  WARRANTY: 'WARRANTY',
  FEEDBACK: 'FEEDBACK',
  AVATAR: 'AVATAR',
} as const;

export type PrivateMediaOwner =
  (typeof PRIVATE_MEDIA_OWNER)[keyof typeof PRIVATE_MEDIA_OWNER];

type NormalizedImage = {
  buffer: Buffer;
  contentType: string;
  extension: string;
  originalName: string;
};

type SavedMedia = {
  id: string;
  storageKey: string;
  url: string;
};

@Injectable()
export class PrivateMediaService implements OnModuleInit {
  private readonly logger = new Logger(PrivateMediaService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly featureService: FeatureService,
  ) {}

  async onModuleInit() {
    await this.ensureDirectory(this.privateBaseDir(), 0o750);
    await this.ensureDirectory(getPrivateUploadTempDir(), 0o700);
    await this.cleanupAbandonedTemporaryUploads();
  }

  async saveImages(input: {
    ownerFeature: PrivateMediaOwner;
    ownerRecordId: string;
    uploaderId: string;
    files: Express.Multer.File[];
    maxBytesPerFile?: number;
  }): Promise<string[]> {
    const startedAt = Date.now();
    const files = input.files || [];
    if (files.length === 0) return [];

    const aggregateBytes = await this.aggregateInputBytes(files);
    const aggregateLimit = getImageUploadAggregateMaxBytes();
    if (aggregateBytes > aggregateLimit) {
      await this.cleanupManagedTemporaryFiles(files);
      this.logger.warn(
        `Private media upload rejected: ownerFeature=${input.ownerFeature} uploaderId=${input.uploaderId} fileCount=${files.length} aggregateBytes=${aggregateBytes} reason=aggregate_limit`,
      );
      throw new BadRequestException(
        'Tổng dung lượng ảnh quá lớn. Vui lòng giảm số lượng hoặc kích thước ảnh.',
      );
    }

    const saved: SavedMedia[] = [];
    try {
      for (const file of files) {
        const normalized = await this.normalizeImage(
          file,
          input.maxBytesPerFile ?? getImageUploadMaxBytes(),
        );
        const media = await this.persistPrivateImage({
          ...input,
          normalized,
        });
        saved.push(media);
      }
      this.logger.log(
        `Private media upload succeeded: ownerFeature=${input.ownerFeature} ownerRecordId=${input.ownerRecordId} uploaderId=${input.uploaderId} fileCount=${saved.length} aggregateBytes=${aggregateBytes} durationMs=${Date.now() - startedAt}`,
      );
      return saved.map((item) => item.url);
    } catch (error) {
      await this.discardSavedMedia(saved);
      this.logger.warn(
        `Private media upload failed: ownerFeature=${input.ownerFeature} ownerRecordId=${input.ownerRecordId} uploaderId=${input.uploaderId} fileCount=${files.length} savedCount=${saved.length} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      if (error instanceof BadRequestException) throw error;
      throw new BadRequestException(
        'Chưa lưu được ảnh. Vui lòng kiểm tra tệp và thử lại.',
      );
    } finally {
      await this.cleanupManagedTemporaryFiles(files);
    }
  }

  async savePublicHelpImage(
    pageKey: string,
    file: Express.Multer.File,
  ): Promise<string> {
    try {
      const normalized = await this.normalizeImage(
        file,
        getImageUploadMaxBytes(),
      );
      const filename = `${randomUUID()}.${normalized.extension}`;
      const directory = this.publicPath('help-content', pageKey);
      await this.ensureDirectory(directory, 0o755);
      const target = this.pathInside(directory, filename);
      await this.writeAtomic(target, normalized.buffer, 0o644);
      this.logger.log(
        `Public help image saved: pageKey=${pageKey} bytes=${normalized.buffer.length}`,
      );
      return `${this.imageBaseUrl()}/help-content/${encodeURIComponent(pageKey)}/${filename}`;
    } finally {
      await this.cleanupManagedTemporaryFiles([file]);
    }
  }

  async openForUser(mediaId: string, user: any) {
    const media = await this.prisma.mediaObject.findFirst({
      where: {
        id: mediaId,
        visibility: 'PRIVATE',
        deletedAt: null,
        OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
      },
    });
    if (!media) {
      this.logAccessDenied(mediaId, user, 'not_found');
      throw this.mediaNotFound();
    }

    const allowed = await this.canReadOwner(media, user);
    if (!allowed) {
      this.logAccessDenied(mediaId, user, 'scope_denied');
      throw this.mediaNotFound();
    }

    let filePath: string;
    try {
      filePath = this.privatePath(media.storageKey);
    } catch (error) {
      this.logger.error(
        `Private media storage key rejected: mediaId=${this.mediaLogId(mediaId)} error=${this.safeError(error)}`,
      );
      throw this.mediaNotFound();
    }
    let stat: fs.Stats;
    try {
      stat = await fs.promises.stat(filePath);
    } catch {
      this.logger.error(
        `Private media file missing: mediaId=${this.mediaLogId(mediaId)} ownerFeature=${media.ownerFeature}`,
      );
      throw this.mediaNotFound();
    }
    if (!stat.isFile() || stat.size !== media.sizeBytes) {
      this.logger.error(
        `Private media integrity mismatch: mediaId=${this.mediaLogId(mediaId)} expectedBytes=${media.sizeBytes} actualBytes=${stat.size}`,
      );
      throw this.mediaNotFound();
    }
    const checksum = await this.hashFile(filePath);
    if (checksum !== media.checksumSha256) {
      this.logger.error(
        `Private media checksum mismatch: mediaId=${this.mediaLogId(mediaId)}`,
      );
      throw this.mediaNotFound();
    }

    this.logger.log(
      `Private media access allowed: mediaId=${this.mediaLogId(mediaId)} ownerFeature=${media.ownerFeature} userId=${user?.id ?? 'unknown'} bytes=${stat.size}`,
    );
    return { media, filePath, size: stat.size };
  }

  async discardUrls(urls: string[]) {
    const ids = urls
      .map((url) => this.mediaIdFromUrl(url))
      .filter(Boolean) as string[];
    if (ids.length === 0) return;
    const media = await this.prisma.mediaObject.findMany({
      where: { id: { in: ids }, deletedAt: null },
    });
    await this.discardSavedMedia(
      media.map((item) => ({
        id: item.id,
        storageKey: item.storageKey,
        url: this.publicUrl(item.id),
      })),
    );
  }

  publicUrl(mediaId: string) {
    return `${this.publicMediaBaseUrl()}/media/${mediaId}`;
  }

  private async persistPrivateImage(input: {
    ownerFeature: PrivateMediaOwner;
    ownerRecordId: string;
    uploaderId: string;
    normalized: NormalizedImage;
  }): Promise<SavedMedia> {
    const id = randomUUID();
    const storageKey = path.posix.join(
      input.ownerFeature.toLowerCase(),
      id.slice(0, 2),
      `${id}.${input.normalized.extension}`,
    );
    const target = this.privatePath(storageKey);
    await this.ensureDirectory(path.dirname(target), 0o750);
    await this.writeAtomic(target, input.normalized.buffer, 0o600);

    try {
      await this.prisma.mediaObject.create({
        data: {
          id,
          storageKey,
          ownerFeature: input.ownerFeature,
          ownerRecordId: input.ownerRecordId,
          uploaderId: input.uploaderId,
          originalName: input.normalized.originalName,
          contentTypeVerified: input.normalized.contentType,
          sizeBytes: input.normalized.buffer.length,
          checksumSha256: createHash('sha256')
            .update(input.normalized.buffer)
            .digest('hex'),
          visibility: 'PRIVATE',
        },
      });
    } catch (error) {
      await fs.promises.unlink(target).catch(() => undefined);
      throw error;
    }
    return { id, storageKey, url: this.publicUrl(id) };
  }

  private async normalizeImage(
    file: Express.Multer.File,
    maxBytes: number,
  ): Promise<NormalizedImage> {
    const source = file.path?.trim() || file.buffer;
    if (!source) {
      throw new BadRequestException('Không đọc được tệp ảnh đã chọn.');
    }

    const inputBytes = await this.inputSize(file);
    if (inputBytes < 1 || inputBytes > maxBytes) {
      throw new BadRequestException(
        'Ảnh vượt quá dung lượng cho phép. Vui lòng chọn ảnh nhỏ hơn.',
      );
    }

    try {
      const pipeline = sharp(source, {
        failOn: 'warning',
        limitInputPixels: this.maxInputPixels(),
        sequentialRead: true,
      });
      const metadata = await pipeline.metadata();
      const format = metadata.format;
      if (!format || !['jpeg', 'png', 'webp', 'heif'].includes(format)) {
        throw new Error('unsupported_format');
      }
      if (
        !metadata.width ||
        !metadata.height ||
        metadata.width * metadata.height > this.maxInputPixels() ||
        (metadata.pages ?? 1) !== 1
      ) {
        throw new Error('invalid_dimensions');
      }

      let output = pipeline.rotate();
      let contentType: string;
      let extension: string;
      if (format === 'png') {
        output = output.png({ compressionLevel: 9, adaptiveFiltering: true });
        contentType = 'image/png';
        extension = 'png';
      } else if (format === 'webp') {
        output = output.webp({ quality: 88 });
        contentType = 'image/webp';
        extension = 'webp';
      } else {
        output = output.jpeg({ quality: 88, mozjpeg: true });
        contentType = 'image/jpeg';
        extension = 'jpg';
      }
      const buffer = await output.toBuffer();
      if (buffer.length < 1 || buffer.length > maxBytes) {
        throw new Error('normalized_size_exceeded');
      }
      return {
        buffer,
        contentType,
        extension,
        originalName: this.safeOriginalName(file.originalname),
      };
    } catch (error) {
      this.logger.warn(
        `Private media decode rejected: inputBytes=${inputBytes} mime=${this.safeMime(file.mimetype)} error=${this.safeError(error)}`,
      );
      throw new BadRequestException(
        'Tệp đã chọn không phải ảnh hợp lệ hoặc ảnh có kích thước quá lớn.',
      );
    }
  }

  private async canReadOwner(media: any, user: any) {
    if (!user?.id) return false;
    if (media.ownerFeature === PRIVATE_MEDIA_OWNER.AVATAR) {
      return media.ownerRecordId === user.id || isSuperAdminRole(user.role);
    }
    if (media.ownerFeature === PRIVATE_MEDIA_OWNER.FEEDBACK) {
      return (
        isSuperAdminRole(user.role) &&
        (await this.featureService.canAccessFeature(
          user,
          FEATURE_KEYS.ADMIN_FEEDBACK,
        ))
      );
    }
    if (media.ownerFeature === PRIVATE_MEDIA_OWNER.WARRANTY) {
      if (
        !(await this.featureService.canAccessFeature(
          user,
          FEATURE_KEYS.WARRANTY,
        ))
      ) {
        return false;
      }
      if (isSuperAdminRole(user.role)) {
        return Boolean(
          await this.prisma.warranty.findUnique({
            where: { id: media.ownerRecordId },
            select: { id: true },
          }),
        );
      }
      if (!user.storeId) return false;
      return Boolean(
        await this.prisma.warranty.findFirst({
          where: {
            id: media.ownerRecordId,
            createdBy: { storeId: user.storeId },
          },
          select: { id: true },
        }),
      );
    }
    return false;
  }

  private async discardSavedMedia(saved: SavedMedia[]) {
    for (const item of [...saved].reverse()) {
      await this.prisma.mediaObject
        .updateMany({
          where: { id: item.id, deletedAt: null },
          data: { deletedAt: new Date() },
        })
        .catch((error) =>
          this.logger.error(
            `Private media rollback metadata failed: mediaId=${this.mediaLogId(item.id)} error=${this.safeError(error)}`,
          ),
        );
      await fs.promises
        .unlink(this.privatePath(item.storageKey))
        .catch((error: NodeJS.ErrnoException) => {
          if (error.code !== 'ENOENT') {
            this.logger.error(
              `Private media rollback file failed: mediaId=${this.mediaLogId(item.id)} error=${this.safeError(error)}`,
            );
          }
        });
    }
  }

  private async aggregateInputBytes(files: Express.Multer.File[]) {
    const sizes = await Promise.all(files.map((file) => this.inputSize(file)));
    return sizes.reduce((total, size) => total + size, 0);
  }

  private async inputSize(file: Express.Multer.File) {
    if (Number.isSafeInteger(file.size) && file.size >= 0) return file.size;
    if (file.buffer) return file.buffer.length;
    if (file.path) return (await fs.promises.stat(file.path)).size;
    return 0;
  }

  private async cleanupManagedTemporaryFiles(files: Express.Multer.File[]) {
    const tempBase = getPrivateUploadTempDir();
    await Promise.all(
      files.map(async (file) => {
        if (!file.path) return;
        const resolved = path.resolve(file.path);
        if (!this.isInside(tempBase, resolved)) return;
        await fs.promises.unlink(resolved).catch(() => undefined);
      }),
    );
  }

  private async cleanupAbandonedTemporaryUploads() {
    const directory = getPrivateUploadTempDir();
    const cutoff = Date.now() - 24 * 60 * 60 * 1000;
    let removed = 0;
    for (const entry of await fs.promises.readdir(directory, {
      withFileTypes: true,
    })) {
      if (!entry.isFile()) continue;
      const target = this.pathInside(directory, entry.name);
      const stat = await fs.promises.stat(target).catch(() => null);
      if (!stat || stat.mtimeMs >= cutoff) continue;
      await fs.promises.unlink(target).catch(() => undefined);
      removed += 1;
    }
    if (removed > 0) {
      this.logger.warn(`Private upload stale files removed: count=${removed}`);
    }
  }

  private privateBaseDir() {
    return path.resolve(
      process.env.PRIVATE_MEDIA_BASE_DIR?.trim() || '/data/private-media',
    );
  }

  private publicBaseDir() {
    return path.resolve(
      process.env.UPLOAD_BASE_DIR?.trim() || '/data/app_images',
    );
  }

  private publicMediaBaseUrl() {
    const value =
      process.env.PRIVATE_MEDIA_PUBLIC_BASE_URL?.trim() ||
      process.env.PUBLIC_BASE_URL?.trim() ||
      'http://localhost:3000';
    return value.replace(/\/+$/, '');
  }

  private imageBaseUrl() {
    return (
      process.env.IMAGE_BASE_URL?.trim() || 'http://localhost:3000/uploads'
    ).replace(/\/+$/, '');
  }

  private privatePath(storageKey: string) {
    return this.pathInside(this.privateBaseDir(), ...storageKey.split('/'));
  }

  private publicPath(...segments: string[]) {
    return this.pathInside(this.publicBaseDir(), ...segments);
  }

  private pathInside(baseDir: string, ...segments: string[]) {
    const base = path.resolve(baseDir);
    const target = path.resolve(base, ...segments);
    if (!this.isInside(base, target)) {
      throw new BadRequestException('Đường dẫn lưu ảnh không hợp lệ.');
    }
    return target;
  }

  private isInside(baseDir: string, target: string) {
    const base = path.resolve(baseDir);
    const resolved = path.resolve(target);
    return resolved === base || resolved.startsWith(base + path.sep);
  }

  private async ensureDirectory(directory: string, mode: number) {
    await fs.promises.mkdir(directory, { recursive: true, mode });
    await fs.promises.chmod(directory, mode).catch(() => undefined);
  }

  private async writeAtomic(target: string, data: Buffer, mode: number) {
    const temporary = `${target}.tmp-${randomUUID()}`;
    try {
      await fs.promises.writeFile(temporary, data, { flag: 'wx', mode });
      await fs.promises.rename(temporary, target);
      await fs.promises.chmod(target, mode).catch(() => undefined);
    } catch (error) {
      await fs.promises.unlink(temporary).catch(() => undefined);
      throw error;
    }
  }

  private async hashFile(filePath: string) {
    const hash = createHash('sha256');
    const stream = fs.createReadStream(filePath);
    for await (const chunk of stream) hash.update(chunk);
    return hash.digest('hex');
  }

  private maxInputPixels() {
    const parsed = Number(process.env.PRIVATE_MEDIA_MAX_PIXELS);
    return Number.isSafeInteger(parsed) && parsed >= 1_000_000
      ? parsed
      : 24_000_000;
  }

  private safeOriginalName(value: string) {
    return path
      .basename(String(value || 'image'))
      .replace(/[\u0000-\u001f\u007f]/g, '')
      .slice(0, 255);
  }

  private safeMime(value: string) {
    return String(value || 'unknown')
      .replace(/[^a-z0-9/+.-]/gi, '')
      .slice(0, 80);
  }

  private mediaIdFromUrl(value: string) {
    try {
      const segments = new URL(value).pathname.split('/').filter(Boolean);
      const mediaIndex = segments.lastIndexOf('media');
      return mediaIndex >= 0 ? segments[mediaIndex + 1] || null : null;
    } catch {
      return null;
    }
  }

  private logAccessDenied(mediaId: string, user: any, reason: string) {
    this.logger.warn(
      `Private media access denied: mediaId=${this.mediaLogId(mediaId)} userId=${user?.id ?? 'unknown'} reason=${reason}`,
    );
  }

  private mediaLogId(value: string) {
    return createHash('sha256').update(value).digest('hex').slice(0, 12);
  }

  private mediaNotFound() {
    return new NotFoundException(
      'Không tìm thấy ảnh hoặc bạn không có quyền xem.',
    );
  }

  private safeError(error: unknown) {
    return String(error instanceof Error ? error.message : error)
      .replace(/[\r\n]+/g, ' ')
      .slice(0, 240);
  }
}
