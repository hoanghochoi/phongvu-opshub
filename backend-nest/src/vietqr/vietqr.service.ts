import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MapVietinService } from '../map-vietin/map-vietin.service';

export interface CreateVietQrInput {
  amount?: number | null;
  orderCode?: string | null;
  storeCode: string;
  createdById?: string | null;
}

export interface VietQrResponse {
  id: string;
  bankBin: string;
  bankName: string;
  accountNumber: string;
  accountName: string;
  amount: number | null;
  transferContent: string;
  qrPayload: string;
  status: string;
  createdAt: Date;
}

type MapTransaction = Record<string, unknown>;

@Injectable()
export class VietQrService {
  private readonly bankBinsByName: Record<string, string> = {
    VIETINBANK: '970415',
    ICB: '970415',
    VIETCOMBANK: '970436',
    VCB: '970436',
  };
  private readonly bankNamesByBin: Record<string, string> = {
    '970415': 'VietinBank',
    '970436': 'Vietcombank',
  };

  constructor(
    private prisma: PrismaService,
    private mapVietinService?: MapVietinService,
  ) {}

  async create(input: CreateVietQrInput): Promise<VietQrResponse> {
    const config = await this.getConfig(input.storeCode);
    const amount = this.normalizeAmount(input.amount);
    const storeCode = this.normalizeText(input.storeCode, 'storeCode');
    const orderCode = this.normalizeOptionalText(input.orderCode);
    const transferContent = orderCode
      ? this.normalizeTransferContent(`${orderCode} ${storeCode} BOT`)
      : '';

    const merchantAccountInfo = this.buildMerchantAccountInfo(
      config.bankBin,
      config.accountNumber,
    );
    const payloadWithoutCrc = [
      this.field('00', '01'),
      this.field('01', '12'),
      this.field('38', merchantAccountInfo),
      this.field('53', '704'),
      amount === null ? '' : this.field('54', String(amount)),
      this.field('58', 'VN'),
      this.field('59', config.accountName),
      this.field('60', config.city),
      transferContent
        ? this.field('62', this.field('08', transferContent))
        : '',
      '6304',
    ].join('');

    const paymentIntent = await this.prisma.vietQrPaymentIntent.create({
      data: {
        storeCode,
        createdById: input.createdById || null,
        amount,
        orderCode: orderCode || null,
        transferContent,
        qrPayload: `${payloadWithoutCrc}${this.crc16(payloadWithoutCrc)}`,
      },
    });

    return {
      id: paymentIntent.id,
      bankBin: config.bankBin,
      bankName: config.bankName,
      accountNumber: config.accountNumber,
      accountName: config.accountName,
      amount,
      transferContent,
      qrPayload: paymentIntent.qrPayload,
      status: paymentIntent.status,
      createdAt: paymentIntent.createdAt,
    };
  }

  async confirmPayment(user: any, paymentIntentId: string) {
    if (!this.mapVietinService) {
      throw new ServiceUnavailableException('Chưa cấu hình dịch vụ MAP');
    }

    const intent = await this.prisma.vietQrPaymentIntent.findUnique({
      where: { id: paymentIntentId },
    });
    if (!intent) throw new NotFoundException('Không tìm thấy mã QR');
    await this.assertCanAccessIntent(user, intent.storeCode);

    if (intent.status === 'PAID') {
      return {
        id: intent.id,
        status: intent.status,
        confirmed: true,
        reason: 'ALREADY_CONFIRMED',
        matchedTransactionNumber: intent.matchedTransactionNumber,
        confirmedAt: intent.confirmedAt,
      };
    }

    if (!intent.amount || !intent.transferContent) {
      return this.updateCheckResult(intent.id, 'MANUAL_REVIEW', {
        confirmed: false,
        reason: 'MISSING_MATCH_FIELDS',
        message:
          'QR thiếu số tiền hoặc nội dung chuyển khoản nên không thể tự xác nhận',
      });
    }

    const now = new Date();
    const searchResult =
      await this.mapVietinService.searchTransactionsForStoreCode(
        intent.storeCode,
        {
          startDate: this.formatMapDate(intent.createdAt),
          endDate: this.formatMapDate(now),
          amount: String(intent.amount),
          page: 0,
          size: 100,
        },
      );

    const matches = (searchResult.list as MapTransaction[]).filter((row) =>
      this.isMatchingTransaction(row, intent),
    );

    if (matches.length === 1) {
      const match = matches[0];
      const matchedTranTime = this.readTransactionTime(match);
      const updated = await this.prisma.vietQrPaymentIntent.update({
        where: { id: intent.id },
        data: {
          status: 'PAID',
          matchedTransactionId: this.readText(match, 'id'),
          matchedTransactionNumber: this.readText(match, 'transactionNumber'),
          matchedAmount: this.readAmount(match),
          matchedTranTime,
          confirmedAt: now,
          lastCheckedAt: now,
          lastCheckResult: this.buildCheckResult('MATCHED', matches.length),
        },
      });

      return {
        id: updated.id,
        status: updated.status,
        confirmed: true,
        reason: 'MATCHED',
        matchedTransactionNumber: updated.matchedTransactionNumber,
        matchedAmount: updated.matchedAmount,
        matchedTranTime: updated.matchedTranTime,
        confirmedAt: updated.confirmedAt,
      };
    }

    const status = matches.length > 1 ? 'AMBIGUOUS' : 'NOT_FOUND';
    return this.updateCheckResult(intent.id, status, {
      confirmed: false,
      reason: matches.length > 1 ? 'MULTIPLE_MATCHES' : 'NO_MATCH',
      totalCandidates: searchResult.total,
      matchedCandidates: matches.length,
    });
  }

