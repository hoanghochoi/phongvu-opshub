import { BadRequestException } from '@nestjs/common';
import { memoryStorage, type Options } from 'multer';

const DEFAULT_USER_IMPORT_UPLOAD_MAX_BYTES = 5 * 1024 * 1024;
const ALLOWED_EXTENSIONS = new Set(['.xlsx', '.xls']);
const ALLOWED_MIME_TYPES = new Set([
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel',
  'application/octet-stream',
]);

export const userImportFileUploadOptions: Options = {
  storage: memoryStorage(),
  limits: {
    files: 1,
    fileSize:
      Number(process.env.USER_IMPORT_UPLOAD_MAX_BYTES?.trim()) ||
      DEFAULT_USER_IMPORT_UPLOAD_MAX_BYTES,
  },
  fileFilter: (_req, file, callback) => {
    const lowerName = file.originalname.toLowerCase();
    const hasAllowedExtension = Array.from(ALLOWED_EXTENSIONS).some(
      (extension) => lowerName.endsWith(extension),
    );
    if (!hasAllowedExtension || !ALLOWED_MIME_TYPES.has(file.mimetype)) {
      callback(
        new BadRequestException('Chỉ cho phép upload file Excel nhân sự'),
      );
      return;
    }
    callback(null, true);
  },
};
