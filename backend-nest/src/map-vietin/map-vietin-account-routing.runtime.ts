import { Logger, type LoggerService } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import {
  type MapPersistStats,
  type MapTransactionRow,
} from './map-vietin-persistence.runtime';

export type UnmappedReason =
  | 'MISSING_VIRTUAL_ACCOUNT'
  | 'UNMAPPED_ACCOUNT'
  | 'AMBIGUOUS_ACCOUNT';

export type StoreAccountRow = {
  storeId: string;
  transferAccountNumber?: string | null;
};

export type MapGlobalPersistStats = {
  created: number;
  updated: number;
  unchanged: number;
  cacheHits: number;
  quarantined: number;
  sourceAccountMapped: number;
};

type RoutingLogger = Pick<LoggerService, 'log' | 'warn'>;

export type MapVietinAccountRoutingRuntimeConfig = {
  prisma: PrismaService;
  logger?: RoutingLogger;
  contentKeys: string[];
  transactionNumberKeys: string[];
  statusKeys: string[];
  payerNameKeys: string[];
  payerAccountKeys: string[];
  readAmount: (row: MapTransactionRow) => number | null;
  isSuccessfulTransaction: (row: MapTransactionRow) => boolean;
  readFirstText: (row: MapTransactionRow, keys: string[]) => string;
  readTransactionTime: (row: MapTransactionRow) => Date | null;
  isEfastMapTransactionRow: (row: MapTransactionRow) => boolean;
  resolveGlobalVirtualAccount: (row: MapTransactionRow) => string;
  resolveEfastSourceAccount: (row: MapTransactionRow) => string;
  normalizeAccountNumber: (value: string) => string;
  scrubJson: (value: unknown) => unknown;
  maskAccount: (value: string) => string;
  persistTransactions: (
    storeCode: string | null,
    rows: unknown[],
    stats: MapPersistStats,
  ) => Promise<number>;
};

/**
 * Owns global account-to-store resolution and quarantine persistence. The
 * MapVietinService remains the public facade; provider/scheduler, statement
 * policy and transaction canonical persistence stay with their existing owners.
 */
export class MapVietinAccountRoutingRuntime {
  private readonly defaultLogger = new Logger(
    MapVietinAccountRoutingRuntime.name,
  );

  constructor(private readonly config: MapVietinAccountRoutingRuntimeConfig) {}

  async loadStoreAccountIndex() {
    const stores = (await this.config.prisma.store.findMany({
      where: { transferAccountNumber: { not: null } },
      select: { storeId: true, transferAccountNumber: true },
    })) as StoreAccountRow[];
    const index = new Map<string, string[]>();
    for (const store of stores) {
      const accountKey = this.config.normalizeAccountNumber(
        store.transferAccountNumber || '',
      );
      if (!accountKey) continue;
      const storeCodes = index.get(accountKey) || [];
      if (!storeCodes.includes(store.storeId)) storeCodes.push(store.storeId);
      index.set(accountKey, storeCodes);
    }
    return index;
  }

  async reassignUnassignedEfastTransactions(
    storeAccountIndex: Map<string, string[]>,
  ) {
    let remapped = 0;
    let uniqueAccountCount = 0;
    for (const [accountKey, storeCodes] of storeAccountIndex.entries()) {
      if (storeCodes.length !== 1) continue;
      uniqueAccountCount += 1;
      const result = await this.config.prisma.mapVietinTransaction.updateMany({
        where: {
          storeCode: null,
          AND: [
            {
              rawData: {
                path: ['source'],
                equals: 'VIETIN_EFAST',
              },
            },
            {
              OR: [
                {
                  rawData: {
                    path: ['efastCreditAccountNo'],
                    equals: accountKey,
                  },
                },
                {
                  rawData: {
                    path: ['efastBankAccountNo'],
                    equals: accountKey,
                  },
                },
              ],
            },
          ],
        },
        data: { storeCode: storeCodes[0] },
      });
      remapped += result.count;
    }
    if (remapped > 0) {
      this.logger().log(
        `VietinBank eFAST account remap completed: uniqueAccounts=${uniqueAccountCount} remapped=${remapped}`,
      );
    }
    return remapped;
  }

