import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
} from 'crypto';
import {
  decrypt,
  decryptKey,
  encrypt,
  createMessage,
  generateKey,
  readMessage,
  readPrivateKey,
  readKey,
} from 'openpgp';
import { getBidvH2hConfig } from '../config/env';

type Envelope = {
  v: 1;
  alg: 'A256GCM';
  iv: string;
  tag: string;
  ciphertext: string;
};

export type ValidatedPgpKeyPair = {
  fingerprint: string;
  algorithm: 'Ed25519+X25519';
  publicKeyArmor: string;
  privateKeyArmor: string;
};

@Injectable()
export class BidvH2hCryptoService {
  async generateKeyPair(displayName: string): Promise<ValidatedPgpKeyPair> {
    const generated = await generateKey({
      type: 'ecc',
      curve: 'ed25519Legacy',
      userIDs: [{ name: `OpsHub BIDV H2H - ${displayName}` }],
      subkeys: [{ curve: 'curve25519Legacy' }],
      format: 'armored',
    });
    return this.validateKeyPair(generated.publicKey, generated.privateKey);
  }

  async validateImportedKeyPair(
    publicKeyArmor: string,
    privateKeyArmor: string,
    passphrase?: string,
  ): Promise<ValidatedPgpKeyPair> {
    let privateKey = await readPrivateKey({ armoredKey: privateKeyArmor });
    if (!privateKey.isDecrypted()) {
      if (!passphrase) {
        throw new BadRequestException(
          'Khóa riêng đang được bảo vệ. Vui lòng nhập mật khẩu khóa để kiểm tra.',
        );
      }
      privateKey = await decryptKey({ privateKey, passphrase });
    }
    return this.validateKeyPair(publicKeyArmor, privateKey.armor());
  }

  async decryptPayload(base64Armor: string, privateKeyCipher: string) {
    const encodedBytes = Buffer.byteLength(base64Armor, 'utf8');
    const maximum = getBidvH2hConfig().maxEncodedBodyBytes;
    if (encodedBytes > maximum) {
      throw new BadRequestException('Dữ liệu mã hóa vượt giới hạn cho phép.');
    }
    if (!/^[A-Za-z0-9+/=\r\n]+$/.test(base64Armor)) {
      throw new BadRequestException(
        'Dữ liệu mã hóa không đúng định dạng Base64.',
      );
    }
    let armoredMessage: string;
    try {
      armoredMessage = Buffer.from(base64Armor, 'base64').toString('utf8');
    } catch {
      throw new BadRequestException(
        'Dữ liệu mã hóa không đúng định dạng Base64.',
      );
    }
    if (!armoredMessage.includes('-----BEGIN PGP MESSAGE-----')) {
      throw new BadRequestException('Dữ liệu không phải thông điệp OpenPGP.');
    }
    try {
      const decryptionKey = await readPrivateKey({
        armoredKey: this.decryptPrivateKey(privateKeyCipher),
      });
      const message = await readMessage({ armoredMessage });
      const result = await decrypt({
        message,
        decryptionKeys: decryptionKey,
        format: 'utf8',
        config: { maxDecompressedMessageSize: maximum },
      });
      return result.data;
    } catch {
      throw new BadRequestException('Không giải mã được dữ liệu giao dịch.');
    }
  }

  encryptPrivateKey(privateKeyArmor: string) {
    const kek = this.requiredKek();
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', kek, iv);
    const ciphertext = Buffer.concat([
      cipher.update(privateKeyArmor, 'utf8'),
      cipher.final(),
    ]);
    const envelope: Envelope = {
      v: 1,
      alg: 'A256GCM',
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    };
    return Buffer.from(JSON.stringify(envelope), 'utf8').toString('base64');
  }

  decryptPrivateKey(value: string) {
    const kek = this.requiredKek();
    let envelope: Envelope;
    try {
      envelope = JSON.parse(Buffer.from(value, 'base64').toString('utf8'));
    } catch {
      throw new ServiceUnavailableException('Kho khóa kết nối không đọc được.');
    }
    if (envelope.v !== 1 || envelope.alg !== 'A256GCM') {
      throw new ServiceUnavailableException(
        'Phiên bản kho khóa chưa được hỗ trợ.',
      );
    }
    try {
      const decipher = createDecipheriv(
        'aes-256-gcm',
        kek,
        Buffer.from(envelope.iv, 'base64'),
      );
      decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
      return Buffer.concat([
        decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
        decipher.final(),
      ]).toString('utf8');
    } catch {
      throw new ServiceUnavailableException('Không mở được kho khóa kết nối.');
    }
  }

  sensitiveHash(value: string) {
    return createHmac('sha256', this.requiredKek())
      .update(
        value
          .trim()
          .replace(/[^A-Z0-9]/gi, '')
          .toUpperCase(),
      )
      .digest('hex');
  }

  maskAccount(value: string | null) {
    if (!value) return null;
    const normalized = value.trim().replace(/\s+/g, '');
    if (normalized.length <= 4) return '*'.repeat(normalized.length);
    return `${'*'.repeat(Math.min(8, normalized.length - 4))}${normalized.slice(-4)}`;
  }

  private async validateKeyPair(
    publicKeyArmor: string,
    privateKeyArmor: string,
  ): Promise<ValidatedPgpKeyPair> {
    try {
      const publicKey = await readKey({ armoredKey: publicKeyArmor });
      const privateKey = await readPrivateKey({ armoredKey: privateKeyArmor });
      if (publicKey.getFingerprint() !== privateKey.getFingerprint()) {
        throw new Error('fingerprint mismatch');
      }
      const primaryAlgorithm = publicKey.getAlgorithmInfo();
      const encryptionAlgorithm = (
        await publicKey.getEncryptionKey()
      ).getAlgorithmInfo();
      if (
        primaryAlgorithm.algorithm !== 'eddsaLegacy' ||
        primaryAlgorithm.curve !== 'ed25519Legacy' ||
        encryptionAlgorithm.algorithm !== 'ecdh' ||
        encryptionAlgorithm.curve !== 'curve25519Legacy'
      ) {
        throw new Error('unsupported key layout');
      }
      const messageText = `opshub-pgp-roundtrip-${randomBytes(8).toString('hex')}`;
      const encrypted = await encrypt({
        message: await createMessage({ text: messageText }),
        encryptionKeys: publicKey,
        format: 'armored',
      });
      const message = await readMessage({ armoredMessage: encrypted });
      const decrypted = await decrypt({
        message,
        decryptionKeys: privateKey,
        format: 'utf8',
      });
      if (decrypted.data !== messageText)
        throw new Error('round-trip mismatch');
      return {
        fingerprint: publicKey.getFingerprint().toUpperCase(),
        algorithm: 'Ed25519+X25519',
        publicKeyArmor: publicKey.armor(),
        privateKeyArmor: privateKey.armor(),
      };
    } catch {
      throw new BadRequestException(
        'Cặp khóa OpenPGP không hợp lệ hoặc không hỗ trợ mã hóa X25519.',
      );
    }
  }

  private requiredKek() {
    const kek = getBidvH2hConfig().kek;
    if (!kek) {
      throw new ServiceUnavailableException(
        'Chưa cấu hình khóa bảo vệ riêng cho kết nối ngân hàng.',
      );
    }
    return kek;
  }
}
