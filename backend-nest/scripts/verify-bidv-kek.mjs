import { createDecipheriv } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createPrismaClient } from './prisma-local.mjs';

const secretPath = process.env.BIDV_H2H_KEK_FILE || '/run/secrets/bidv-h2h-kek';
const encoded = readFileSync(secretPath, 'utf8').trim();
const key = Buffer.from(encoded, 'base64');
if (key.length !== 32 || key.toString('base64') !== encoded) {
  throw new Error('BIDV KEK file is not a canonical 32-byte Base64 key.');
}

function decryptEnvelope(value) {
  const envelope = JSON.parse(Buffer.from(value, 'base64').toString('utf8'));
  if (envelope.v !== 1 || envelope.alg !== 'A256GCM') {
    throw new Error('Unsupported BIDV key envelope.');
  }
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(envelope.iv, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
    decipher.final(),
  ]);
}

const { prisma, close } = createPrismaClient();
try {
  const protectedKeys = await prisma.bankPgpKey.findMany({
    where: { bankCode: 'BIDV' },
    select: { privateKeyCipher: true },
  });
  for (const protectedKey of protectedKeys)
    decryptEnvelope(protectedKey.privateKeyCipher);
  console.log(
    `BIDV KEK preflight passed protectedKeyCount=${protectedKeys.length}`,
  );
} catch {
  console.error('BIDV KEK does not match protected data; deployment stopped.');
  process.exitCode = 1;
} finally {
  key.fill(0);
  await close();
}