  private async assertCanAccessIntent(user: any, storeCode: string) {
    if (user.role === 'SUPER_ADMIN') return;
    if (!user.storeId) throw new ForbiddenException('Tài khoản chưa có showroom');
    const store = await this.prisma.store.findUnique({ where: { id: user.storeId } });
    if (!store || store.storeId !== storeCode) {
      throw new ForbiddenException('Không có quyền xác nhận QR của showroom khác');
    }
  }

  private async updateCheckResult(
    id: string,
    status: string,
    result: Record<string, unknown>,
  ) {
    const updated = await this.prisma.vietQrPaymentIntent.update({
      where: { id },
      data: {
        status,
        lastCheckedAt: new Date(),
        lastCheckResult: result as Prisma.InputJsonObject,
      },
    });
    return {
      id: updated.id,
      status: updated.status,
      ...result,
      lastCheckedAt: updated.lastCheckedAt,
    };
  }

  private isMatchingTransaction(row: MapTransaction, intent: any) {
    if (this.readAmount(row) !== intent.amount) return false;
    if (!this.isSuccessfulTransaction(row)) return false;

    const tranTime = this.readTransactionTime(row);
    if (!tranTime) return false;
    const lowerBound = new Date(intent.createdAt.getTime() - 10 * 60 * 1000);
    if (tranTime < lowerBound) return false;
    if (tranTime > new Date(Date.now() + 5 * 60 * 1000)) return false;

    return this.transactionContentMatches(row, intent);
  }

  private transactionContentMatches(row: MapTransaction, intent: any) {
    const transactionContent = this.normalizeMatchText(
      this.readText(row, 'transactionDescription'),
    );
    const transferContent = this.normalizeMatchText(intent.transferContent);

    return Boolean(
      transferContent && transactionContent.includes(transferContent),
    );
  }

  private isSuccessfulTransaction(row: MapTransaction) {
    const statusText = this.normalizeMatchText(
      `${this.readText(row, 'statusText')} ${this.readText(row, 'status')}`,
    );
    return (
      statusText.includes('THANH CONG') ||
      statusText.includes('SUCCESS') ||
      statusText.includes('DA THANH TOAN')
    );
  }

  private readText(row: MapTransaction, key: string) {
    const value = row[key];
    return value === null || value === undefined ? '' : String(value).trim();
  }

  private readAmount(row: MapTransaction) {
    const value = row.amount;
    if (typeof value === 'number') return Math.trunc(value);
    const normalized = String(value || '').replace(/[^0-9]/g, '');
    return normalized ? Number(normalized) : null;
  }

