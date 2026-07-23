import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { adapt, managedwriter, protos } from '@google-cloud/bigquery-storage';
import { safeLogError } from '../common/log-sanitizer';
import { resolveMapVietinBigQueryConfig } from './map-vietin-bigquery.config';
import {
  MapVietinBigQueryAppendResult,
  MapVietinBigQueryAppender,
  MapVietinBigQueryRow,
} from './map-vietin-bigquery.types';

@Injectable()
export class MapVietinBigQueryStorageWriterService
  implements MapVietinBigQueryAppender, OnModuleDestroy
{
  private readonly config = resolveMapVietinBigQueryConfig();
  private writeClient: InstanceType<typeof managedwriter.WriterClient> | null =
    null;
  private connection: Awaited<
    ReturnType<
      InstanceType<typeof managedwriter.WriterClient>['createStreamConnection']
    >
  > | null = null;
  private writer: InstanceType<typeof managedwriter.JSONWriter> | null = null;
  private connecting: Promise<void> | null = null;

  async appendRows(
    rows: MapVietinBigQueryRow[],
  ): Promise<MapVietinBigQueryAppendResult> {
    if (rows.length === 0) return { successfulIndexes: [], failed: [] };
    const failed: Array<{ index: number; reason: string }> = [];
    const successfulIndexes = await this.appendIndexedRows(
      rows.map((row, index) => ({ row, index })),
      failed,
    );
    return {
      successfulIndexes: successfulIndexes.sort((left, right) => left - right),
      failed: failed.sort((left, right) => left.index - right.index),
    };
  }

  private async appendIndexedRows(
    rows: Array<{ row: MapVietinBigQueryRow; index: number }>,
    failed: Array<{ index: number; reason: string }>,
  ): Promise<number[]> {
    if (rows.length === 0) return [];
    await this.ensureWriter();
    try {
      await this.writer!.appendRows(rows.map((item) => item.row)).getResult();
      return rows.map((item) => item.index);
    } catch (error) {
      const rowErrors = this.extractRowErrors(error, rows.length);
      if (rowErrors.length === 0) {
        this.resetWriter();
        throw error;
      }
      // Storage Write rejects the entire append when any row is malformed.
      // Keep the connection, quarantine only reported rows, then append the
      // remaining rows in a fresh request before acknowledging any outbox row.
      const failedIndexes = new Set(rowErrors.map((item) => item.index));
      for (const item of rowErrors) {
        failed.push({ index: rows[item.index].index, reason: item.reason });
      }
      return this.appendIndexedRows(
        rows.filter((_, index) => !failedIndexes.has(index)),
        failed,
      );
    }
  }

  onModuleDestroy() {
    this.close();
  }

  close() {
    this.resetWriter();
    this.writeClient?.close();
    this.writeClient = null;
  }

  private async ensureWriter() {
    if (this.writer && this.writeClient?.isOpen()) return;
    if (this.connecting) return this.connecting;
    this.connecting = this.connect();
    try {
      await this.connecting;
    } finally {
      this.connecting = null;
    }
  }

  private async connect() {
    if (!this.config.enabled) {
      throw new Error('Map Vietin BigQuery worker is disabled');
    }
    this.close();
    const destinationTable = `projects/${this.config.projectId}/datasets/${this.config.datasetId}/tables/${this.config.tableId}`;
    const defaultStreamId = `${destinationTable}/streams/_default`;
    const client = new managedwriter.WriterClient({
      projectId: this.config.projectId,
      ...(this.config.keyFilename
        ? { keyFilename: this.config.keyFilename }
        : {}),
    });
    client.enableWriteRetries(true);
    client.setMaxRetryAttempts(4);
    const writeStream = await client.getWriteStream({
      streamId: defaultStreamId,
      view: protos.google.cloud.bigquery.storage.v1.WriteStreamView.FULL,
    });
    if (!writeStream.tableSchema) {
      client.close();
      throw new Error('BigQuery raw table schema is unavailable');
    }
    const protoDescriptor = adapt.convertStorageSchemaToProto2Descriptor(
      writeStream.tableSchema,
      'root',
    );
    const connection = await client.createStreamConnection({
      streamId: managedwriter.DefaultStream,
      destinationTable,
    });
    this.writeClient = client;
    this.connection = connection;
    this.writer = new managedwriter.JSONWriter({
      connection,
      protoDescriptor,
    });
  }

  private resetWriter() {
    try {
      this.writer?.close();
    } catch {
      // Reconnection owns recovery; never log or expose buffered row contents.
    }
    this.writer = null;
    this.connection = null;
  }

  private extractRowErrors(error: unknown, rowCount: number) {
    const value = error as Record<string, unknown> | null;
    const candidates = [value?.rowErrors, value?.errors, value?.details];
    const failed = new Map<number, string>();
    for (const candidate of candidates) {
      if (!Array.isArray(candidate)) continue;
      for (const item of candidate) {
        if (!item || typeof item !== 'object') continue;
        const rowError = item as Record<string, unknown>;
        const index = Number(
          rowError.index ?? rowError.rowIndex ?? rowError.row_index,
        );
        if (!Number.isInteger(index) || index < 0 || index >= rowCount)
          continue;
        failed.set(
          index,
          safeLogError(rowError.message ?? rowError.reason ?? rowError, 240),
        );
      }
    }
    return [...failed.entries()].map(([index, reason]) => ({ index, reason }));
  }
}
