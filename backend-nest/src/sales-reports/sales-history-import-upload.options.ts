import { BadRequestException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { extname, join } from 'node:path';
import { diskStorage, memoryStorage, type Options } from 'multer';

export const SALES_HISTORY_IMPORT_MAX_BYTES = 200 * 1024 * 1024;
export const SALES_HISTORY_IMPORT_CHUNK_BYTES = 4 * 1024 * 1024;
const SALES_HISTORY_IMPORT_CHUNK_PARSER_HEADROOM_BYTES = 64 * 1024;
export const SALES_HISTORY_IMPORT_DIRECTORY = join(
  tmpdir(),
  'opshub-sales-history-imports',
);

mkdirSync(SALES_HISTORY_IMPORT_DIRECTORY, { recursive: true });

const ALLOWED_EXTENSIONS = new Set(['.csv', '.tsv']);
const ALLOWED_MIME_TYPES = new Set([
  'text/csv',
  'text/tab-separated-values',
  'text/plain',
  'application/csv',
  'application/octet-stream',
]);

export const salesHistoryImportUploadOptions: Options = {
  storage: diskStorage({
    destination: SALES_HISTORY_IMPORT_DIRECTORY,
    filename: (_request, _file, callback) => callback(null, randomUUID()),
  }),
  limits: { files: 1, fileSize: SALES_HISTORY_IMPORT_MAX_BYTES },
  fileFilter: (_request, file, callback) => {
    const extension = extname(file.originalname).toLowerCase();
    if (
      !ALLOWED_EXTENSIONS.has(extension) ||
      !ALLOWED_MIME_TYPES.has(String(file.mimetype || '').toLowerCase())
    ) {
      callback(
        new BadRequestException(
          'Chỉ nhận tệp CSV hoặc TSV, dung lượng tối đa 200 MiB.',
        ),
      );
      return;
    }
    callback(null, true);
  },
};

export const salesHistoryImportChunkUploadOptions: Options = {
  storage: memoryStorage(),
  limits: {
    files: 1,
    fileSize:
      SALES_HISTORY_IMPORT_CHUNK_BYTES +
      SALES_HISTORY_IMPORT_CHUNK_PARSER_HEADROOM_BYTES,
  },
};
