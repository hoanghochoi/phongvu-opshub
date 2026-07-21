import fs from 'node:fs';

const token = encodeURIComponent(
  process.env.WEB_CACHE_BUST_TOKEN ?? process.argv[2] ?? '',
);

if (!token) {
  throw new Error('WEB_CACHE_BUST_TOKEN is required.');
}

const sourceBootstrapPath = 'web/flutter_bootstrap.js';
const builtBootstrapPath = 'build/web/flutter_bootstrap.js';
const builtIndexPath = 'build/web/index.html';
const fullCanvasKitPath = 'build/web/canvaskit/canvaskit.wasm';
const fullCanvasKitVariantPattern = /canvasKitVariant\s*:\s*(['"])full\1/;

function readRequiredFile(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') {
      throw new Error(`Missing Flutter web file: ${filePath}`);
    }
    throw error;
  }
}

function requireMatch(content, pattern, message) {
  if (!pattern.test(content)) {
    throw new Error(message);
  }
}

function requireText(content, expected, message) {
  if (!content.includes(expected)) {
    throw new Error(message);
  }
}

const sourceBootstrap = readRequiredFile(sourceBootstrapPath);
for (const tokenName of [
  '{{flutter_js}}',
  '{{flutter_build_config}}',
  '{{flutter_service_worker_version}}',
]) {
  if (!sourceBootstrap.includes(tokenName)) {
    throw new Error(`Missing Flutter bootstrap template token: ${tokenName}`);
  }
}
requireMatch(
  sourceBootstrap,
  fullCanvasKitVariantPattern,
  'Source bootstrap must configure canvasKitVariant: full.',
);

const builtBootstrap = readRequiredFile(builtBootstrapPath);
requireMatch(
  builtBootstrap,
  fullCanvasKitVariantPattern,
  'Built bootstrap must configure canvasKitVariant: full.',
);
requireText(
  builtBootstrap,
  `"mainJsPath":"main.dart.js?v=${token}"`,
  'Built bootstrap is missing the expected main.dart.js cache-busting token.',
);
if (builtBootstrap.includes('{{flutter_')) {
  throw new Error('Built bootstrap still contains unresolved Flutter tokens.');
}

const builtIndex = readRequiredFile(builtIndexPath);
requireText(
  builtIndex,
  `src="flutter_bootstrap.js?v=${token}"`,
  'Built index is missing the expected bootstrap cache-busting token.',
);

let canvasKitStats;
try {
  canvasKitStats = fs.statSync(fullCanvasKitPath);
} catch (error) {
  if (error?.code === 'ENOENT') {
    throw new Error(`Missing full CanvasKit artifact: ${fullCanvasKitPath}`);
  }
  throw error;
}
if (!canvasKitStats.isFile() || canvasKitStats.size === 0) {
  throw new Error(`Invalid full CanvasKit artifact: ${fullCanvasKitPath}`);
}

console.log(
  `Flutter web bootstrap verification: PASS (full CanvasKit ${canvasKitStats.size} bytes, token ${token})`,
);
