import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { getBidvH2hConfig } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { BidvH2hCryptoService } from './bidv-h2h-crypto.service';
import {
  BidvOperatingMode,
  normalizedOperatingMode,
} from './bidv-h2h-operating-mode';

const BANK_CODE = 'BIDV';

export type BidvOperatingAssessment = {
  operatingMode: BidvOperatingMode;
  effectiveMode: BidvOperatingMode;
  ready: boolean;
  readiness: {
    infrastructure: boolean;
    kek: boolean;
    client: boolean;
    openPgpKey: boolean;
  };
  blockers: string[];
};

@Injectable()
export class BidvH2hOperatingPolicy {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: BidvH2hCryptoService,
  ) {}

  async evaluate(db: any = this.prisma): Promise<BidvOperatingAssessment> {
    const config = getBidvH2hConfig();
    const now = new Date();
    const usableWhere = {
      bankCode: BANK_CODE,
      status: 'ACTIVE',
      OR: [{ overlapExpiresAt: null }, { overlapExpiresAt: { gt: now } }],
    };
    const [control, client, key] = await Promise.all([
      db.bankConnectionControl.findUnique({ where: { bankCode: BANK_CODE } }),
      db.bankApiClient.findFirst({ where: usableWhere, select: { id: true } }),
      db.bankPgpKey.findFirst({
        where: usableWhere,
        select: { id: true, privateKeyCipher: true },
      }),
    ]);

    let keyReadable = false;
    if (config.kek && key?.privateKeyCipher) {
      try {
        this.crypto.decryptPrivateKey(key.privateKeyCipher);
        keyReadable = true;
      } catch {
        keyReadable = false;
      }
    }
    const readiness = {
      infrastructure: config.infrastructureReady,
      kek: Boolean(config.kek) && (!key || keyReadable),
      client: Boolean(client),
      openPgpKey: Boolean(key) && keyReadable,
    };
    const blockers: string[] = [];
    if (!readiness.infrastructure)
      blockers.push(
        'Hạ tầng kết nối chưa sẵn sàng. Vui lòng liên hệ kỹ thuật.',
      );
    if (!readiness.client) blockers.push('Hãy tạo OAuth client trước.');
    if (!readiness.openPgpKey) blockers.push('Hãy tạo khóa OpenPGP trước.');
    const ready = Object.values(readiness).every(Boolean);
    const operatingMode = normalizedOperatingMode(control);
    return {
      operatingMode,
      effectiveMode: ready ? operatingMode : 'STOPPED',
      ready,
      readiness,
      blockers,
    };
  }

  async assertIngress(db: any = this.prisma) {
    const assessment = await this.evaluate(db);
    if (assessment.effectiveMode === 'STOPPED') this.unavailable();
    return assessment;
  }

  async assertLive(db: any = this.prisma) {
    const assessment = await this.evaluate(db);
    if (assessment.effectiveMode !== 'LIVE') this.unavailable();
    return assessment;
  }

  async lock(tx: any) {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('opshub:bidv-h2h-control'))`;
  }

  unavailable(): never {
    throw new ServiceUnavailableException({
      error: 'temporarily_unavailable',
      error_description: 'Kênh kết nối đang tạm dừng. Vui lòng thử lại sau.',
    });
  }
}
