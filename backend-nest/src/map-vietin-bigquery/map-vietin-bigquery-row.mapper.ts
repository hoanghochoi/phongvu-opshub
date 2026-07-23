import { Injectable } from '@nestjs/common';
import { ClaimedMapVietinBigQueryEvent } from './map-vietin-bigquery.types';

@Injectable()
export class MapVietinBigQueryRowMapper {
  toRow(event: ClaimedMapVietinBigQueryEvent, now = new Date()) {
    const payload = this.record(event.payload);
    const transactionId = this.requiredString(
      payload.transaction_id,
      'transaction_id',
    );
    if (transactionId !== event.aggregateId) {
      throw new Error('Outbox aggregate does not match transaction_id');
    }

    return {
      event_id: event.id,
      transaction_id: transactionId,
      revision: this.requiredIntegerString(payload.revision, 'revision'),
      schema_version: event.schemaVersion,
      transaction_date: this.requiredDate(
        payload.transaction_date,
        'transaction_date',
      ),
      store_code: this.optionalString(payload.store_code),
      statement_number: this.optionalString(payload.statement_number),
      amount: this.requiredInteger(payload.amount, 'amount'),
      orders: this.stringArray(payload.orders, 'orders'),
      order_source: this.optionalString(payload.order_source),
      status: this.optionalString(payload.status),
      paid_at: this.optionalTimestamp(payload.paid_at, 'paid_at'),
      income_type: this.requiredString(payload.income_type, 'income_type'),
      provider_source: this.optionalString(payload.provider_source),
      first_seen_at: this.requiredTimestamp(
        payload.first_seen_at,
        'first_seen_at',
      ),
      source_created_at: this.requiredTimestamp(
        payload.source_created_at,
        'source_created_at',
      ),
      source_updated_at: this.requiredTimestamp(
        payload.source_updated_at,
        'source_updated_at',
      ),
      event_occurred_at: event.occurredAt.toISOString(),
      exported_at: now.toISOString(),
      is_deleted: this.requiredBoolean(payload.is_deleted, 'is_deleted'),
    };
  }

  private record(value: unknown): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('Outbox payload must be an object');
    }
    return value as Record<string, unknown>;
  }

  private requiredString(value: unknown, field: string) {
    const normalized = String(value ?? '').trim();
    if (!normalized) throw new Error(`Missing ${field}`);
    return normalized;
  }

  private optionalString(value: unknown) {
    if (value === null || value === undefined) return null;
    const normalized = String(value).trim();
    return normalized || null;
  }

  private requiredIntegerString(value: unknown, field: string) {
    const normalized = this.requiredString(value, field);
    if (!/^\d+$/.test(normalized)) throw new Error(`Invalid ${field}`);
    return normalized;
  }

  private requiredInteger(value: unknown, field: string) {
    const parsed = Number(value);
    if (!Number.isSafeInteger(parsed)) throw new Error(`Invalid ${field}`);
    return parsed;
  }

  private stringArray(value: unknown, field: string) {
    if (!Array.isArray(value)) throw new Error(`Invalid ${field}`);
    return value.map((item) => this.requiredString(item, field));
  }

  private requiredDate(value: unknown, field: string) {
    const normalized = this.requiredString(value, field);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
      throw new Error(`Invalid ${field}`);
    }
    return normalized;
  }

  private optionalTimestamp(value: unknown, field: string) {
    if (value === null || value === undefined || value === '') return null;
    return this.requiredTimestamp(value, field);
  }

  private requiredTimestamp(value: unknown, field: string) {
    const normalized = this.requiredString(value, field);
    if (!Number.isFinite(Date.parse(normalized))) {
      throw new Error(`Invalid ${field}`);
    }
    return normalized;
  }

  private requiredBoolean(value: unknown, field: string) {
    if (typeof value !== 'boolean') throw new Error(`Invalid ${field}`);
    return value;
  }
}
