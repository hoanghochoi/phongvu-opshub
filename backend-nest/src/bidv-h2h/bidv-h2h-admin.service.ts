import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { hash } from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { isSuperAdminRole } from '../common/system-role';
import { getBidvH2hConfig } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import {
  BidvH2hCryptoService,
  ValidatedPgpKeyPair,
} from './bidv-h2h-crypto.service';
import { UpdateBankConnectionControlDto } from './bidv-h2h.dto';

const BANK_CODE = 'BIDV';
const MAX_ACTIVE_VERSIONS = 2;

@Injectable()
export class BidvH2hAdminService {
  private readonly logger = new Logger(BidvH2hAdminService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: BidvH2hCryptoService,
  ) {}

  async snapshot(actor: any) {
    this.assertSuperAdmin(actor, 'snapshot');
    const [clients, keys, control, audits] = await Promise.all([
      (this.prisma as any).bankApiClient.findMany({
        where: { bankCode: BANK_CODE },
        orderBy: [{ version: 'desc' }, { createdAt: 'desc' }],
      }),
      (this.prisma as any).bankPgpKey.findMany({
        where: { bankCode: BANK_CODE },
        orderBy: [{ version: 'desc' }, { createdAt: 'desc' }],
      }),
      this.getControl(),
      (this.prisma as any).bankConnectionAudit.findMany({
        where: { bankCode: BANK_CODE },
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
    ]);
    const config = getBidvH2hConfig();
    return {
      bankCode: BANK_CODE,
      environment: config.environment,
      publicBaseUrl: config.publicBaseUrl,
      controls: {
        ingressRequested: control.ingressEnabled,
        projectionRequested: control.projectionEnabled,
        ingressMasterEnabled: config.ingestMasterEnabled,
        projectionMasterEnabled: config.projectionMasterEnabled,
        ingressEffective: config.ingestMasterEnabled && control.ingressEnabled,
        projectionEffective:
          config.projectionMasterEnabled && control.projectionEnabled,
        version: control.version,
        updatedAt: control.updatedAt,
      },
      clients: clients.map((client: any) => this.serializeClient(client)),
      keys: keys.map((key: any) => this.serializeKey(key)),
      audits: audits.map((audit: any) => ({
        id: audit.id,
        action: audit.action,
        targetType: audit.targetType,
        targetId: audit.targetId,
        summary: audit.summary,
        createdAt: audit.createdAt,
      })),
    };
  }

  async createClient(actor: any, displayName: string) {
    this.assertSuperAdmin(actor, 'create_client');
    const clientId = `bidv_${randomBytes(16).toString('hex')}`;
    const clientSecret = randomBytes(32).toString('base64url');
    const secretHash = await hash(clientSecret, 12);
    const client = await this.prisma.$transaction(async (tx) => {
      await this.lockControlPlane(tx);
      await this.assertActiveCapacity(tx, 'bankApiClient');
      const maximum = await (tx as any).bankApiClient.aggregate({
        where: { bankCode: BANK_CODE },
        _max: { version: true },
      });
      const created = await (tx as any).bankApiClient.create({
        data: {
          displayName: displayName.trim(),
          clientId,
          secretHash,
          version: Number(maximum._max.version ?? 0) + 1,
          createdByUserId: actor?.id ?? null,
          createdByEmailHash: this.actorEmailHash(actor),
        },
      });
      await this.audit(tx, actor, 'CLIENT_CREATED', 'CLIENT', created.id, {
        version: created.version,
        displayName: created.displayName,
      });
      return created;
    });
    this.logger.log(
      `BIDV API client created clientRef=${client.id} version=${client.version}`,
    );
    return { ...this.serializeClient(client), clientSecret };
  }

  async rotateClient(actor: any, id: string) {
    this.assertSuperAdmin(actor, 'rotate_client');
    const clientId = `bidv_${randomBytes(16).toString('hex')}`;
    const clientSecret = randomBytes(32).toString('base64url');
    const secretHash = await hash(clientSecret, 12);
    const overlapExpiresAt = this.overlapExpiresAt();
    const created = await this.prisma.$transaction(async (tx) => {
      await this.lockControlPlane(tx);
      const current = await (tx as any).bankApiClient.findUnique({
        where: { id },
      });
      if (!current || current.bankCode !== BANK_CODE)
        throw new NotFoundException('Không tìm thấy client cần xoay vòng.');
      if (!this.recordUsable(current))
        throw new ConflictException(
          'Client này không còn hoạt động để xoay vòng.',
        );
      await this.assertActiveCapacity(tx, 'bankApiClient');
      await (tx as any).bankApiClient.update({
        where: { id },
        data: { overlapExpiresAt },
      });
      const next = await (tx as any).bankApiClient.create({
        data: {
          displayName: current.displayName,
          clientId,
          secretHash,
          version: current.version + 1,
          createdByUserId: actor?.id ?? null,
          createdByEmailHash: this.actorEmailHash(actor),
        },
      });
      await this.audit(tx, actor, 'CLIENT_ROTATED', 'CLIENT', next.id, {
        previousId: current.id,
        version: next.version,
        overlapExpiresAt: overlapExpiresAt.toISOString(),
      });
      return next;
    });
    this.logger.log(
      `BIDV API client rotated clientRef=${created.id} version=${created.version}`,
    );
    return { ...this.serializeClient(created), clientSecret };
  }

  async revokeClient(actor: any, id: string, recoveryOverride = false) {
    this.assertSuperAdmin(actor, 'revoke_client');
    const revoked = await this.prisma.$transaction(async (tx) => {
      await this.lockControlPlane(tx);
      const current = await (tx as any).bankApiClient.findUnique({
        where: { id },
      });
      if (!current || current.bankCode !== BANK_CODE)
        throw new NotFoundException('Không tìm thấy client cần thu hồi.');
      if (current.status === 'REVOKED') return current;
      const usableCount = await this.usableCount(tx, 'bankApiClient', id);
      if (usableCount === 0 && !recoveryOverride) {
        throw new ConflictException(
          'Không thể thu hồi client cuối cùng. Hãy tạo client thay thế trước.',
        );
      }
      const now = new Date();
      const result = await (tx as any).bankApiClient.update({
        where: { id },
        data: { status: 'REVOKED', revokedAt: now, overlapExpiresAt: null },
      });
      await (tx as any).bankAccessToken.updateMany({
        where: { clientRefId: id, revokedAt: null },
        data: { revokedAt: now },
      });
      await this.audit(tx, actor, 'CLIENT_REVOKED', 'CLIENT', id, {
        recoveryOverride,
      });
      return result;
    });
    this.logger.warn(
      `BIDV API client revoked clientRef=${id} override=${recoveryOverride}`,
    );
    return this.serializeClient(revoked);
  }

  async generateKey(actor: any, displayName: string) {
    this.assertSuperAdmin(actor, 'generate_key');
    const pair = await this.crypto.generateKeyPair(displayName.trim());
    return this.persistKey(actor, displayName.trim(), pair, null);
  }

  async importKey(
    actor: any,
    input: {
      displayName: string;
      publicKeyArmor: string;
      privateKeyArmor: string;
      passphrase?: string;
    },
  ) {
    this.assertSuperAdmin(actor, 'import_key');
    const pair = await this.crypto.validateImportedKeyPair(
      input.publicKeyArmor,
      input.privateKeyArmor,
      input.passphrase,
    );
    return this.persistKey(actor, input.displayName.trim(), pair, null, true);
  }

  async rotateKey(actor: any, id: string) {
    this.assertSuperAdmin(actor, 'rotate_key');
    const current = await (this.prisma as any).bankPgpKey.findUnique({
      where: { id },
    });
    if (!current || current.bankCode !== BANK_CODE)
      throw new NotFoundException('Không tìm thấy khóa cần xoay vòng.');
    if (!this.recordUsable(current))
      throw new ConflictException('Khóa này không còn hoạt động để xoay vòng.');
    const pair = await this.crypto.generateKeyPair(current.displayName);
    return this.persistKey(actor, current.displayName, pair, id);
  }

  async revokeKey(actor: any, id: string, recoveryOverride = false) {
    this.assertSuperAdmin(actor, 'revoke_key');
    const revoked = await this.prisma.$transaction(async (tx) => {
      await this.lockControlPlane(tx);
      const current = await (tx as any).bankPgpKey.findUnique({
        where: { id },
      });
      if (!current || current.bankCode !== BANK_CODE)
        throw new NotFoundException('Không tìm thấy khóa cần thu hồi.');
      if (current.status === 'REVOKED') return current;
      const usableCount = await this.usableCount(tx, 'bankPgpKey', id);
      if (usableCount === 0 && !recoveryOverride) {
        throw new ConflictException(
          'Không thể thu hồi khóa cuối cùng. Hãy tạo khóa thay thế trước.',
        );
      }
      const result = await (tx as any).bankPgpKey.update({
        where: { id },
        data: {
          status: 'REVOKED',
          revokedAt: new Date(),
          overlapExpiresAt: null,
        },
      });
      await this.audit(tx, actor, 'KEY_REVOKED', 'PGP_KEY', id, {
        recoveryOverride,
      });
      return result;
    });
    this.logger.warn(
      `BIDV PGP key revoked keyRef=${id} override=${recoveryOverride}`,
    );
    return this.serializeKey(revoked);
  }

  async exportPublicKey(actor: any, id: string) {
    this.assertSuperAdmin(actor, 'export_public_key');
    const key = await this.prisma.$transaction(async (tx) => {
      const found = await (tx as any).bankPgpKey.findUnique({ where: { id } });
      if (!found || found.bankCode !== BANK_CODE) {
        throw new NotFoundException('Không tìm thấy khóa công khai.');
      }
      await this.audit(tx, actor, 'PUBLIC_KEY_EXPORTED', 'PGP_KEY', id, {
        fingerprint: found.fingerprint,
      });
      return found;
    });
    return {
      id: key.id,
      fingerprint: key.fingerprint,
      publicKeyArmor: key.publicKeyArmor,
      fileName: `opshub-bidv-${key.fingerprint.slice(-16)}.asc`,
    };
  }

  async updateControl(actor: any, input: UpdateBankConnectionControlDto) {
    this.assertSuperAdmin(actor, 'update_control');
    if (input.projectionEnabled && !input.ingressEnabled) {
      throw new BadRequestException(
        'Cần bật tiếp nhận trước khi bật đối soát tự động.',
      );
    }
    const result = await this.prisma.$transaction(async (tx) => {
      await this.lockControlPlane(tx);
      const control = await (tx as any).bankConnectionControl.upsert({
        where: { bankCode: BANK_CODE },
        create: {
          bankCode: BANK_CODE,
          ingressEnabled: input.ingressEnabled,
          projectionEnabled: input.projectionEnabled,
          updatedByUserId: actor?.id ?? null,
        },
        update: {
          ingressEnabled: input.ingressEnabled,
          projectionEnabled: input.projectionEnabled,
          version: { increment: 1 },
          updatedByUserId: actor?.id ?? null,
        },
      });
      await this.audit(tx, actor, 'CONTROL_UPDATED', 'CONTROL', BANK_CODE, {
        ingressEnabled: input.ingressEnabled,
        projectionEnabled: input.projectionEnabled,
        version: control.version,
      });
      return control;
    });
    this.logger.warn(
      `BIDV connection control updated ingress=${result.ingressEnabled} projection=${result.projectionEnabled} version=${result.version}`,
    );
    return this.snapshot(actor);
  }

  private async persistKey(
    actor: any,
    displayName: string,
    pair: ValidatedPgpKeyPair,
    previousId: string | null,
    imported = false,
  ) {
    const privateKeyCipher = this.crypto.encryptPrivateKey(
      pair.privateKeyArmor,
    );
    const overlapExpiresAt = previousId ? this.overlapExpiresAt() : null;
    const key = await this.prisma.$transaction(async (tx) => {
      await this.lockControlPlane(tx);
      await this.assertActiveCapacity(tx, 'bankPgpKey');
      let version = 1;
      if (previousId) {
        const previous = await (tx as any).bankPgpKey.findUnique({
          where: { id: previousId },
        });
        if (!previous || !this.recordUsable(previous))
          throw new ConflictException('Khóa cũ không còn hoạt động.');
        version = previous.version + 1;
        await (tx as any).bankPgpKey.update({
          where: { id: previousId },
          data: { overlapExpiresAt },
        });
      } else {
        const maximum = await (tx as any).bankPgpKey.aggregate({
          where: { bankCode: BANK_CODE },
          _max: { version: true },
        });
        version = Number(maximum._max.version ?? 0) + 1;
      }
      const created = await (tx as any).bankPgpKey.create({
        data: {
          displayName,
          fingerprint: pair.fingerprint,
          algorithm: pair.algorithm,
          publicKeyArmor: pair.publicKeyArmor,
          privateKeyCipher,
          version,
          createdByUserId: actor?.id ?? null,
          createdByEmailHash: this.actorEmailHash(actor),
        },
      });
      await this.audit(
        tx,
        actor,
        previousId
          ? 'KEY_ROTATED'
          : imported
            ? 'KEY_IMPORTED'
            : 'KEY_GENERATED',
        'PGP_KEY',
        created.id,
        {
          fingerprint: created.fingerprint,
          version,
          previousId,
          overlapExpiresAt: overlapExpiresAt?.toISOString() ?? null,
        },
      );
      return created;
    });
    this.logger.log(
      `BIDV PGP key stored keyRef=${key.id} version=${key.version}`,
    );
    return this.serializeKey(key);
  }

  private async getControl() {
    return (this.prisma as any).bankConnectionControl.upsert({
      where: { bankCode: BANK_CODE },
      create: { bankCode: BANK_CODE },
      update: {},
    });
  }

  private serializeClient(client: any) {
    return {
      id: client.id,
      displayName: client.displayName,
      clientId: client.clientId,
      scope: client.scope,
      status: this.effectiveStatus(client),
      version: client.version,
      activatedAt: client.activatedAt,
      overlapExpiresAt: client.overlapExpiresAt,
      revokedAt: client.revokedAt,
      createdAt: client.createdAt,
      updatedAt: client.updatedAt,
    };
  }

  private serializeKey(key: any) {
    return {
      id: key.id,
      displayName: key.displayName,
      fingerprint: key.fingerprint,
      algorithm: key.algorithm,
      status: this.effectiveStatus(key),
      version: key.version,
      activatedAt: key.activatedAt,
      overlapExpiresAt: key.overlapExpiresAt,
      revokedAt: key.revokedAt,
      createdAt: key.createdAt,
      updatedAt: key.updatedAt,
    };
  }

  private effectiveStatus(record: any) {
    if (record.status === 'REVOKED') return 'REVOKED';
    if (record.overlapExpiresAt && record.overlapExpiresAt <= new Date())
      return 'EXPIRED';
    if (record.overlapExpiresAt) return 'OVERLAP';
    return 'ACTIVE';
  }

  private recordUsable(record: any) {
    return (
      record.status === 'ACTIVE' &&
      (!record.overlapExpiresAt || record.overlapExpiresAt > new Date())
    );
  }

  private async assertActiveCapacity(
    tx: any,
    model: 'bankApiClient' | 'bankPgpKey',
    excludedId?: string,
  ) {
    const count = await this.usableCount(tx, model, excludedId);
    if (count >= MAX_ACTIVE_VERSIONS) {
      throw new ConflictException(
        'Đã có tối đa hai phiên bản đang hoạt động. Hãy thu hồi một phiên bản trước.',
      );
    }
  }

  private usableCount(
    tx: any,
    model: 'bankApiClient' | 'bankPgpKey',
    excludedId?: string,
  ) {
    return (tx as any)[model].count({
      where: {
        bankCode: BANK_CODE,
        status: 'ACTIVE',
        ...(excludedId ? { id: { not: excludedId } } : {}),
        OR: [
          { overlapExpiresAt: null },
          { overlapExpiresAt: { gt: new Date() } },
        ],
      },
    });
  }

  private overlapExpiresAt() {
    return new Date(
      Date.now() + getBidvH2hConfig().rotationOverlapHours * 60 * 60 * 1000,
    );
  }

  private async lockControlPlane(tx: any) {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext('opshub:bidv-h2h-control'))`;
  }

  private audit(
    tx: any,
    actor: any,
    action: string,
    targetType: string,
    targetId: string,
    summary: Record<string, unknown>,
  ) {
    return (tx as any).bankConnectionAudit.create({
      data: {
        bankCode: BANK_CODE,
        actorUserId: actor?.id ?? null,
        actorEmailHash: this.actorEmailHash(actor),
        action,
        targetType,
        targetId,
        summary,
      },
    });
  }

  private actorEmailHash(actor: any) {
    const email = String(actor?.email ?? '')
      .trim()
      .toLowerCase();
    return email ? createHash('sha256').update(email).digest('hex') : null;
  }

  private assertSuperAdmin(actor: any, source: string) {
    if (isSuperAdminRole(actor?.role)) return;
    this.logger.warn(
      `BIDV admin access denied source=${source} actor=${actor?.id ?? 'unknown'} role=${actor?.role ?? 'unknown'}`,
    );
    throw new ForbiddenException(
      'Chỉ quản trị viên toàn hệ thống mới quản lý được kết nối ngân hàng.',
    );
  }
}
