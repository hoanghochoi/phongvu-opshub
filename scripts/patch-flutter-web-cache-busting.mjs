import fs from 'node:fs';

const token = encodeURIComponent(
  process.env.WEB_CACHE_BUST_TOKEN ?? process.argv[2] ?? '',
);

if (!token) {
  throw new Error('WEB_CACHE_BUST_TOKEN is required.');
}

const indexPath = 'build/web/index.html';
const bootstrapPath = 'build/web/flutter_bootstrap.js';

function patchFile(filePath, patcher) {
  let before;
  try {
    before = fs.readFileSync(filePath, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') {
      throw new Error(`Missing Flutter web build file: ${filePath}`);
    }
    throw error;
  }
  const after = patcher(before);
  if (after === before) {
    throw new Error(`No cache-busting replacement made in ${filePath}`);
  }
  fs.writeFileSync(filePath, after);
}

patchFile(indexPath, (content) =>
  content.replace(
    /src=(["'])flutter_bootstrap\.js(?:\?[^"']*)?\1/,
    `src="flutter_bootstrap.js?v=${token}"`,
  ),
);

patchFile(bootstrapPath, (content) =>
  content.replace(
    /"mainJsPath":"main\.dart\.js(?:\?[^"]*)?"/,
    `"mainJsPath":"main.dart.js?v=${token}"`,
  ),
);

console.log(`Patched Flutter web cache-busting token: ${token}`);
