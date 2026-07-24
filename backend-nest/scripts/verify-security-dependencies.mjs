import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const lock = JSON.parse(
  fs.readFileSync(new URL('../package-lock.json', import.meta.url), 'utf8'),
);

const packageVersions = (name) =>
  Object.entries(lock.packages)
    .filter(([packagePath]) => packagePath.endsWith(`node_modules/${name}`))
    .map(([, metadata]) => metadata.version)
    .filter(Boolean);

const assertFloor = (name, floor, { required = true } = {}) => {
  const versions = packageVersions(name);
  if (required && versions.length === 0) {
    throw new Error(`${name} is missing from package-lock.json`);
  }
  for (const version of versions) {
    if (compareVersions(version, floor) < 0) {
      throw new Error(`${name}@${version} is below security floor ${floor}`);
    }
  }
  return versions;
};

const fastUriVersions = assertFloor('fast-uri', '3.1.4');
const sharpVersions = assertFloor('sharp', '0.35.0');
const honoNodeServerVersions = assertFloor('@hono/node-server', '2.0.5', {
  required: false,
});
const findMyWayVersions = assertFloor('find-my-way', '9.7.0', {
  required: false,
});

const fastUri = require('fast-uri');
const idnInput = 'http://127。0。0。1/';
const parsedIdn = fastUri.parse(idnInput);
if (parsedIdn.error || parsedIdn.host !== new URL(idnInput).hostname) {
  throw new Error(
    `fast-uri IDN canonicalization mismatch: ${JSON.stringify(parsedIdn)}`,
  );
}

const backslashInput = 'http://evil.com\\@allowed.com';
const parsedBackslash = fastUri.parse(backslashInput);
if (!parsedBackslash.error) {
  throw new Error('fast-uri accepted a literal backslash authority delimiter');
}

if (findMyWayVersions.length > 0) {
  const router = require('find-my-way')();
  router.on('GET', '/health', () => undefined);
  if (!router.find('GET', '/health')) {
    throw new Error('find-my-way legitimate route lookup failed');
  }
  if (router.find('constructor', '/') !== null) {
    throw new Error(
      'find-my-way inherited HTTP method lookup was not rejected',
    );
  }
}

const sharp = require('sharp');
if (compareVersions(sharp.versions.sharp, '0.35.0') < 0) {
  throw new Error(`loaded sharp ${sharp.versions.sharp} is vulnerable`);
}
if (compareVersions(sharp.versions.vips, '8.18.3') < 0) {
  throw new Error(`loaded libvips ${sharp.versions.vips} is vulnerable`);
}

const png = await sharp({
  create: {
    width: 2,
    height: 2,
    channels: 3,
    background: '#1238c8',
  },
})
  .png()
  .toBuffer();
const metadata = await sharp(png).metadata();
if (
  metadata.format !== 'png' ||
  metadata.width !== 2 ||
  metadata.height !== 2
) {
  throw new Error(`sharp PNG control failed: ${JSON.stringify(metadata)}`);
}

console.log(
  JSON.stringify({
    fastUriVersions,
    sharpVersions,
    honoNodeServerVersions,
    findMyWayVersions,
    fastUriIdnCanonicalization: 'ok',
    fastUriBackslashRejection: 'ok',
    findMyWayInheritedMethodRejection:
      findMyWayVersions.length > 0 ? 'ok' : 'not-installed',
    loadedSharp: sharp.versions.sharp,
    loadedLibvips: sharp.versions.vips,
    sharpPngControl: 'ok',
  }),
);

function compareVersions(left, right) {
  const normalize = (value) =>
    value
      .split(/[.+-]/, 3)
      .map((part) => Number.parseInt(part, 10))
      .map((part) => (Number.isNaN(part) ? 0 : part));
  const leftParts = normalize(left);
  const rightParts = normalize(right);
  for (let index = 0; index < 3; index += 1) {
    const difference = (leftParts[index] ?? 0) - (rightParts[index] ?? 0);
    if (difference !== 0) return Math.sign(difference);
  }
  return 0;
}
