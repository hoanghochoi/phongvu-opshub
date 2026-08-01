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
      bank_source: 'VIETIN',
      currency: 'VND',
      direction: 'C',
      exact_amount: '125000.000000',
      first_seen_at: '2026-07-23T01:00:00.000Z',
      source_created_at: '2026-07-23T01:00:00.000Z',
      source_updated_at: '2026-07-23T02:00:00.000Z',
      is_deleted: false,
      bank_source: 'VIETIN',
      currency: 'VND',
      direction: 'C',
      exact_amount: '125000.000000',
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
      order_tracking_status: 'FOLLOWING',
      is_deleted: false,
    });
    expect(row.transaction_date).toEqual(new Date('2026-07-23T00:00:00.000Z'));
    expect(row.paid_at).toEqual(new Date('2026-07-23T02:00:00.000Z'));
    expect(row.first_seen_at).toEqual(new Date('2026-07-23T01:00:00.000Z'));
    expect(row.event_occurred_at).toEqual(new Date('2026-07-23T02:00:00.000Z'));
    expect(row.exported_at).toEqual(new Date('2026-07-23T03:00:00.000Z'));
    expect(row).not.toHaveProperty('rawData');
    expect(row).not.toHaveProperty('payerName');
  });

  it('requires a canonical tracking status for schema v2 events', () => {
    const v2Event = {
      ...event,
      schemaVersion: 2,
      payload: {
        ...(event.payload as object),
        order_tracking_status: 'unfollowed',
      },
    };

    expect(mapper.toRow(v2Event as never)).toMatchObject({
      schema_version: 2,
      order_tracking_status: 'UNFOLLOWED',
    });
    expect(() =>
      mapper.toRow({
        ...v2Event,
        payload: {
          ...(v2Event.payload as object),
          order_tracking_status: 'PAUSED',
        },
      } as never),
    ).toThrow('order_tracking_status');
    expect(() =>
      mapper.toRow({
        ...v2Event,
        payload: { ...(event.payload as object) },
      } as never),
    ).toThrow('order_tracking_status');
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
    expect(() =>
      mapper.toRow({
        ...event,
        payload: {
          ...(event.payload as object),
          transaction_date: '2026-02-31',
        },
      }),
    ).toThrow('transaction_date');
  });
});
