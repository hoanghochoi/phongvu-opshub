import type { Prisma } from '@prisma/client';

export type ClaimedMapVietinBigQueryEvent = {
  id: string;
  aggregateId: string;
  schemaVersion: number;
  payload: Prisma.JsonValue;
  occurredAt: Date;
  attempts: number;
  claimToken: string;
};

export type MapVietinBigQueryRow = {
  event_id: string;
  transaction_id: string;
  revision: string;
  schema_version: number;
  transaction_date: Date;
  store_code: string | null;
  statement_number: string | null;
  amount: number;
  orders: string[];
  order_source: string | null;
  status: string | null;
  paid_at: Date | null;
  income_type: string;
  provider_source: string | null;
  first_seen_at: Date;
  source_created_at: Date;
  source_updated_at: Date;
  event_occurred_at: Date;
  exported_at: Date;
  is_deleted: boolean;
};

export type MapVietinBigQueryAppendResult = {
  successfulIndexes: number[];
  failed: Array<{ index: number; reason: string }>;
};

export interface MapVietinBigQueryAppender {
  appendRows(
    rows: MapVietinBigQueryRow[],
  ): Promise<MapVietinBigQueryAppendResult>;
}
