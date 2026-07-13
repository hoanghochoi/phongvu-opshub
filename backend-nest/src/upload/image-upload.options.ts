import { BadRequestException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { diskStorage, type Options } from 'multer';

const DEFAULT_IMAGE_UPLOAD_MAX_BYTES = 10 * 1024 * 1024;
const DEFAULT_AVATAR_UPLOAD_MAX_BYTES = 2 * 1024 * 1024;
export const IMAGE_UPLOAD_MAX_FILES = 20;
const DEFAULT_IMAGE_UPLOAD_AGGREGATE_MAX_BYTES = 30 * 1024 * 1024;
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

export function getImageUploadAggregateMaxBytes(
  env: Record<string, string | undefined> = process.env,
): number {
  return getPositiveByteLimit(
    env,
    'UPLOAD_AGGREGATE_MAX_BYTES',
    DEFAULT_IMAGE_UPLOAD_AGGREGATE_MAX_BYTES,
  );
}

export function getPrivateUploadTempDir(
  env: Record<string, string | undefined> = process.env,
): string {
  return path.resolve(
    env.PRIVATE_UPLOAD_TEMP_DIR?.trim() ||
      path.join(os.tmpdir(), 'opshub-private-uploads'),
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

const privateUploadStorage = diskStorage({
  destination: (_req, _file, callback) => {
    const destination = getPrivateUploadTempDir();
    try {
      fs.mkdirSync(destination, { recursive: true, mode: 0o700 });
      fs.chmodSync(destination, 0o700);
      callback(null, destination);
    } catch (error) {
      callback(error as Error, destination);
    }
  },
  filename: (_req, _file, callback) => callback(null, randomUUID()),
});

const boundedMultipartLimits = {
  fields: 8,
  fieldNameSize: 64,
  fieldSize: 8 * 1024,
};

export const imageUploadOptions: Options = {
  storage: privateUploadStorage,
  limits: {
    ...boundedMultipartLimits,
    files: IMAGE_UPLOAD_MAX_FILES,
    fileSize: getImageUploadMaxBytes(),
    parts: IMAGE_UPLOAD_MAX_FILES + boundedMultipartLimits.fields,
  },
  fileFilter: imageFileFilter,
};

export const avatarUploadOptions: Options = {
  storage: privateUploadStorage,
  limits: {
    ...boundedMultipartLimits,
    files: 1,
    fileSize: getAvatarUploadMaxBytes(),
    parts: 1 + boundedMultipartLimits.fields,
  },
  fileFilter: imageFileFilter,
};
