import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'crypto';

function getSecretKey() {
  return createHash('sha256')
    .update(
      process.env.MAP_VIETIN_CREDENTIAL_SECRET ||
        process.env.JWT_SECRET ||
        'development-map-vietin-secret',
    )
    .digest();
}

export function encryptSecret(value: string) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', getSecretKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(value, 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [
    'v1',
    iv.toString('base64'),
    tag.toString('base64'),
    encrypted.toString('base64'),
  ].join(':');
}

export function decryptSecret(cipherText: string) {
  const [version, ivValue, tagValue, encryptedValue] = cipherText.split(':');
  if (version !== 'v1' || !ivValue || !tagValue || !encryptedValue) {
    throw new Error('Unsupported secret cipher format');
  }

  const decipher = createDecipheriv(
    'aes-256-gcm',
    getSecretKey(),
    Buffer.from(ivValue, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(tagValue, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedValue, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}
