import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';

export interface CreateVietQrInput {
  amount: number;
  orderCode: string;
  storeCode: string;
}

export interface VietQrResponse {
  bankBin: string;
  accountNumber: string;
  accountName: string;
  amount: number;
  transferContent: string;
  qrPayload: string;
}

@Injectable()
export class VietQrService {
  create(input: CreateVietQrInput): VietQrResponse {
    const config = this.getConfig();
    const amount = this.normalizeAmount(input.amount);
    const orderCode = this.normalizeText(input.orderCode, 'orderCode');
    const storeCode = this.normalizeText(input.storeCode, 'storeCode');
    const transferContent = this.normalizeTransferContent(
      `${storeCode}-${orderCode}`,
    );

    const merchantAccountInfo = this.buildMerchantAccountInfo(
      config.bankBin,
      config.accountNumber,
    );
    const additionalData = this.field('08', transferContent);
    const payloadWithoutCrc = [
      this.field('00', '01'),
      this.field('01', '12'),
      this.field('38', merchantAccountInfo),
      this.field('53', '704'),
      this.field('54', String(amount)),
      this.field('58', 'VN'),
      this.field('59', config.accountName),
      this.field('60', config.city),
      this.field('62', additionalData),
      '6304',
    ].join('');

    return {
      bankBin: config.bankBin,
      accountNumber: config.accountNumber,
      accountName: config.accountName,
      amount,
      transferContent,
      qrPayload: `${payloadWithoutCrc}${this.crc16(payloadWithoutCrc)}`,
    };
  }

  private getConfig() {
    const bankBin = this.getEnv('VIETQR_BANK_BIN');
    const accountNumber = this.getEnv('VIETQR_ACCOUNT_NUMBER');
    const accountName = this.normalizeTransferContent(
      this.getEnv('VIETQR_ACCOUNT_NAME'),
    );
    const city = this.normalizeTransferContent(
      process.env.VIETQR_MERCHANT_CITY || 'HO CHI MINH',
    );

    if (!bankBin || !accountNumber || !accountName) {
      throw new ServiceUnavailableException(
        'Thiếu cấu hình VietQR trên backend',
      );
    }

    return { bankBin, accountNumber, accountName, city };
  }

  private getEnv(key: string): string {
    return (process.env[key] || '').trim();
  }

  private normalizeAmount(amount: number): number {
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