  async persistGlobalTransactions(
    rows: unknown[],
    storeAccountIndex: Map<string, string[]>,
  ): Promise<MapGlobalPersistStats> {
    const result: MapGlobalPersistStats = {
      created: 0,
      updated: 0,
      unchanged: 0,
      cacheHits: 0,
      quarantined: 0,
      sourceAccountMapped: 0,
    };
    for (const raw of rows) {
      if (!raw || typeof raw !== 'object') continue;
      const row = raw as MapTransactionRow;
      const amount = this.config.readAmount(row);
      if (!amount || amount <= 0) continue;
      if (!this.config.isSuccessfulTransaction(row)) continue;

      const virtualAccount = this.config.resolveGlobalVirtualAccount(row);
      const sourceAccount = this.config.resolveEfastSourceAccount(row);
      const accountCandidates = this.config.isEfastMapTransactionRow(row)
        ? [
            { value: virtualAccount, sourceAccount: false },
            { value: sourceAccount, sourceAccount: true },
          ]
        : [{ value: virtualAccount, sourceAccount: false }];
      let accountKey = '';
      let accountValue = '';
      let storeCodes: string[] = [];
      let matchedBySourceAccount = false;
      for (const candidate of accountCandidates) {
        const candidateKey = this.config.normalizeAccountNumber(
          candidate.value,
        );
        if (!candidateKey) continue;
        if (!accountKey) {
          accountKey = candidateKey;
          accountValue = candidate.value;
        }
        const candidateStoreCodes = storeAccountIndex.get(candidateKey) || [];
        if (candidateStoreCodes.length === 0) continue;
        accountKey = candidateKey;
        accountValue = candidate.value;
        storeCodes = candidateStoreCodes;
        matchedBySourceAccount = candidate.sourceAccount;
        break;
      }

      if (storeCodes.length === 0) {
        if (
          this.config.isEfastMapTransactionRow(row) &&
          !this.config.normalizeAccountNumber(virtualAccount)
        ) {
          const stats = this.emptyPersistStats();
          result.created += await this.config.persistTransactions(
            null,
            [row],
            stats,
          );
          this.addPersistStats(result, stats);
          continue;
        }
        await this.quarantineGlobalTransaction(
          row,
          accountKey ? 'UNMAPPED_ACCOUNT' : 'MISSING_VIRTUAL_ACCOUNT',
          accountKey ? accountValue : virtualAccount,
        );
        result.quarantined += 1;
        continue;
      }
      if (storeCodes.length > 1) {
        await this.quarantineGlobalTransaction(
          row,
          'AMBIGUOUS_ACCOUNT',
          accountValue,
        );
        result.quarantined += 1;
        continue;
      }
      if (matchedBySourceAccount) result.sourceAccountMapped += 1;

      const stats = this.emptyPersistStats();
      result.created += await this.config.persistTransactions(
        storeCodes[0],
        [row],
        stats,
      );
      this.addPersistStats(result, stats);
    }
    return result;
  }

  private async quarantineGlobalTransaction(
    row: MapTransactionRow,
    reason: UnmappedReason,
    virtualAccount: string,
  ) {
    const amount = this.config.readAmount(row);
    const content = this.config.readFirstText(row, this.config.contentKeys);
    const transactionNumber = this.config.readFirstText(
      row,
      this.config.transactionNumberKeys,
    );
    const paidAt = this.config.readTransactionTime(row);
    const status = this.config.readFirstText(row, this.config.statusKeys);
    const payerName = this.config.readFirstText(row, this.config.payerNameKeys);
    const payerAccount = this.config.readFirstText(
      row,
      this.config.payerAccountKeys,
    );
    const fallback = [
      virtualAccount,
      transactionNumber,
      amount ?? '',
      paidAt?.toISOString() ?? '',
      content,
    ].join('|');
    const hash = createHash('sha256')
      .update(`${reason}|${fallback}`)
      .digest('hex');
    const unmappedKey = `${reason}:${hash}`;

    await this.config.prisma.mapVietinUnmappedTransaction.upsert({
      where: { unmappedKey },
      create: {
        unmappedKey,
        virtualAccount: virtualAccount || null,
        reason,
        transactionNumber: transactionNumber || null,
        amount,
        content,
        status: status || null,
        paidAt,
        payerName: payerName || null,
        payerAccount: payerAccount || null,
        rawData: this.config.scrubJson(row) as Prisma.InputJsonObject,
      },
      update: {
        virtualAccount: virtualAccount || null,
        reason,
        transactionNumber: transactionNumber || null,
        amount,
        content,
        status: status || null,
        paidAt,
        payerName: payerName || null,
        payerAccount: payerAccount || null,
        rawData: this.config.scrubJson(row) as Prisma.InputJsonObject,
      },
    });
    this.logger().warn(
      `Global MAP transaction quarantined: ${reason} virtualAccount=${this.config.maskAccount(virtualAccount)}`,
    );
  }

  private emptyPersistStats(): MapPersistStats {
    return { updated: 0, unchanged: 0, cacheHits: 0 };
  }

  private addPersistStats(
    result: MapGlobalPersistStats,
    stats: MapPersistStats,
  ) {
    result.updated += stats.updated;
    result.unchanged += stats.unchanged;
    result.cacheHits += stats.cacheHits;
  }

  private logger(): RoutingLogger {
    return this.config.logger ?? this.defaultLogger;
  }
}
