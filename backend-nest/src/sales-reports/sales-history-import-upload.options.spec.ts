import express from 'express';
import multer from 'multer';
import request from 'supertest';
import {
  SALES_HISTORY_IMPORT_CHUNK_BYTES,
  salesHistoryImportChunkUploadOptions,
} from './sales-history-import-upload.options';
import { SalesHistoryImportService } from './sales-history-import.service';

function createChunkParserApp() {
  const app = express();
  app.post(
    '/chunk',
    multer(salesHistoryImportChunkUploadOptions).single('chunk'),
    (req, res) => {
      res.status(200).json({ bytes: req.file?.buffer.length });
    },
  );
  app.use(
    (
      error: unknown,
      _request: express.Request,
      response: express.Response,
      _next: express.NextFunction,
    ) => {
      if (error instanceof multer.MulterError) {
        response.status(413).json({ code: error.code });
        return;
      }
      response.status(500).json({ error: 'unexpected parser error' });
    },
  );
  return app;
}

describe('sales history import chunk upload boundaries', () => {
  const parserCapBytes = SALES_HISTORY_IMPORT_CHUNK_BYTES + 64 * 1024;

  it('sets the parser cap to the 4 MiB logical chunk plus exactly 64 KiB headroom', () => {
    expect(salesHistoryImportChunkUploadOptions.limits?.fileSize).toBe(
      parserCapBytes,
    );
  });

  it('parses an exact 4 MiB logical chunk inside its multipart envelope', async () => {
    await request(createChunkParserApp())
      .post('/chunk')
      .field('offset', '0')
      .attach('chunk', Buffer.alloc(SALES_HISTORY_IMPORT_CHUNK_BYTES), {
        filename: 'history.part',
        contentType: 'application/octet-stream',
      })
      .expect(200, { bytes: SALES_HISTORY_IMPORT_CHUNK_BYTES });
  });

  it.each([parserCapBytes, parserCapBytes + 1])(
    'rejects a chunk at or over the parser cap (%i bytes) with LIMIT_FILE_SIZE',
    async (chunkBytes) => {
      await request(createChunkParserApp())
        .post('/chunk')
        .field('offset', '0')
        .attach('chunk', Buffer.alloc(chunkBytes), {
          filename: 'history.part',
          contentType: 'application/octet-stream',
        })
        .expect(413, { code: 'LIMIT_FILE_SIZE' });
    },
  );

  it('still rejects a chunk larger than the logical 4 MiB limit', async () => {
    const service = new SalesHistoryImportService({} as any, {} as any);

    await expect(
      service.appendUploadChunk({ id: 'admin-1' }, 'job-1', 0, {
        buffer: Buffer.alloc(SALES_HISTORY_IMPORT_CHUNK_BYTES + 1),
      } as Express.Multer.File),
    ).rejects.toThrow('Phần dữ liệu tải lên chưa hợp lệ');
  });
});
