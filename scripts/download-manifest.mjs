import { mkdirSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname } from 'node:path';

const mode = process.argv[2];

if (mode === 'from-artifacts') {
  await writeFromArtifacts();
} else if (mode === 'from-live') {
  await writeFromLive();
} else {
  fail('Usage: node scripts/download-manifest.mjs <from-artifacts|from-live>');
}

async function writeFromArtifacts() {
  const publicBaseUrl = normalizeBaseUrl(requireEnv('OPSHUB_PUBLIC_BASE_URL'));
  const outputPath = requireEnv('DOWNLOAD_MANIFEST_OUTPUT');
  const version = requireEnv('APP_VERSION');
  const build = readPositiveInt(requireEnv('APP_BUILD_NUMBER'), 'APP_BUILD_NUMBER');

  const manifest = {
    schemaVersion: 1,
    version,
    build,
    releaseNotes: envString('APP_RELEASE_NOTES'),
    commit: envString('GITHUB_SHA'),
    publishedAt: new Date().toISOString(),
    files: {
      apk: artifactFile({
        publicBaseUrl,
        fileName: requireEnv('APK_FILE_NAME'),
        filePath: requireEnv('APK_FILE_PATH'),
      }),
      windowsInstaller: artifactFile({
        publicBaseUrl,
        fileName: requireEnv('WINDOWS_INSTALLER_FILE_NAME'),
        filePath: requireEnv('WINDOWS_INSTALLER_FILE_PATH'),
      }),
      windowsZip: artifactFile({
        publicBaseUrl,
        fileName: requireEnv('WINDOWS_ZIP_FILE_NAME'),
        filePath: requireEnv('WINDOWS_ZIP_FILE_PATH'),
      }),
      windowsChecksum: artifactFile({
        publicBaseUrl,
        fileName: requireEnv('WINDOWS_CHECKSUM_FILE_NAME'),
        filePath: requireEnv('WINDOWS_CHECKSUM_FILE_PATH'),
      }),
    },
  };

  writeManifest(outputPath, manifest);
}

async function writeFromLive() {
  const publicBaseUrl = normalizeBaseUrl(requireEnv('OPSHUB_PUBLIC_BASE_URL'));
  const apiBaseUrl = normalizeBaseUrl(requireEnv('OPSHUB_API_BASE_URL'));
  const outputPath = requireEnv('DOWNLOAD_MANIFEST_OUTPUT');

  const [android, windows] = await Promise.all([
    fetchJson(`${apiBaseUrl}/app-version?platform=android`),
    fetchJson(`${apiBaseUrl}/app-version?platform=windows`),
  ]);

  const version = String(android.latestVersion || windows.latestVersion || '').trim();
  const build = Number(android.latestBuild || windows.latestBuild || 0);
  if (!version || !Number.isInteger(build) || build <= 0) {
    fail('Live app-version metadata did not include a valid version/build.');
  }

  const apkUrl = readUrl(android.updateUrl, 'android.updateUrl');
  const installerUrl = readUrl(windows.updateUrl, 'windows.updateUrl');
  const windowsZipName = `phongvu-opshub-windows-v${version}+${build}.zip`;
  const windowsChecksumName = `phongvu-opshub-windows-v${version}+${build}.sha256`;
  const windowsZipUrl = `${publicBaseUrl}/downloads/${windowsZipName}`;
  const windowsChecksumUrl = `${publicBaseUrl}/downloads/${windowsChecksumName}`;

  const [apkHead, installerHead, zipHead, checksumHead, existingManifest] =
    await Promise.all([
      headFile(apkUrl, 'APK'),
      headFile(installerUrl, 'Windows installer'),
      headFile(windowsZipUrl, 'Windows ZIP'),
      headFile(windowsChecksumUrl, 'Windows checksum'),
      fetchOptionalJson(`${publicBaseUrl}/downloads/latest.json`),
    ]);

  const existingMatches =
    existingManifest?.version === version && existingManifest?.build === build;
  const publishedAt =
    (existingMatches && existingManifest.publishedAt) ||
    latestLastModified(apkHead, installerHead, zipHead, checksumHead) ||
    new Date().toISOString();

  const releaseNotes = String(android.releaseNotes || windows.releaseNotes || '').trim();
  const commit =
    (existingMatches && existingManifest.commit) || extractGitHubCommit(releaseNotes);

  const manifest = {
    schemaVersion: 1,
    version,
    build,
    releaseNotes,
    commit,
    publishedAt,
    files: {
      apk: liveFile(apkUrl, apkHead),
      windowsInstaller: liveFile(installerUrl, installerHead),
      windowsZip: liveFile(windowsZipUrl, zipHead),
      windowsChecksum: liveFile(windowsChecksumUrl, checksumHead),
    },
  };

  writeManifest(outputPath, manifest);
}

function artifactFile({ publicBaseUrl, fileName, filePath }) {
  const sizeBytes = statSync(filePath).size;
  return {
    fileName,
    url: `${publicBaseUrl}/downloads/${fileName}`,
    sizeBytes,
  };
}

function liveFile(url, head) {
  return {
    fileName: basename(new URL(url).pathname),
    url,
    sizeBytes: head.sizeBytes,
  };
}

async function fetchJson(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) {
    fail(`GET ${url} failed with HTTP ${response.status}.`);
  }
  return response.json();
}

async function fetchOptionalJson(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) return null;
  return response.json();
}

async function headFile(url, label) {
  const response = await fetch(url, { method: 'HEAD', cache: 'no-store' });
  if (!response.ok) {
    fail(`${label} is not reachable: ${url} returned HTTP ${response.status}.`);
  }
  const contentLength = response.headers.get('content-length');
  const sizeBytes = Number(contentLength);
  if (!Number.isInteger(sizeBytes) || sizeBytes <= 0) {
    fail(`${label} did not return a valid Content-Length: ${url}.`);
  }
  const lastModified = response.headers.get('last-modified');
  return {
    sizeBytes,
    lastModified: lastModified ? new Date(lastModified).toISOString() : '',
  };
}

function latestLastModified(...heads) {
  const timestamps = heads
    .map((head) => Date.parse(head.lastModified))
    .filter((value) => Number.isFinite(value));
  if (timestamps.length === 0) return '';
  return new Date(Math.max(...timestamps)).toISOString();
}

function extractGitHubCommit(releaseNotes) {
  const match = /GitHub\s+([0-9a-f]{7,40})/i.exec(releaseNotes);
  return match?.[1] ?? '';
}

function readUrl(value, label) {
  const text = String(value || '').trim();
  if (!text) fail(`${label} is empty.`);
  try {
    return new URL(text).toString();
  } catch {
    fail(`${label} is not a valid URL: ${text}`);
  }
}

function writeManifest(outputPath, manifest) {
  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  console.log(`Wrote download manifest: ${outputPath}`);
}

function normalizeBaseUrl(value) {
  return value.replace(/\/+$/, '');
}

function envString(name) {
  return process.env[name]?.trim() ?? '';
}

function requireEnv(name) {
  const value = envString(name);
  if (!value) fail(`${name} is required.`);
  return value;
}

function readPositiveInt(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    fail(`${label} must be a positive integer.`);
  }
  return parsed;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