  private readTransactionTime(row: MapTransaction) {
    const raw = this.readText(row, 'tranTime') || this.readText(row, 'txnDate');
    if (!raw) return null;
    const match = /^(\d{2})\/(\d{2})\/(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(
      raw,
    );
    if (!match) {
      const parsed = new Date(raw);
      return Number.isNaN(parsed.getTime()) ? null : parsed;
    }
    return new Date(
      Number(match[3]),
      Number(match[2]) - 1,
      Number(match[1]),
      Number(match[4] || '0'),
      Number(match[5] || '0'),
      Number(match[6] || '0'),
    );
  }

  private buildCheckResult(reason: string, matchedCandidates: number) {
    return { confirmed: reason === 'MATCHED', reason, matchedCandidates };
  }

  private normalizeMatchText(value: string) {
    return (value || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/Đ/g, 'D')
      .replace(/đ/g, 'd')
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private formatMapDate(value: Date) {
    return [
      String(value.getDate()).padStart(2, '0'),
      String(value.getMonth() + 1).padStart(2, '0'),
      value.getFullYear(),
    ].join('/');
  }

  private async getConfig(storeCode: string) {
    const store = storeCode
      ? await this.prisma.store.findUnique({ where: { storeId: storeCode } })
      : null;
    const bankBin =
      store?.transferBankBin?.trim() ||
      this.resolveBankBin(store?.transferBankName) ||
      this.getEnv('VIETQR_BANK_BIN');
    const accountNumber =
      store?.transferAccountNumber?.trim() ||
      this.getEnv('VIETQR_ACCOUNT_NUMBER');
    const accountName = this.normalizeTransferContent(
      store?.transferAccountName?.trim() || this.getEnv('VIETQR_ACCOUNT_NAME'),
    );
    const city = this.normalizeTransferContent(
      process.env.VIETQR_MERCHANT_CITY || 'HO CHI MINH',
    );

    if (!bankBin || !accountNumber || !accountName) {
      throw new ServiceUnavailableException(
        'Thiếu cấu hình VietQR trên backend',
      );
    }

    return {
      bankBin,
      bankName: this.resolveBankName(store?.transferBankName, bankBin),
      accountNumber,
      accountName,
      city,
    };
  }

  private resolveBankBin(bankName?: string | null): string {
    const normalized = this.normalizeTransferContent(bankName || '').replace(
      /\s+/g,
      '',
    );
    return this.bankBinsByName[normalized] || '';
  }

  private resolveBankName(
    bankName: string | null | undefined,
    bankBin: string,
  ) {
    const normalized = (bankName || '').trim();
    return normalized || this.bankNamesByBin[bankBin] || bankBin;
  }

  private getEnv(key: string): string {
    return (process.env[key] || '').trim();
  }

  private normalizeAmount(amount: number | null | undefined): number | null {
    if (amount === null || amount === undefined) {
      return null;
    }
    if (!Number.isInteger(amount) || amount <= 0 || amount > 999999999999) {
      throw new BadRequestException('Số tiền VietQR không hợp lệ');
    }
    return amount;
  }

  private normalizeText(value: string, fieldName: string): string {
    const normalized = this.normalizeTransferContent(value);
    if (!normalized) {
      throw new BadRequestException(`${fieldName} không được để trống`);
    }
    return normalized;
  }

  private normalizeOptionalText(value: string | null | undefined): string {
    return this.normalizeTransferContent(value || '');
  }

  private normalizeTransferContent(value: string): string {
    return (value || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/Đ/g, 'D')
      .replace(/đ/g, 'd')
      .toUpperCase()
      .replace(/[^A-Z0-9 ._-]/g, '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 99);
  }

  private buildMerchantAccountInfo(bankBin: string, accountNumber: string) {
    const consumerAccount = [
      this.field('00', bankBin),
      this.field('01', accountNumber),
    ].join('');

    return [
      this.field('00', 'A000000727'),
      this.field('01', consumerAccount),
      this.field('02', 'QRIBFTTA'),
    ].join('');
  }

  private field(id: string, value: string): string {
    return `${id}${value.length.toString().padStart(2, '0')}${value}`;
  }

  private crc16(value: string): string {
    let crc = 0xffff;
    for (let i = 0; i < value.length; i += 1) {
      crc ^= value.charCodeAt(i) << 8;
      for (let bit = 0; bit < 8; bit += 1) {
        crc = (crc & 0x8000) !== 0 ? (crc << 1) ^ 0x1021 : crc << 1;
        crc &= 0xffff;
      }
    }
    return crc.toString(16).toUpperCase().padStart(4, '0');
  }
}
