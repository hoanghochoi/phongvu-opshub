import { MapVietinBigQueryStorageWriterService } from './map-vietin-bigquery-storage-writer.service';

describe('MapVietinBigQueryStorageWriterService', () => {
  it('does not acknowledge valid rows until they are re-appended after a row error', async () => {
    const service = new MapVietinBigQueryStorageWriterService();
    const getResult = jest
      .fn()
      .mockRejectedValueOnce({
        rowErrors: [{ index: 1, message: 'invalid amount' }],
      })
      .mockResolvedValueOnce({});
    const appendRows = jest.fn(() => ({ getResult }));
    (service as any).writer = { appendRows, close: jest.fn() };
    (service as any).writeClient = { isOpen: () => true };
    const rows = [
      { event_id: 'event-0' },
      { event_id: 'event-1' },
      { event_id: 'event-2' },
    ] as any;

    await expect(service.appendRows(rows)).resolves.toEqual({
      successfulIndexes: [0, 2],
      failed: [
        {
          index: 1,
          reason: expect.stringContaining('invalid amount'),
        },
      ],
    });

    expect(appendRows).toHaveBeenNthCalledWith(1, rows);
    expect(appendRows).toHaveBeenNthCalledWith(2, [rows[0], rows[2]]);
  });
});
