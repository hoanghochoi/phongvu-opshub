import { adapt, managedwriter, protos } from '@google-cloud/bigquery-storage';
import { MapVietinBigQueryRowMapper } from './map-vietin-bigquery-row.mapper';
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

  it('encodes mapped DATE and TIMESTAMP fields before a Storage Write request', () => {
    const schema = protos.google.cloud.bigquery.storage.v1.TableFieldSchema;
    const protoDescriptor = adapt.convertStorageSchemaToProto2Descriptor(
      {
        fields: [
          {
            name: 'transaction_date',
            type: schema.Type.DATE,
            mode: schema.Mode.REQUIRED,
          },
          {
            name: 'paid_at',
            type: schema.Type.TIMESTAMP,
            mode: schema.Mode.NULLABLE,
          },
          ...[
            'first_seen_at',
            'source_created_at',
            'source_updated_at',
            'event_occurred_at',
            'exported_at',
          ].map((name) => ({
            name,
            type: schema.Type.TIMESTAMP,
            mode: schema.Mode.REQUIRED,
          })),
        ],
      },
      'root',
    );
    const write = jest.fn(() => ({ getResult: jest.fn() }));
    const connection = {
      onSchemaUpdated: jest.fn(() => ({ off: jest.fn() })),
      reconnect: jest.fn(),
      getStreamId: jest.fn(() => 'projects/test/streams/_default'),
      write,
      close: jest.fn(),
    };
    const writer = new managedwriter.JSONWriter({
      connection: connection as never,
      protoDescriptor,
    });
    const mapper = new MapVietinBigQueryRowMapper();
    const row = mapper.toRow(
      {
        id: 'event-1',
        aggregateId: 'transaction-1',
        schemaVersion: 1,
        occurredAt: new Date('2026-07-23T02:00:00.000Z'),
        attempts: 1,
        claimToken: 'claim-1',
        payload: {
          transaction_id: 'transaction-1',
          revision: '2',
          transaction_date: '2026-07-23',
          store_code: 'S01',
          statement_number: 'STMT-1',
          amount: 125000,
          orders: ['ORD-1'],
          order_source: 'MAP',
          status: 'SUCCESS',
          paid_at: '2026-07-23T02:00:00.000Z',
          income_type: 'SALES',
          provider_source: 'MAP',
          first_seen_at: '2026-07-23T01:00:00.000Z',
          source_created_at: '2026-07-23T01:00:00.000Z',
          source_updated_at: '2026-07-23T02:00:00.000Z',
          is_deleted: false,
        },
      } as never,
      new Date('2026-07-23T03:00:00.000Z'),
    );

    expect(() => writer.appendRows([row])).not.toThrow();
    expect(write).toHaveBeenCalledTimes(1);
    writer.close();
  });
});
