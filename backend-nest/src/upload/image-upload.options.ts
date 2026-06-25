import { BadRequestException } from '@nestjs/common';
import { memoryStorage, type Options } from 'multer';

const DEFAULT_IMAGE_UPLOAD_MAX_BYTES = 10 * 1024 * 1024;
const DEFAULT_AVATAR_UPLOAD_MAX_BYTES = 2 * 1024 * 1024;
export const IMAGE_UPLOAD_MAX_FILES = 20;
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
  return getPositiveByteLimit(
    env,
    'UPLOAD_MAX_BYTES',
    DEFAULT_IMAGE_UPLOAD_MAX_BYTES,
  );
}

export function getAvatarUploadMaxBytes(
  env: Record<string, string | undefined> = process.env,
): number {
  return getPositiveByteLimit(
    env,
    'AVATAR_UPLOAD_MAX_BYTES',
    DEFAULT_AVATAR_UPLOAD_MAX_BYTES,
  );
}

function getPositiveByteLimit(
  env: Record<string, string | undefined>,
  envKey: string,
  fallback: number,
): number {
  const rawValue = env[envKey]?.trim();
  if (!rawValue) {
    return fallback;
  }

  const value = Number(rawValue);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`Invalid ${envKey} value: ${rawValue}`);
  }
  return value;
}

const imageFileFilter: Options['fileFilter'] = (_req, file, callback) => {
  if (!ALLOWED_IMAGE_MIME_TYPES.has(file.mimetype)) {
    callback(new BadRequestException('Chỉ cho phép upload file ảnh'));
    return;
  }
  callback(null, true);
};

export const imageUploadOptions: Options = {
  storage: memoryStorage(),
  limits: {
    files: IMAGE_UPLOAD_MAX_FILES,
    fileSize: getImageUploadMaxBytes(),
  },
  fileFilter: imageFileFilter,
};

export const avatarUploadOptions: Options = {
  storage: memoryStorage(),
  limits: {
    fileSize: getAvatarUploadMaxBytes(),
  },
  fileFilter: imageFileFilter,
};
