import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'crypto';

const FIELD_NAMES = new Set([
  'transDate',
  'transTime',
  'accountNo',
  'dorc',
  'currency',
  'amount',
  'remark',
  'refNo',
  'frBankCode',
  'frAccName',
  'frAccNo',
  'frBankName',
  'seq',
  'endBal',
  'channelRef',
  'channelID',
  'toBankCode',
  'toAccName',
  'toAccNo',
  'toBankName',
  'va',
  'transCode',
  'businessDate',
  'ext1',
  'ext2',
  'ext3',
  'ext4',
  'ext5',
]);

export type ParsedBidvTransaction = {
  accountNo: string;
  amount: Prisma.Decimal;
  currency: string;
  transDate: string;
  transactionDateValue: Date;
  transTime: string;
  paidAt: Date;
  dorc: 'C' | 'D';
  seq: string;
  refNo: string;
  remark: string;
  frBankCode: string | null;
  frAccName: string | null;
  frAccNo: string | null;
  frBankName: string | null;
  endBal: Prisma.Decimal | null;
  channelRef: string | null;
  channelID: string | null;
  businessDate: string;
  businessDateValue: Date;
  toBankCode: string | null;
  toAccName: string | null;
  toAccNo: string | null;
  toBankName: string | null;
  va: string | null;
  showroomCodeHint: string | null;
  transCode: string | null;
  extensions: Record<string, string | null>;
  identityHash: string;
  payloadHash: string;
};

@Injectable()
export class BidvH2hParser {
  parsePayload(payload: string, maximumTransactions: number) {
    let decoded: unknown;
    try {
      decoded = JSON.parse(payload);
    } catch {
      throw new BadRequestException('Dữ liệu giao dịch không đúng định dạng.');
    }
    if (!Array.isArray(decoded) || decoded.length === 0) {
      throw new BadRequestException('Danh sách giao dịch không được để trống.');
    }
    if (decoded.length > maximumTransactions) {
      throw new BadRequestException(
        'Số giao dịch trong một lần gửi vượt giới hạn.',
      );
    }
    return decoded.map((item, index) => this.parseTransaction(item, index));
  }

