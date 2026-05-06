import { BadRequestException } from '@nestjs/common';
import { memoryStorage, type Options } from 'multer';

const DEFAULT_IMAGE_UPLOAD_MAX_BYTES = 5 * 1024 * 1024;
const ALLOWED_IMAGE_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
]);

export function getImageUploadMaxBytes(
  env: Record<string, string | undefined> = process.env,
): number {
  const rawValue = env.UPLOAD_MAX_BYTES?.trim();
  if (!rawValue) {
    return DEFAULT_IMAGE_UPLOAD_MAX_BYTES;
  }

  const value = Number(rawValue);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`Invalid UPLOAD_MAX_BYTES value: ${rawValue}`);
  }
  return value;
}

export const imageUploadOptions: Options = {
  storage: memoryStorage(),
  limits: {
    files: 10,
    fileSize: getImageUploadMaxBytes(),
  },
  fileFilter: (_req, file, callback) => {
    if (!ALLOWED_IMAGE_MIME_TYPES.has(file.mimetype)) {
      callback(new BadRequestException('Chỉ cho phép upload file ảnh'));
      return;
    }
    callback(null, true);
  },
};
