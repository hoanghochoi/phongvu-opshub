import { MapVietinBigQueryRowMapper } from './map-vietin-bigquery-row.mapper';

describe('MapVietinBigQueryRowMapper', () => {
  const mapper = new MapVietinBigQueryRowMapper();
  const event = {
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
      status: 'PAID',
      paid_at: '2026-07-23T02:00:00.000Z',
      income_type: 'SALES',
      provider_source: 'MAP',
      first_seen_at: '2026-07-23T01:00:00.000Z',
      source_created_at: '2026-07-23T01:00:00.000Z',
      source_updated_at: '2026-07-23T02:00:00.000Z',
      is_deleted: false,
      rawData: { payerName: 'must not be forwarded' },
    },
  } as never;

  it('maps only the sanitized whitelist', () => {
    const row = mapper.toRow(event, new Date('2026-07-23T03:00:00.000Z'));
    expect(row).toMatchObject({
      event_id: 'event-1',
      transaction_id: 'transaction-1',
      revision: '2',
      statement_number: 'STMT-1',
      is_deleted: false,
    });
    expect(row).not.toHaveProperty('rawData');
    expect(row).not.toHaveProperty('payerName');
  });

  it('rejects aggregate mismatch and malformed numeric values', () => {
    expect(() => mapper.toRow({ ...event, aggregateId: 'wrong' })).toThrow(
      'aggregate',
    );
    expect(() =>
      mapper.toRow({
        ...event,
        payload: { ...(event.payload as object), amount: 1.5 },
      }),
    ).toThrow('amount');
  });
});
