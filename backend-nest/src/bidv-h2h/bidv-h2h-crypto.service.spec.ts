import { createMessage, encrypt, enums, generateKey, readKey } from 'openpgp';
import { BidvH2hCryptoService } from './bidv-h2h-crypto.service';

describe('BidvH2hCryptoService', () => {
  const originalEnv = process.env;
  const service = new BidvH2hCryptoService();

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      BIDV_H2H_KEK_BASE64: Buffer.alloc(32, 7).toString('base64'),
      BIDV_H2H_MAX_ENCODED_BODY_BYTES: '1048576',
    };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('generates the documented key layout and decrypts Base64 armor', async () => {
    const pair = await service.generateKeyPair('UAT generated fixture');
    expect(pair.algorithm).toBe('Ed25519+X25519');
    expect(pair.fingerprint).toMatch(/^[A-F0-9]+$/);
    const encryptedPrivate = service.encryptPrivateKey(pair.privateKeyArmor);
    expect(encryptedPrivate).not.toContain('PRIVATE KEY');
    const publicKey = await readKey({ armoredKey: pair.publicKeyArmor });
    const plaintext = JSON.stringify([{ refNo: 'generated-fixture' }]);
    const armor = await encrypt({
      message: await createMessage({ text: plaintext }),
      encryptionKeys: publicKey,
      format: 'armored',
    });
    await expect(
      service.decryptPayload(
        Buffer.from(armor, 'utf8').toString('base64'),
        encryptedPrivate,
      ),
    ).resolves.toBe(plaintext);
  }, 30_000);

  it('fails closed without the dedicated KEK and never uses JWT_SECRET', () => {
    process.env = { ...originalEnv, JWT_SECRET: 'must-not-be-used' };
    expect(() => service.encryptPrivateKey('private')).toThrow(
      'khóa bảo vệ riêng',
    );
  });

  it('rejects altered envelope ciphertext', () => {
    const encrypted = service.encryptPrivateKey('private material');
    const envelope = JSON.parse(Buffer.from(encrypted, 'base64').toString());
    envelope.ciphertext = Buffer.from('altered').toString('base64');
    expect(() =>
      service.decryptPrivateKey(
        Buffer.from(JSON.stringify(envelope)).toString('base64'),
      ),
    ).toThrow('Không mở được');
  });

  it('rejects imported keys outside the documented Ed25519/X25519 layout', async () => {
    const rsa = await generateKey({
      type: 'rsa',
      rsaBits: 2048,
      userIDs: [{ name: 'Unsupported RSA fixture' }],
      format: 'armored',
    });

    await expect(
      service.validateImportedKeyPair(rsa.publicKey, rsa.privateKey),
    ).rejects.toThrow('không hợp lệ');
  }, 30_000);

  it('rejects a compressed message whose plaintext exceeds the configured limit', async () => {
    const pair = await service.generateKeyPair('Compressed payload fixture');
    const publicKey = await readKey({ armoredKey: pair.publicKeyArmor });
    const armor = await encrypt({
      message: await createMessage({ text: 'x'.repeat(1_100_000) }),
      encryptionKeys: publicKey,
      format: 'armored',
      config: { preferredCompressionAlgorithm: enums.compression.zlib },
    });
    const encryptedPrivate = service.encryptPrivateKey(pair.privateKeyArmor);

    await expect(
      service.decryptPayload(
        Buffer.from(armor, 'utf8').toString('base64'),
        encryptedPrivate,
      ),
    ).rejects.toThrow('Không giải mã được');
  }, 30_000);
});
