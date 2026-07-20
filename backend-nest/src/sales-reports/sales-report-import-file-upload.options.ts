import { BadRequestException } from '@nestjs/common';
import { memoryStorage, type Options } from 'multer';

const DEFAULT_MAX_BYTES = 5 * 1024 * 1024;
const ALLOWED_EXTENSIONS = new Set(['.xlsx', '.xls']);
const ALLOWED_MIME_TYPES = new Set([
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel',
  'application/octet-stream',
]);

export const salesReportImportFileUploadOptions: Options = {
  storage: memoryStorage(),
  limits: {
    files: 1,
    fileSize:
      Number(process.env.SALES_REPORT_IMPORT_MAX_BYTES?.trim()) ||
      DEFAULT_MAX_BYTES,
  },
  fileFilter: (_req, file, callback) => {
    const lowerName = file.originalname.toLowerCase();
    const allowedExtension = Array.from(ALLOWED_EXTENSIONS).some((extension) =>
      lowerName.endsWith(extension),
    );
    if (!allowedExtension || !ALLOWED_MIME_TYPES.has(file.mimetype)) {
      callback(
        new BadRequestException(
          'Chỉ nhận file Excel .xlsx hoặc .xls, dung lượng tối đa 5 MB.',
        ),
      );
      return;
    }
    callback(null, true);
  },
};
