import { StreamableFile } from '@nestjs/common';
import type { Response } from 'express';
import { MapVietinController } from './map-vietin.controller';
import { MapVietinService } from './map-vietin.service';

describe('MapVietinController', () => {
  it('routes batch tracking updates to the service', async () => {
    const batchUpdateStatementOrderTracking = jest.fn().mockResolvedValue({
      processedCount: 2,
      changedCount: 2,
      unchangedCount: 0,
    });
    const controller = new MapVietinController({
      batchUpdateStatementOrderTracking,
    } as unknown as MapVietinService);
    const user = { id: 'acc-1' };
    const body = {
      transactionIds: ['stored-1', 'stored-2'],
      status: 'UNFOLLOWED',
    };

    await expect(
      controller.batchUpdateStatementOrderTracking({ user }, body),
    ).resolves.toMatchObject({ processedCount: 2 });
    expect(batchUpdateStatementOrderTracking).toHaveBeenCalledWith(user, body);
  });

  it('streams statement XLSX bytes instead of serializing the Buffer as JSON', async () => {
    const workbook = Buffer.from([0x50, 0x4b, 0x03, 0x04, 0x01, 0x02]);
    const exportStatementsXlsx = jest.fn().mockResolvedValue(workbook);
    const controller = new MapVietinController({
      exportStatementsXlsx,
    } as unknown as MapVietinService);
    const setHeader = jest.fn();
    const response = { setHeader } as unknown as Response;
    const user = { id: 'user-1' };
    const body = { transactionIds: ['statement-1'] };

    const result = await controller.exportStatements({ user }, body, response);

    expect(exportStatementsXlsx).toHaveBeenCalledWith(user, body);
    expect(setHeader).toHaveBeenCalledWith(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(setHeader).toHaveBeenCalledWith(
      'Content-Disposition',
      'attachment; filename="opshub-bank-statements.xlsx"',
    );
    expect(result).toBeInstanceOf(StreamableFile);
    expect(await readStreamableFile(result)).toEqual(workbook);
  });
});

async function readStreamableFile(file: StreamableFile) {
  const chunks: Buffer[] = [];
  for await (const chunk of file.getStream()) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}
