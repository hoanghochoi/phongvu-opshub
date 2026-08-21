import {
  ConflictException,
  Injectable,
  Logger,
  PayloadTooLargeException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash } from 'crypto';
import { Prisma } from '@prisma/client';
import { safeLogError } from '../common/log-sanitizer';
import { getBidvH2hConfig } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { BidvH2hCryptoService } from './bidv-h2h-crypto.service';
import { BidvH2hParser, ParsedBidvTransaction } from './bidv-h2h-parser';
import { BidvClientPrincipal } from './bidv-h2h-oauth.service';
import { BidvH2hOperatingPolicy } from './bidv-h2h-operating-policy';

const SUCCESS = { errorCode: '000', errorDesc: 'Success' } as const;

@Injectable()
export class BidvH2hIngressService {
  private readonly logger = new Logger(BidvH2hIngressService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: BidvH2hCryptoService,
    private readonly parser: BidvH2hParser,
    private readonly operatingPolicy: BidvH2hOperatingPolicy,
  ) {}

  async ingest(
    principal: BidvClientPrincipal,
    requestIdValue: unknown,
    bankCode: string,
    encryptedData: string,
  ) {
    const startedAt = Date.now();
    const requestId = this.requestId(requestIdValue);
    const requestHash = createHash('sha256')
      .update(`${bankCode}|${encryptedData}`)
      .digest('hex');
    this.logger.log(
      `BIDV ingress started requestRef=${this.requestRef(requestId)} clientRef=${principal.id}`,
    );

    try {
      const config = getBidvH2hConfig();
      if (
        Buffer.byteLength(encryptedData, 'utf8') > config.maxEncodedBodyBytes
      ) {
        throw new PayloadTooLargeException(
          'Dữ liệu gửi lên vượt kích thước cho phép.',
        );
      }
      await this.operatingPolicy.assertIngress();

      const duplicate = await (
        this.prisma as any
      ).bankIngressReceipt.findUnique({
        where: { bankCode_requestId: { bankCode, requestId } },
      });
      if (duplicate) {
        if (duplicate.requestHash !== requestHash) {
          throw new ConflictException(
            'REQUESTID đã được dùng cho nội dung khác.',
          );
        }
        this.logger.log(
          `BIDV ingress duplicate accepted requestRef=${this.requestRef(requestId)} receiptRef=${duplicate.id}`,
        );
        return SUCCESS;
      }

      const decrypted = await this.decryptWithActiveKey(encryptedData);
      if (Date.now() - startedAt >= config.processingTimeoutMs) {
        throw new ServiceUnavailableException(
          'Xử lý dữ liệu vượt thời gian cho phép. Vui lòng thử lại.',
        );
      }
      const rows = this.parser.parsePayload(
        decrypted,
        config.maxTransactionsPerBatch,
      );
      await this.persistAtomic(
        principal,
        requestId,
        requestHash,
        bankCode,
        rows,
        config.processingTimeoutMs,
        config.retentionDays,
      );
      this.logger.log(
        `BIDV ingress succeeded requestRef=${this.requestRef(requestId)} clientRef=${principal.id} transactionCount=${rows.length} durationMs=${Date.now() - startedAt}`,
      );
      return SUCCESS;
    } catch (error) {
      this.logger.warn(
        `BIDV ingress failed requestRef=${this.requestRef(requestId)} clientRef=${principal.id} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }

  private async persistAtomic(
    principal: BidvClientPrincipal,
    requestId: string,
    requestHash: string,
    bankCode: string,
    rows: ParsedBidvTransaction[],
    timeoutMs: number,
    retentionDays: number,
  ) {
    return this.prisma.$transaction(
      async (tx) => {
        await this.operatingPolicy.lock(tx);
        await this.operatingPolicy.assertIngress(tx);
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`${bankCode}:${requestId}`}))`;
        const duplicate = await (tx as any).bankIngressReceipt.findUnique({
          where: { bankCode_requestId: { bankCode, requestId } },
        });
        if (duplicate) {
          if (duplicate.requestHash !== requestHash) {
            throw new ConflictException(
              'REQUESTID đã được dùng cho nội dung khác.',
            );
          }
          return duplicate;
        }
        const identityHashes = [
          ...new Set(rows.map((row) => row.identityHash)),
        ].sort();
        for (const identityHash of identityHashes) {
          await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`bidv-identity:${identityHash}`}))`;
        }
        const receipt = await (tx as any).bankIngressReceipt.create({
          data: {
            bankCode,
            requestId,
            requestHash,
            clientRefId: principal.id,
            transactionCount: rows.length,
          },
        });

        for (const row of rows) {
          const existing = await (tx as any).bankTransaction.findMany({
            where: { identityHash: row.identityHash },
            select: { id: true, payloadHash: true },
          });
          if (
            existing.some((item: any) => item.payloadHash === row.payloadHash)
          ) {
            continue;
          }
          const hasConflict = existing.length > 0;
          if (hasConflict) {
            await (tx as any).bankTransaction.updateMany({
              where: { identityHash: row.identityHash },
              data: {
                conflictStatus: 'CONFLICT',
                projectionStatus: 'CONFLICT',
                projectionReason: 'identity_payload_conflict',
              },
            });
          }
          const transaction = await (tx as any).bankTransaction.create({
            data: this.transactionCreateData(
              receipt.id,
              bankCode,
              row,
              hasConflict,
              retentionDays,
            ),
          });
          await tx.domainOutboxEvent.create({
            data: {
              eventType: 'BANK_TRANSACTION_RECEIVED',
              aggregateType: 'BankTransaction',
              aggregateId: transaction.id,
              dedupeKey: `bank-transaction-received:${transaction.id}`,
              schemaVersion: 1,
              payload: {
                transactionId: transaction.id,
                bankCode,
                direction: row.dorc,
                currency: row.currency,
                businessDate: row.businessDateValue.toISOString().slice(0, 10),
                conflict: hasConflict,
              },
            },
          });
        }
        return (tx as any).bankIngressReceipt.update({
          where: { id: receipt.id },
          data: { completedAt: new Date(), status: 'ACCEPTED' },
        });
      },
      { timeout: timeoutMs, maxWait: Math.min(timeoutMs, 5_000) },
    );
  }

  private transactionCreateData(
    receiptId: string,
    bankCode: string,
    row: ParsedBidvTransaction,
    hasConflict: boolean,
    retentionDays: number,
  ) {
    return {
      receiptId,
      bankCode,
      identityHash: row.identityHash,
      payloadHash: row.payloadHash,
      accountNoHash: this.crypto.sensitiveHash(row.accountNo),
      accountNoMasked: this.crypto.maskAccount(row.accountNo)!,
      exactAmount: row.amount,
      currency: row.currency,
      transactionDate: row.transactionDateValue,
      transactionTime: row.transTime,
      paidAt: row.paidAt,
      direction: row.dorc,
      sequence: row.seq,
      referenceNumber: row.refNo,
      remark: row.remark,
      senderBankCode: row.frBankCode,
      senderAccountName: row.frAccName,
      senderAccountHash: row.frAccNo
        ? this.crypto.sensitiveHash(row.frAccNo)
        : null,
      senderAccountMasked: this.crypto.maskAccount(row.frAccNo),
      senderBankName: row.frBankName,
      endingBalance: row.endBal,
      channelReference: row.channelRef,
      channelId: row.channelID,
      businessDate: row.businessDateValue,
      receiverBankCode: row.toBankCode,
      receiverAccountName: row.toAccName,
      receiverAccountHash: row.toAccNo
        ? this.crypto.sensitiveHash(row.toAccNo)
        : null,
      receiverAccountMasked: this.crypto.maskAccount(row.toAccNo),
      receiverBankName: row.toBankName,
      virtualAccountHash: row.va ? this.crypto.sensitiveHash(row.va) : null,
      virtualAccountMasked: this.crypto.maskAccount(row.va),
      showroomCodeHint: row.showroomCodeHint,
      transactionCode: row.transCode,
      extensions: row.extensions as Prisma.InputJsonObject,
      conflictStatus: hasConflict ? 'CONFLICT' : 'NONE',
      projectionStatus: hasConflict ? 'CONFLICT' : 'PENDING',
      projectionReason: hasConflict ? 'identity_payload_conflict' : null,
      retainedUntil: new Date(Date.now() + retentionDays * 24 * 60 * 60 * 1000),
    };
  }

  private async decryptWithActiveKey(encryptedData: string) {
    const keys = await (this.prisma as any).bankPgpKey.findMany({
      where: {
        bankCode: 'BIDV',
        status: 'ACTIVE',
        OR: [
          { overlapExpiresAt: null },
          { overlapExpiresAt: { gt: new Date() } },
        ],
      },
      orderBy: { version: 'desc' },
      take: 2,
    });
    if (keys.length === 0) {
      throw new ServiceUnavailableException(
        'Chưa có khóa giải mã đang hoạt động.',
      );
    }
    let lastError: unknown;
    for (const key of keys) {
      try {
        return await this.crypto.decryptPayload(
          encryptedData,
          key.privateKeyCipher,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  private requestId(value: unknown) {
    const requestId = Array.isArray(value) ? value[0] : value;
    if (
      typeof requestId !== 'string' ||
      !requestId.trim() ||
      requestId.length > 200 ||
      /[\r\n]/.test(requestId)
    ) {
      throw new ConflictException('Thiếu REQUESTID hợp lệ.');
    }
    return requestId.trim();
  }

  private requestRef(value: string) {
    return createHash('sha256').update(value).digest('hex').slice(0, 12);
  }
}