  private parseTransaction(
    value: unknown,
    index: number,
  ): ParsedBidvTransaction {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw this.invalid(index, 'giao dịch phải là một đối tượng');
    }
    const row = value as Record<string, unknown>;
    const unknownFields = Object.keys(row).filter(
      (key) => !FIELD_NAMES.has(key),
    );
    if (unknownFields.length > 0) {
      throw this.invalid(index, 'có trường chưa được hỗ trợ');
    }
    const accountNo = this.required(row, 'accountNo', index, 64);
    const amountText = this.required(row, 'amount', index, 40);
    const amount = this.decimal(amountText, index, 'amount');
    if (!amount.isPositive())
      throw this.invalid(index, 'amount phải lớn hơn 0');
    const currency = this.required(row, 'currency', index, 3).toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency)) {
      throw this.invalid(index, 'currency không hợp lệ');
    }
    const transDate = this.required(row, 'transDate', index, 6);
    const transTime = this.required(row, 'transTime', index, 6);
    const date = this.parseDdMmYy(transDate, index, 'transDate');
    const paidAt = this.parseVietnamTime(date, transTime, index);
    const dorc = this.required(row, 'dorc', index, 1).toUpperCase();
    if (dorc !== 'C' && dorc !== 'D')
      throw this.invalid(index, 'dorc phải là C hoặc D');
    const businessDate = this.required(row, 'businessDate', index, 6);
    const businessDateValue = this.parseDdMmYy(
      businessDate,
      index,
      'businessDate',
    );
    const seq = this.required(row, 'seq', index, 80);
    const refNo = this.required(row, 'refNo', index, 160);
    const remark = this.required(row, 'remark', index, 1000, true);
    const va = this.optional(row, 'va', index, 160);
    const normalized = {
      accountNo,
      amount: amount.toString(),
      currency,
      transDate,
      transTime,
      dorc,
      seq,
      refNo,
      remark,
      frBankCode: this.optional(row, 'frBankCode', index, 40),
      frAccName: this.optional(row, 'frAccName', index, 300),
      frAccNo: this.optional(row, 'frAccNo', index, 160),
      frBankName: this.optional(row, 'frBankName', index, 300),
      endBal: this.optional(row, 'endBal', index, 40),
      channelRef: this.optional(row, 'channelRef', index, 200),
      channelID: this.optional(row, 'channelID', index, 80),
      businessDate,
      toBankCode: this.optional(row, 'toBankCode', index, 40),
      toAccName: this.optional(row, 'toAccName', index, 300),
      toAccNo: this.optional(row, 'toAccNo', index, 160),
      toBankName: this.optional(row, 'toBankName', index, 300),
      va,
      transCode: this.optional(row, 'transCode', index, 80),
      ext1: this.optional(row, 'ext1', index, 500),
      ext2: this.optional(row, 'ext2', index, 500),
      ext3: this.optional(row, 'ext3', index, 500),
      ext4: this.optional(row, 'ext4', index, 500),
      ext5: this.optional(row, 'ext5', index, 500),
    };
    return {
      accountNo,
      amount,
      currency,
      transDate,
      transactionDateValue: date,
      transTime,
      paidAt,
      dorc,
      seq,
      refNo,
      remark,
      frBankCode: normalized.frBankCode,
      frAccName: normalized.frAccName,
      frAccNo: normalized.frAccNo,
      frBankName: normalized.frBankName,
      endBal: normalized.endBal
        ? this.decimal(normalized.endBal, index, 'endBal')
        : null,
      channelRef: normalized.channelRef,
      channelID: normalized.channelID,
      businessDate,
      businessDateValue,
      toBankCode: normalized.toBankCode,
      toAccName: normalized.toAccName,
      toAccNo: normalized.toAccNo,
      toBankName: normalized.toBankName,
      va,
      showroomCodeHint: this.showroomCodeFromRemark(remark),
      transCode: normalized.transCode,
      extensions: {
        ext1: normalized.ext1,
        ext2: normalized.ext2,
        ext3: normalized.ext3,
        ext4: normalized.ext4,
        ext5: normalized.ext5,
      },
      identityHash: createHash('sha256')
        .update(['BIDV', accountNo, refNo, seq, businessDate].join('|'))
        .digest('hex'),
      payloadHash: createHash('sha256')
        .update(JSON.stringify(normalized))
        .digest('hex'),
    };
  }

  showroomCodeFromRemark(value: string) {
    const normalized = value.trim().replace(/\s+/g, ' ').toUpperCase();
    if (!normalized) return null;
    const parts = normalized.split(' ');
    const candidate = parts.at(-1) === 'BOT' ? parts.at(-2) : parts.at(-1);
    if (!candidate || !/^[A-Z0-9][A-Z0-9_-]{1,63}$/.test(candidate)) {
      return null;
    }
    return candidate;
  }

  private parseDdMmYy(value: string, index: number, field: string) {
    if (!/^\d{6}$/.test(value))
      throw this.invalid(index, `${field} không hợp lệ`);
    const day = Number(value.slice(0, 2));
    const month = Number(value.slice(2, 4));
    const year = 2000 + Number(value.slice(4, 6));
    const date = new Date(Date.UTC(year, month - 1, day));
    if (
      date.getUTCFullYear() !== year ||
      date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day
    ) {
      throw this.invalid(index, `${field} không hợp lệ`);
    }
    return date;
  }

  private parseVietnamTime(date: Date, value: string, index: number) {
    if (!/^\d{6}$/.test(value))
      throw this.invalid(index, 'transTime không hợp lệ');
    const hour = Number(value.slice(0, 2));
    const minute = Number(value.slice(2, 4));
    const second = Number(value.slice(4, 6));
    if (hour > 23 || minute > 59 || second > 59) {
      throw this.invalid(index, 'transTime không hợp lệ');
    }
    return new Date(
      Date.UTC(
        date.getUTCFullYear(),
        date.getUTCMonth(),
        date.getUTCDate(),
        hour - 7,
        minute,
        second,
      ),
    );
  }

  private decimal(value: string, index: number, field: string) {
    if (!/^-?\d+(?:\.\d{1,6})?$/.test(value)) {
      throw this.invalid(index, `${field} không hợp lệ`);
    }
    try {
      return new Prisma.Decimal(value);
    } catch {
      throw this.invalid(index, `${field} không hợp lệ`);
    }
  }

  private required(
    row: Record<string, unknown>,
    key: string,
    index: number,
    maxLength: number,
    allowEmpty = false,
  ) {
    const value = row[key];
    if (typeof value !== 'string')
      throw this.invalid(index, `${key} là bắt buộc`);
    const normalized = value.trim();
    if (!allowEmpty && !normalized)
      throw this.invalid(index, `${key} là bắt buộc`);
    if (normalized.length > maxLength)
      throw this.invalid(index, `${key} quá dài`);
    return normalized;
  }

  private optional(
    row: Record<string, unknown>,
    key: string,
    index: number,
    maxLength: number,
  ) {
    const value = row[key];
    if (value === undefined || value === null || value === '') return null;
    if (typeof value !== 'string')
      throw this.invalid(index, `${key} không hợp lệ`);
    const normalized = value.trim();
    if (normalized.length > maxLength)
      throw this.invalid(index, `${key} quá dài`);
    return normalized || null;
  }

  private invalid(index: number, reason: string) {
    return new BadRequestException(`Giao dịch thứ ${index + 1}: ${reason}.`);
  }
}
