import { Injectable, Logger } from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import { safeLogError } from '../common/log-sanitizer';
import { getBidvH2hConfig } from '../config/env';
import { PaymentNotificationsService } from '../payment-notifications/payment-notifications.service';
import { PrismaService } from '../prisma/prisma.service';

const MAX_ATTEMPTS = 8;

@Injectable()
export class BidvH2hProjectionWorker {
  private readonly logger = new Logger(BidvH2hProjectionWorker.name);
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly paymentNotifications: PaymentNotificationsService,
  ) {}

  @Interval(1000)
  async tick() {
    if (this.running) return;
    this.running = true;
    try {
      if (!(await this.projectionEnabled())) return;
      for (let index = 0; index < 20; index += 1) {
        const claimed = await this.claimOne();
        if (!claimed) break;
        await this.process(claimed);
      }
    } finally {
      this.running = false;
    }
  }

  private async projectionEnabled() {
    const config = getBidvH2hConfig();
    if (!config.projectionMasterEnabled) return false;
    const control = await (this.prisma as any).bankConnectionControl.findUnique(
      {
        where: { bankCode: 'BIDV' },
      },
    );
    return control?.projectionEnabled === true;
  }

  private async claimOne() {
    const claimToken = randomUUID();
    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>`
      WITH candidate AS (
        SELECT id
        FROM "BankTransaction"
        WHERE (
          (
            "projectionStatus" IN ('PENDING', 'RETRY')
            AND "projectionAvailableAt" <= NOW()
            AND (
              "projectionLeaseExpiresAt" IS NULL
              OR "projectionLeaseExpiresAt" < NOW()
            )
          )
          OR (
            "projectionStatus" = 'PROCESSING'
            AND "projectionLeaseExpiresAt" < NOW()
          )
        )
        ORDER BY "createdAt", id
        FOR UPDATE SKIP LOCKED
        LIMIT 1
      )
      UPDATE "BankTransaction" transaction
      SET "projectionStatus" = 'PROCESSING',
          "projectionClaimedAt" = NOW(),
          "projectionClaimToken" = ${claimToken},
          "projectionLeaseExpiresAt" = NOW() + INTERVAL '30 seconds',
          "projectionAttempts" = transaction."projectionAttempts" + 1,
          "updatedAt" = NOW()
      FROM candidate
      WHERE transaction.id = candidate.id
      RETURNING transaction.id
    `;
    if (rows.length === 0) return null;
    return (this.prisma as any).bankTransaction.findUnique({
      where: { id: rows[0].id },
    });
  }

  private async process(transaction: any) {
    const startedAt = Date.now();
    try {
      const outcome = await this.prisma.$transaction(async (tx) => {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`bidv-identity:${transaction.identityHash}`}))`;
        const current = await (tx as any).bankTransaction.findUnique({
          where: { id: transaction.id },
        });
        if (
          !current ||
          current.projectionClaimToken !== transaction.projectionClaimToken
        ) {
          throw new Error('projection lease lost');
        }
        const eligibility = await this.eligibility(current, tx);
        if (!eligibility.eligible) {
          return { kind: 'SKIPPED' as const, reason: eligibility.reason };
        }
        const projected = await tx.mapVietinTransaction.upsert({
          where: { canonicalBankTransactionId: transaction.id },
          create: {
            storeCode: eligibility.storeCode,
            transactionKey: `bidv:${current.identityHash}:${current.payloadHash.slice(0, 12)}`,
            transactionNumber: current.referenceNumber,
            amount: eligibility.amount,
            content: current.remark,
            status: 'SUCCESS',
            paidAt: current.paidAt,
            payerName: current.senderAccountName,
            payerAccount: current.senderAccountMasked,
            rawData: {
              source: 'BIDV_H2H',
              bankCode: current.bankCode,
              direction: current.direction,
              currency: current.currency,
              canonicalBankTransactionId: current.id,
            },
            bankSource: 'BIDV_H2H',
            currency: current.currency,
            direction: current.direction,
            exactAmount: current.exactAmount,
            canonicalBankTransactionId: current.id,
          },
          update: {},
        });
        return {
          kind: 'PROJECTED' as const,
          projected,
          storeCode: eligibility.storeCode,
        };
      });

      if (outcome.kind === 'SKIPPED') {
        const status =
          outcome.reason === 'identity_conflict' ? 'CONFLICT' : 'SKIPPED';
        await this.finish(transaction, status, outcome.reason);
        this.logger.log(
          `BIDV projection skipped transactionRef=${transaction.id} reason=${outcome.reason}`,
        );
        return;
      }

      const projected = outcome.projected;

      await this.paymentNotifications.createForTransaction(projected as any);
      await this.finish(transaction, 'PROJECTED', null, projected.id);
      this.logger.log(
        `BIDV projection succeeded transactionRef=${transaction.id} projectedRef=${projected.id} store=${outcome.storeCode} durationMs=${Date.now() - startedAt}`,
      );
    } catch (error) {
      await this.retry(transaction, error);
      this.logger.warn(
        `BIDV projection failed transactionRef=${transaction.id} attempt=${transaction.projectionAttempts} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
    }
  }

  private async eligibility(
    transaction: any,
    db: any = this.prisma,
  ): Promise<
    | { eligible: true; storeCode: string; amount: number }
    | { eligible: false; reason: string }
  > {
    if (transaction.conflictStatus !== 'NONE') {
      return { eligible: false, reason: 'identity_conflict' };
    }
    if (transaction.direction !== 'C') {
      return { eligible: false, reason: 'not_credit' };
    }
    if (transaction.currency !== 'VND') {
      return { eligible: false, reason: 'not_vnd' };
    }
    const exact = new Prisma.Decimal(transaction.exactAmount);
    if (
      !exact.isInteger() ||
      !exact.isPositive() ||
      exact.greaterThan(Number.MAX_SAFE_INTEGER)
    ) {
      return { eligible: false, reason: 'amount_not_supported' };
    }
    const storeCode = await this.resolveStore(transaction, db);
    if (!storeCode) return { eligible: false, reason: 'showroom_not_unique' };
    return { eligible: true, storeCode, amount: exact.toNumber() };
  }

  private async resolveStore(transaction: any, db: any = this.prisma) {
    if (!transaction.showroomCodeHint) return null;
    const stores = await db.store.findMany({
      select: { storeId: true },
    });
    const matches = new Set<string>(
      stores
        .filter(
          (store: { storeId: string }) =>
            store.storeId.trim().toUpperCase() === transaction.showroomCodeHint,
        )
        .map((store: { storeId: string }) => store.storeId),
    );
    return matches.size === 1 ? Array.from(matches)[0] : null;
  }

  private finish(
    transaction: any,
    status: string,
    reason: string | null,
    projectedTransactionId?: string,
  ) {
    return (this.prisma as any).bankTransaction.updateMany({
      where: {
        id: transaction.id,
        projectionClaimToken: transaction.projectionClaimToken,
      },
      data: {
        projectionStatus: status,
        projectionReason: reason,
        projectedTransactionId: projectedTransactionId,
        projectedAt: status === 'PROJECTED' ? new Date() : null,
        projectionClaimToken: null,
        projectionClaimedAt: null,
        projectionLeaseExpiresAt: null,
        projectionLastError: null,
      },
    });
  }

  private retry(transaction: any, error: unknown) {
    const dead = transaction.projectionAttempts >= MAX_ATTEMPTS;
    const backoffSeconds = Math.min(
      300,
      Math.pow(2, Math.max(0, transaction.projectionAttempts - 1)),
    );
    return (this.prisma as any).bankTransaction.updateMany({
      where: {
        id: transaction.id,
        projectionClaimToken: transaction.projectionClaimToken,
      },
      data: {
        projectionStatus: dead ? 'DEAD_LETTER' : 'RETRY',
        projectionAvailableAt: new Date(Date.now() + backoffSeconds * 1000),
        projectionClaimToken: null,
        projectionClaimedAt: null,
        projectionLeaseExpiresAt: null,
        projectionLastError: safeLogError(error),
      },
    });
  }
}
