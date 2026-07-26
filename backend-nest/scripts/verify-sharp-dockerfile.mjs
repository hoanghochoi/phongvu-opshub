import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const dockerfile = (
  await readFile(new URL('../Dockerfile', import.meta.url), 'utf8')
).replace(/\r\n?/g, '\n');

const required = [
  'SHARP_ARCH="$(node -p "process.arch")"',
  'case "$SHARP_ARCH" in x64|arm64)',
  'sharp-linuxmusl-${SHARP_ARCH}-${SHARP_VERSION}.node',
  '@img/sharp-libvips-linuxmusl-${SHARP_ARCH}/lib',
  '@img/sharp-libvips-linuxmusl-x64/lib:/app/node_modules/@img/sharp-libvips-linuxmusl-arm64/lib',
];

for (const marker of required) {
  assert.ok(dockerfile.includes(marker), `Dockerfile is missing: ${marker}`);
}

assert.ok(
  dockerfile.match(/sharp-linuxmusl-\$\{SHARP_ARCH\}-\$\{SHARP_VERSION\}\.node/g)
    ?.length >= 2,
  'Dockerfile must verify the architecture-specific Sharp addon before and after pruning',
);
assert.ok(
  !dockerfile.includes('sharp-linuxmusl-x64-${SHARP_VERSION}.node'),
  'Dockerfile still hard-codes the x64 Sharp addon',
);

console.log('Sharp Dockerfile architecture contract verified: x64+arm64');
