import { NotFoundException } from '@nestjs/common';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import sharp from 'sharp';
import {
  PrivateMediaService,
  PRIVATE_MEDIA_OWNER,
} from './private-media.service';

describe('PrivateMediaService', () => {
  let root: string;
  let prisma: any;
  let featureService: any;
  let service: PrivateMediaService;
  let createdMedia: any;
  const originalEnv = { ...process.env };

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'opshub-private-media-'));
    process.env.PRIVATE_MEDIA_BASE_DIR = path.join(root, 'private');
    process.env.PRIVATE_UPLOAD_TEMP_DIR = path.join(root, 'temporary');
    process.env.UPLOAD_BASE_DIR = path.join(root, 'public');
    process.env.PRIVATE_MEDIA_PUBLIC_BASE_URL = 'https://api.example.com/api';
    process.env.IMAGE_BASE_URL = 'https://api.example.com/uploads';
    delete process.env.UPLOAD_AGGREGATE_MAX_BYTES;
    delete process.env.PRIVATE_MEDIA_MAX_PIXELS;

    createdMedia = null;
    prisma = {
      mediaObject: {
        create: jest.fn().mockImplementation(async ({ data }: any) => {
          createdMedia = data;
          return data;
        }),
        findFirst: jest.fn().mockImplementation(async () => createdMedia),
        findMany: jest.fn().mockResolvedValue([]),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      warranty: {
        findUnique: jest.fn(),
        findFirst: jest.fn(),
      },
    };
    featureService = { canAccessFeature: jest.fn().mockResolvedValue(true) };
    service = new PrivateMediaService(prisma, featureService);
  });

  afterEach(() => {
    process.env = { ...originalEnv };
    fs.rmSync(root, { recursive: true, force: true });
  });

  it('decodes and re-encodes a valid image under an opaque private key', async () => {
    const source = await sharp({
      create: {
        width: 24,
        height: 16,
        channels: 3,
        background: { r: 10, g: 20, b: 30 },
      },
    })
      .png()
      .toBuffer();
    const file = multerFile({
      buffer: source,
      originalname: 'customer-receipt.heic',
      mimetype: 'image/heic',
    });

    const [url] = await service.saveImages({
      ownerFeature: PRIVATE_MEDIA_OWNER.WARRANTY,
      ownerRecordId: 'warranty-1',
      uploaderId: 'user-1',
      files: [file],
    });

    expect(url).toMatch(
      /^https:\/\/api\.example\.com\/api\/media\/[0-9a-f-]{36}$/,
    );
    expect(createdMedia).toMatchObject({
      ownerFeature: 'WARRANTY',
      ownerRecordId: 'warranty-1',
      uploaderId: 'user-1',
      contentTypeVerified: 'image/png',
      visibility: 'PRIVATE',
      originalName: 'customer-receipt.heic',
    });
    expect(createdMedia.storageKey).not.toContain('customer-receipt');
    const storedPath = path.join(
      process.env.PRIVATE_MEDIA_BASE_DIR!,
      ...createdMedia.storageKey.split('/'),
    );
    expect(fs.existsSync(storedPath)).toBe(true);
    await expect(sharp(storedPath).metadata()).resolves.toMatchObject({
      format: 'png',
      width: 24,
      height: 16,
    });
  });

  it('rejects spoofed image bytes before metadata is created', async () => {
    const file = multerFile({
      buffer: Buffer.from('<script>alert(1)</script>'),
      originalname: 'attack.jpg',
      mimetype: 'image/jpeg',
    });

    await expect(
      service.saveImages({
        ownerFeature: PRIVATE_MEDIA_OWNER.AVATAR,
        ownerRecordId: 'user-1',
        uploaderId: 'user-1',
        files: [file],
      }),
    ).rejects.toThrow('không phải ảnh hợp lệ');
    expect(prisma.mediaObject.create).not.toHaveBeenCalled();
  });

  it('rejects a request above the aggregate byte limit', async () => {
    process.env.UPLOAD_AGGREGATE_MAX_BYTES = '10';
    const file = multerFile({
      buffer: Buffer.alloc(11),
      originalname: 'large.jpg',
      mimetype: 'image/jpeg',
    });

    await expect(
      service.saveImages({
        ownerFeature: PRIVATE_MEDIA_OWNER.AVATAR,
        ownerRecordId: 'user-1',
        uploaderId: 'user-1',
        files: [file],
      }),
    ).rejects.toThrow('Tổng dung lượng ảnh quá lớn');
  });

  it('rejects a non-array multipart file value before processing', async () => {
    await expect(
      service.saveImages({
        ownerFeature: PRIVATE_MEDIA_OWNER.AVATAR,
        ownerRecordId: 'user-1',
        uploaderId: 'user-1',
        files: 'not-an-array',
      } as any),
    ).rejects.toThrow('Danh sách ảnh tải lên không hợp lệ');
    expect(prisma.mediaObject.create).not.toHaveBeenCalled();
  });

  it('removes the managed temporary upload after decoding fails', async () => {
    const tempDir = process.env.PRIVATE_UPLOAD_TEMP_DIR!;
    fs.mkdirSync(tempDir, { recursive: true });
    const tempPath = path.join(
      tempDir,
      '123e4567-e89b-42d3-a456-426614174000',
    );
    fs.writeFileSync(tempPath, 'not-an-image');
    const file = multerFile({
      path: tempPath,
      size: fs.statSync(tempPath).size,
      originalname: 'bad.png',
      mimetype: 'image/png',
    });

    await expect(
      service.saveImages({
        ownerFeature: PRIVATE_MEDIA_OWNER.FEEDBACK,
        ownerRecordId: 'feedback-1',
        uploaderId: 'user-1',
        files: [file],
      }),
    ).rejects.toThrow();
    expect(fs.existsSync(tempPath)).toBe(false);
  });

  it('never reads or deletes a supplied file path outside the managed temp directory', async () => {
    const outsideDir = path.join(root, 'outside');
    fs.mkdirSync(outsideDir, { recursive: true });
    const outsidePath = path.join(
      outsideDir,
      '123e4567-e89b-12d3-a456-426614174000',
    );
    fs.writeFileSync(outsidePath, 'not-an-image');
    const file = multerFile({
      path: outsidePath,
      size: fs.statSync(outsidePath).size,
      buffer: undefined,
      originalname: 'outside.png',
      mimetype: 'image/png',
    });

    await expect(
      service.saveImages({
        ownerFeature: PRIVATE_MEDIA_OWNER.FEEDBACK,
        ownerRecordId: 'feedback-1',
        uploaderId: 'user-1',
        files: [file],
      }),
    ).rejects.toThrow('Không đọc được tệp ảnh đã chọn');
    expect(fs.existsSync(outsidePath)).toBe(true);
  });

  it('allows only the avatar owner and hides denial as not found', async () => {
    const source = await sharp({
      create: {
        width: 10,
        height: 10,
        channels: 3,
        background: 'blue',
      },
    })
      .jpeg()
      .toBuffer();
    const [url] = await service.saveImages({
      ownerFeature: PRIVATE_MEDIA_OWNER.AVATAR,
      ownerRecordId: 'user-1',
      uploaderId: 'user-1',
      files: [
        multerFile({
          buffer: source,
          originalname: 'avatar.jpg',
          mimetype: 'image/jpeg',
        }),
      ],
    });
    const id = url.split('/').pop()!;

    await expect(
      service.openForUser(id, { id: 'user-1', role: 'USER' }),
    ).resolves.toMatchObject({ size: createdMedia.sizeBytes });
    await expect(
      service.openForUser(id, { id: 'user-2', role: 'USER' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('enforces feature and showroom scope for warranty media', async () => {
    createdMedia = {
      id: 'media-1',
      ownerFeature: PRIVATE_MEDIA_OWNER.WARRANTY,
      ownerRecordId: 'warranty-1',
      deletedAt: null,
      expiresAt: null,
      visibility: 'PRIVATE',
      storageKey: 'warranty/aa/not-used.jpg',
      sizeBytes: 1,
      checksumSha256: 'x',
    };
    prisma.warranty.findFirst.mockResolvedValue({ id: 'warranty-1' });

    await expect(
      service.openForUser('media-1', {
        id: 'user-1',
        role: 'USER',
        storeId: 'store-1',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.warranty.findFirst).toHaveBeenCalledWith({
      where: {
        id: 'warranty-1',
        createdBy: { storeId: 'store-1' },
      },
      select: { id: true },
    });

    featureService.canAccessFeature.mockResolvedValue(false);
    prisma.warranty.findFirst.mockClear();
    await expect(
      service.openForUser('media-1', {
        id: 'user-1',
        role: 'USER',
        storeId: 'store-1',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.warranty.findFirst).not.toHaveBeenCalled();
  });

  it('rejects a corrupted storage key without leaving the private base', async () => {
    createdMedia = {
      id: 'media-1',
      ownerFeature: PRIVATE_MEDIA_OWNER.AVATAR,
      ownerRecordId: 'user-1',
      deletedAt: null,
      expiresAt: null,
      visibility: 'PRIVATE',
      storageKey: '../../outside.jpg',
      sizeBytes: 1,
      checksumSha256: 'x',
    };

    await expect(
      service.openForUser('media-1', { id: 'user-1', role: 'USER' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});

function multerFile(
  values: Partial<Express.Multer.File> &
    Pick<Express.Multer.File, 'originalname' | 'mimetype'>,
): Express.Multer.File {
  const buffer = values.buffer;
  return {
    fieldname: 'images',
    encoding: '7bit',
    destination: '',
    filename: '',
    path: '',
    size: buffer?.length ?? 0,
    stream: null as any,
    buffer: buffer as Buffer,
    ...values,
  };
}
