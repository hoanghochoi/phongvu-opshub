import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import zlib from 'node:zlib';

// Usage:
//   $env:OPSHUB_SMOKE_EMAIL='admin@example.com'
//   $env:OPSHUB_SMOKE_PASSWORD='...'
//   node scripts/opshub-web-visual-smoke.mjs
// Screenshots and summary are written under output/ (ignored by git).

const require = createRequire(import.meta.url);
const workspace = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputDir = path.resolve(
  workspace,
  process.env.OPSHUB_VISUAL_SMOKE_OUTPUT || 'output/playwright/opshub-visual-smoke',
);
const baseUrl = normalizeBaseUrl(
  process.env.OPSHUB_VISUAL_SMOKE_URL || 'https://opshub-staging.hoanghochoi.com',
);
const apiBaseUrl = normalizeBaseUrl(
  process.env.OPSHUB_VISUAL_SMOKE_API_URL || `${baseUrl}/api`,
);
const storageEnvironment =
  process.env.OPSHUB_VISUAL_SMOKE_STORAGE_ENV || environmentForBaseUrl(apiBaseUrl);
const email = process.env.OPSHUB_SMOKE_EMAIL;
const password = process.env.OPSHUB_SMOKE_PASSWORD;
const warrantyDetailReceipt = process.env.OPSHUB_VISUAL_SMOKE_WARRANTY_RECEIPT
  ?.toString()
  .trim();
const headless = process.env.OPSHUB_VISUAL_SMOKE_HEADLESS !== 'false';
const preferredBrowserChannel = process.env.OPSHUB_VISUAL_SMOKE_BROWSER_CHANNEL;
const waitMs = Number(process.env.OPSHUB_VISUAL_SMOKE_WAIT_MS || 1200);
const viewports = parseViewports(
  process.env.OPSHUB_VISUAL_SMOKE_VIEWPORTS || 'desktop=1440x900,mobile=390x844',
);
const publicRoutes = parseRoutes(
  process.env.OPSHUB_VISUAL_SMOKE_PUBLIC_ROUTES ||
    ['/login', '/register', '/forgot-password'].join(','),
);
const pendingRoutes = parseRoutes(
  process.env.OPSHUB_VISUAL_SMOKE_PENDING_ROUTES ||
    ['/assignment-pending'].join(','),
);
const defaultAuthenticatedRoutes = parseRoutes(
  process.env.OPSHUB_VISUAL_SMOKE_ROUTES ||
    [
      '/help',
      '/home',
      '/profile',
      '/operations',
      '/notifications',
      '/admin',
      '/admin/users',
      '/admin/roles',
      '/admin/organization',
      '/admin/policies',
      '/admin/features',
      '/admin/personnel',
      '/admin/inventory-import',
      '/admin/feedback',
      '/admin/help-content',
      '/admin/sales-reports',
      '/fifo-menu',
      '/fifo-check',
      '/fifo-history',
      '/fifo/inventory-import',
      '/sort',
      '/warranty-main',
      '/warranty',
      '/check-warranty',
      '/check-warranty/details/:receiptNumber',
      '/vietqr',
      '/payment-monitor',
      '/bank-statement',
      '/offset-adjustments',
      '/feedback',
      '/reports',
      '/sales-reports',
      '/sales-reports/purchased',
      '/sales-reports/not-purchased',
      '/settings',
    ].join(','),
);

if (!email || !password) {
  fail(
    'Missing OPSHUB_SMOKE_EMAIL or OPSHUB_SMOKE_PASSWORD. ' +
      'Run with env vars; do not commit credentials.',
  );
}

const { chromium } = await loadPlaywright();

fs.mkdirSync(outputDir, { recursive: true });

const session = await loginViaApi();
const authenticatedRouteResolution = await resolveAuthenticatedRoutes(
  session,
  defaultAuthenticatedRoutes,
);
const authenticatedRoutes = authenticatedRouteResolution.routes;
const browser = await launchBrowser(chromium);
const startedAt = new Date();
const summary = {
  baseUrl,
  apiBaseUrl,
  storageEnvironment,
  startedAt: startedAt.toISOString(),
  routeCount:
    publicRoutes.length + pendingRoutes.length + authenticatedRoutes.length,
  publicRouteCount: publicRoutes.length,
  pendingRouteCount: pendingRoutes.length,
  authenticatedRouteCount: authenticatedRoutes.length,
  viewportCount: viewports.length,
  publicRoutes,
  pendingRoutes,
  authenticatedRoutes,
  requestedAuthenticatedRoutes: defaultAuthenticatedRoutes,
  dynamicRoutes: authenticatedRouteResolution.dynamicRoutes,
  skippedRoutes: authenticatedRouteResolution.skippedRoutes,
  viewports,
  results: [],
  failures: [],
};

try {
  for (const viewport of viewports) {
    await runViewportRoutes({
      viewport,
      phase: 'public',
      routes: publicRoutes,
    });

    await runViewportRoutes({
      viewport,
      phase: 'pending',
      routes: pendingRoutes,
      pendingSession: {
        email: 'codex.pending.assignment@example.test',
        name: 'Tài khoản chờ gán',
      },
    });

    await runViewportRoutes({
      viewport,
      phase: 'auth',
      routes: authenticatedRoutes,
      session,
      initialRoute: '/home',
    });
  }
} finally {
  await browser.close();
}

summary.completedAt = new Date().toISOString();
summary.ok = summary.failures.length === 0;
const summaryPath = path.join(outputDir, 'summary.json');
fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');

process.stdout.write(
  JSON.stringify(
    {
      ok: summary.ok,
      checked: summary.results.length,
      publicRoutes: summary.publicRouteCount,
      pendingRoutes: summary.pendingRouteCount,
      authenticatedRoutes: summary.authenticatedRouteCount,
      skippedRoutes: summary.skippedRoutes,
      dynamicRoutes: summary.dynamicRoutes,
      failures: summary.failures.map(({ phase, viewport, route, reason }) => ({
        phase,
        viewport,
        route,
        reason,
      })),
      summary: path.relative(workspace, summaryPath).replaceAll(path.sep, '/'),
    },
    null,
    2,
  ) + '\n',
);

if (!summary.ok) process.exit(1);

async function runViewportRoutes({
  viewport,
  phase,
  routes,
  session,
  pendingSession,
  initialRoute,
}) {
  if (routes.length === 0) return;

  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
  });
  if (session) {
    await context.addInitScript(seedSessionStorage, {
      session,
      storageEnvironment,
    });
  }
  if (pendingSession) {
    await context.addInitScript(seedPendingAssignmentStorage, {
      pendingSession,
      storageEnvironment,
    });
  }

  try {
    const page = await context.newPage();
    const runtimeErrors = [];
    page.on('console', (message) => {
      if (message.type() === 'error') {
        runtimeErrors.push(sanitizeSensitiveText(`console: ${message.text()}`));
      }
    });
    page.on('pageerror', (error) => {
      runtimeErrors.push(sanitizeSensitiveText(`pageerror: ${error.message}`));
    });

    if (initialRoute) {
      await settleRoute(page, initialRoute);
    }

    for (const route of routes) {
      const errorsBefore = runtimeErrors.length;
      await settleRoute(page, route);

      const metrics = await page.evaluate(() => {
        const flutterView = document.querySelector('flutter-view');
        const body = document.body;
        const root = document.documentElement;
        return {
          hash: window.location.hash,
          href: window.location.href,
          title: document.title,
          innerWidth: window.innerWidth,
          innerHeight: window.innerHeight,
          bodyScrollWidth: body?.scrollWidth ?? 0,
          bodyClientWidth: body?.clientWidth ?? 0,
          rootScrollWidth: root?.scrollWidth ?? 0,
          flutterViewWidth: Math.round(flutterView?.getBoundingClientRect().width ?? 0),
          flutterViewHeight: Math.round(flutterView?.getBoundingClientRect().height ?? 0),
          ...(() => {
            const candidates = [...document.querySelectorAll('body *')]
              .map((element) => {
              const rect = element.getBoundingClientRect();
              return {
                tag: element.tagName.toLowerCase(),
                id: element.id || '',
                className:
                  typeof element.className === 'string' ? element.className.slice(0, 80) : '',
                left: Math.round(rect.left),
                right: Math.round(rect.right),
                width: Math.round(rect.width),
                height: Math.round(rect.height),
              };
            })
            .filter((item) => item.right > window.innerWidth + 2 || item.left < -2)
              .sort(
                (a, b) =>
                  Math.abs(b.right - window.innerWidth) -
                  Math.abs(a.right - window.innerWidth),
              );
            const isFlutterSemanticNoise = (item) =>
              item.tag.startsWith('flt-announcement') ||
              (item.tag === 'p' && item.width > window.innerWidth * 10 && item.height >= 9000);
            return {
              overflowElements: candidates.filter((item) => !isFlutterSemanticNoise(item)).slice(0, 8),
              ignoredOverflowElements: candidates.filter(isFlutterSemanticNoise).slice(0, 8),
            };
          })(),
          textSample: (body?.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 220),
        };
      });
      const actualRoute = metrics.hash.replace(/^#/, '') || '/';
      const screenshotName = `${phase}-${viewport.name}-${slugRoute(route)}.png`;
      const screenshotPath = path.join(outputDir, screenshotName);
      await page.screenshot({ path: screenshotPath, fullPage: false });
      const screenshotBytes = fs.statSync(screenshotPath).size;
      const screenshotStats = readPngVisualStats(screenshotPath);
      const routeErrors = runtimeErrors.slice(errorsBefore);
      const horizontalOverflow =
        metrics.rootScrollWidth > metrics.innerWidth + 2 ||
        metrics.flutterViewWidth > metrics.innerWidth + 2 ||
        metrics.overflowElements.length > 0;
      const result = {
        phase,
        viewport: viewport.name,
        route,
        actualRoute,
        ok: true,
        screenshot: path.relative(workspace, screenshotPath).replaceAll(path.sep, '/'),
        screenshotBytes,
        screenshotStats,
        metrics,
        errors: routeErrors,
      };

      if (actualRoute !== route) {
        result.ok = false;
        result.reason = `Expected hash ${route}, got ${actualRoute}`;
      } else if (routeErrors.length > 0) {
        result.ok = false;
        result.reason = routeErrors.join('; ');
      } else if (horizontalOverflow) {
        result.ok = false;
        result.reason = `Horizontal overflow: body/root scroll width ${Math.max(
          metrics.bodyScrollWidth,
          metrics.rootScrollWidth,
        )} > viewport ${metrics.innerWidth}`;
      } else if (metrics.flutterViewWidth <= 0 || metrics.flutterViewHeight <= 0) {
        result.ok = false;
        result.reason = 'Flutter view did not render a measurable viewport.';
      } else if (screenshotBytes < 20000) {
        result.ok = false;
        result.reason = `Screenshot too small: ${screenshotBytes} bytes.`;
      } else if (
        screenshotStats.width !== viewport.width ||
        screenshotStats.height !== viewport.height
      ) {
        result.ok = false;
        result.reason =
          `Screenshot dimensions ${screenshotStats.width}x${screenshotStats.height} ` +
          `do not match viewport ${viewport.width}x${viewport.height}.`;
      } else if (
        screenshotStats.uniqueSampledColors < 16 ||
        screenshotStats.lumaRange < 12
      ) {
        result.ok = false;
        result.reason =
          `Screenshot appears visually flat: ${screenshotStats.uniqueSampledColors} colors, ` +
          `luma range ${screenshotStats.lumaRange}.`;
      }

      if (!result.ok) summary.failures.push(result);
      summary.results.push(result);
    }
  } finally {
    await context.close();
  }
}

async function settleRoute(page, route) {
  await page.goto(`${baseUrl}/#${route}`, { waitUntil: 'domcontentloaded', timeout: 45000 });
  await waitForFlutter(page);
  await waitForNetworkQuiet(page);
  await dismissOptionalUpdate(page);
  await page.waitForTimeout(waitMs);
}

async function dismissOptionalUpdate(page) {
  const skipButton = page.getByText('Để sau', { exact: true });
  try {
    if (await skipButton.isVisible({ timeout: 1500 })) {
      await skipButton.click();
    }
  } catch {
    // No optional update dialog is present.
  }
}

async function waitForFlutter(page) {
  await page.waitForSelector('flutter-view', { timeout: 45000 });
  await page.waitForFunction(
    () => {
      const view = document.querySelector('flutter-view');
      const rect = view?.getBoundingClientRect();
      return Boolean(rect && rect.width > 0 && rect.height > 0);
    },
    null,
    { timeout: 45000 },
  );
}

async function waitForNetworkQuiet(page) {
  try {
    await page.waitForLoadState('networkidle', { timeout: 10000 });
  } catch {
    // WebSocket-enabled routes may never become fully idle; visual checks still
    // wait for Flutter plus the configured settle delay.
  }
}

function parseRoutes(value) {
  return value
    .split(',')
    .map((route) => route.trim())
    .filter(Boolean)
    .map((route) => (route.startsWith('/') ? route : `/${route}`));
}

function parseViewports(value) {
  return value
    .split(',')
    .map((entry) => {
      const [name, size] = entry.split('=').map((part) => part.trim());
      const [width, height] = (size || '').split('x').map(Number);
      if (!name || !Number.isFinite(width) || !Number.isFinite(height)) {
        fail(`Invalid viewport entry "${entry}". Use name=WIDTHxHEIGHT.`);
      }
      return { name, width, height };
    });
}

function readPngVisualStats(filePath) {
  const buffer = fs.readFileSync(filePath);
  const signature = buffer.subarray(0, 8).toString('hex');
  if (signature !== '89504e470d0a1a0a') {
    fail(`Screenshot is not a PNG: ${filePath}`);
  }

  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const idatChunks = [];

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.subarray(offset + 4, offset + 8).toString('ascii');
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    offset += 12 + length;

    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data.readUInt8(8);
      colorType = data.readUInt8(9);
    } else if (type === 'IDAT') {
      idatChunks.push(data);
    } else if (type === 'IEND') {
      break;
    }
  }

  if (bitDepth !== 8 || ![2, 6].includes(colorType)) {
    fail(
      `Unsupported PNG format for screenshot stats: bitDepth=${bitDepth}, ` +
        `colorType=${colorType}.`,
    );
  }

  const bytesPerPixel = colorType === 6 ? 4 : 3;
  const rowBytes = width * bytesPerPixel;
  const inflated = zlib.inflateSync(Buffer.concat(idatChunks));
  const pixels = Buffer.alloc(width * height * bytesPerPixel);
  const previous = Buffer.alloc(rowBytes);
  let sourceOffset = 0;
  let targetOffset = 0;

  for (let y = 0; y < height; y += 1) {
    const filter = inflated[sourceOffset];
    sourceOffset += 1;
    const row = Buffer.from(
      inflated.subarray(sourceOffset, sourceOffset + rowBytes),
    );
    sourceOffset += rowBytes;

    for (let x = 0; x < rowBytes; x += 1) {
      const left = x >= bytesPerPixel ? row[x - bytesPerPixel] : 0;
      const up = previous[x];
      const upLeft = x >= bytesPerPixel ? previous[x - bytesPerPixel] : 0;
      row[x] = (row[x] + pngFilterValue(filter, left, up, upLeft)) & 0xff;
    }

    row.copy(pixels, targetOffset);
    row.copy(previous);
    targetOffset += rowBytes;
  }

  const totalPixels = width * height;
  const step = Math.max(1, Math.floor(totalPixels / 20000));
  const colors = new Set();
  let minLuma = 255;
  let maxLuma = 0;
  let sampledPixels = 0;

  for (let pixel = 0; pixel < totalPixels; pixel += step) {
    const index = pixel * bytesPerPixel;
    const red = pixels[index];
    const green = pixels[index + 1];
    const blue = pixels[index + 2];
    const alpha = colorType === 6 ? pixels[index + 3] : 255;
    const luma = Math.round(red * 0.2126 + green * 0.7152 + blue * 0.0722);
    minLuma = Math.min(minLuma, luma);
    maxLuma = Math.max(maxLuma, luma);
    sampledPixels += 1;
    if (colors.size < 10000) colors.add(`${red},${green},${blue},${alpha}`);
  }

  return {
    width,
    height,
    sampledPixels,
    uniqueSampledColors: colors.size,
    lumaRange: maxLuma - minLuma,
  };
}

function pngFilterValue(filter, left, up, upLeft) {
  switch (filter) {
    case 0:
      return 0;
    case 1:
      return left;
    case 2:
      return up;
    case 3:
      return Math.floor((left + up) / 2);
    case 4:
      return pngPaeth(left, up, upLeft);
    default:
      fail(`Unsupported PNG filter: ${filter}.`);
  }
}

function pngPaeth(left, up, upLeft) {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upLeftDistance = Math.abs(estimate - upLeft);
  if (leftDistance <= upDistance && leftDistance <= upLeftDistance) return left;
  if (upDistance <= upLeftDistance) return up;
  return upLeft;
}

function normalizeBaseUrl(value) {
  return value.replace(/\/+$/, '');
}

function sanitizeSensitiveText(value) {
  return String(value)
    .replace(/([?&]access_token=)[^&\s'")]+/gi, '$1[REDACTED]')
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, '[REDACTED_JWT]')
    .replace(/(authorization:\s*bearer\s+)[A-Za-z0-9._-]+/gi, '$1[REDACTED]');
}

function environmentForBaseUrl(value) {
  const url = new URL(value);
  const host = url.host.toLowerCase();
  if (host.includes('opshub-staging') || url.pathname.toLowerCase().includes('staging')) {
    return 'staging';
  }
  if (host === 'opshub.hoanghochoi.com') return 'production';
  if (
    host.startsWith('localhost') ||
    host.startsWith('127.0.0.1') ||
    host.startsWith('192.168.') ||
    host.startsWith('10.') ||
    host.startsWith('172.')
  ) {
    return 'local';
  }
  return host.replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'local';
}

async function loginViaApi() {
  const response = await fetch(`${apiBaseUrl}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      email,
      password,
      platform: 'web',
      deviceId: 'codex-visual-smoke',
      deviceLabel: 'web visual smoke',
    }),
  });
  if (!response.ok) {
    fail(`API login failed with HTTP ${response.status}.`);
  }
  const data = await response.json();
  const token = data.access_token?.toString();
  if (!token) fail('API login did not return access_token.');
  return { token, user: data };
}

async function resolveAuthenticatedRoutes(session, routes) {
  const resolvedRoutes = [];
  const dynamicRoutes = [];
  const skippedRoutes = [];

  for (const route of routes) {
    if (route !== '/check-warranty/details/:receiptNumber') {
      resolvedRoutes.push(route);
      continue;
    }

    const warrantyDetail = await resolveWarrantyDetailRoute(session);
    if (warrantyDetail) {
      resolvedRoutes.push(warrantyDetail.route);
      dynamicRoutes.push({
        pattern: route,
        route: warrantyDetail.route,
        source: warrantyDetail.source,
      });
      continue;
    }

    skippedRoutes.push({
      route,
      reason: 'No readable warranty receipt returned by GET /warranties.',
    });
  }

  return { routes: resolvedRoutes, dynamicRoutes, skippedRoutes };
}

async function resolveWarrantyDetailRoute(session) {
  if (warrantyDetailReceipt) {
    return {
      route: `/check-warranty/details/${encodeURIComponent(warrantyDetailReceipt)}`,
      source: 'OPSHUB_VISUAL_SMOKE_WARRANTY_RECEIPT',
    };
  }

  const response = await fetch(`${apiBaseUrl}/warranties`, {
    headers: {
      authorization: `Bearer ${session.token}`,
      accept: 'application/json',
    },
  });
  if (!response.ok) {
    fail(`Dynamic warranty detail route failed to resolve: HTTP ${response.status}.`);
  }

  const data = await response.json();
  const rows = Array.isArray(data) ? data : data && typeof data === 'object' ? [data] : [];
  const receipt = rows
    .map((row) => row?.receipt?.toString().trim())
    .find((value) => value && value.length > 0);
  if (!receipt) return null;
  return {
    route: `/check-warranty/details/${encodeURIComponent(receipt)}`,
    source: 'GET /warranties',
  };
}

function seedSessionStorage({ session, storageEnvironment }) {
  const prefix = `flutter.opshub.${storageEnvironment}.`;
  const storagePrefix = `opshub.${storageEnvironment}.`;
  for (const key of Object.keys(localStorage)) {
    if (key.startsWith(prefix) || key.startsWith(storagePrefix)) {
      localStorage.removeItem(key);
    }
  }

  const user = session.user || {};
  const setPref = (key, value) => {
    if (value === undefined || value === null) return;
    localStorage.setItem(`${prefix}${key}`, JSON.stringify(value));
  };
  const setJsonStringPref = (key, value) => {
    if (value === undefined || value === null) return;
    setPref(key, JSON.stringify(value));
  };

  setPref('user_email', user.email);
  setPref('user_name', user.firstName || user.name);
  setPref('user_lastName', user.lastName);
  setPref('user_avatarUrl', user.avatarUrl);
  setPref('user_storeId', user.storeId);
  setPref('user_storeName', user.storeName);
  setPref('user_role', user.role);
  setPref('user_status', user.status);
  setPref('user_departmentCode', user.departmentCode);
  setPref('user_jobRoleCode', user.jobRoleCode);
  setPref('user_workScopeType', user.workScopeType);
  setPref('user_regionCode', user.regionCode);
  setPref('user_regionName', user.regionName);
  setPref('user_regionAbbreviation', user.regionAbbreviation);
  setPref('user_areaCode', user.areaCode);
  setPref('user_areaName', user.areaName);
  setPref('user_areaAbbreviation', user.areaAbbreviation);
  setPref('user_organizationNodeId', user.organizationNodeId);
  setPref('user_organizationNodeName', user.organizationNodeName);
  setJsonStringPref('user_organizationNodeIds', user.organizationNodeIds || []);
  setJsonStringPref('user_organizationAssignments', user.organizationAssignments || []);
  setJsonStringPref('user_assignedStores', user.assignedStores || []);
  setJsonStringPref('user_organizationAccessCodes', user.organizationAccessCodes || []);
  setJsonStringPref('user_featureCodes', user.featureCodes || []);
  setPref('user_personnelCode', user.personnelCode);
  setPref('user_assignmentPending', user.assignmentPending === true);
  setPref('user_jwt_token', session.token);
}

function seedPendingAssignmentStorage({ pendingSession, storageEnvironment }) {
  const prefix = `flutter.opshub.${storageEnvironment}.`;
  const storagePrefix = `opshub.${storageEnvironment}.`;
  for (const key of Object.keys(localStorage)) {
    if (key.startsWith(prefix) || key.startsWith(storagePrefix)) {
      localStorage.removeItem(key);
    }
  }

  const setPref = (key, value) => {
    if (value === undefined || value === null) return;
    localStorage.setItem(`${prefix}${key}`, JSON.stringify(value));
  };

  setPref('user_email', pendingSession.email);
  setPref('user_name', pendingSession.name);
  setPref('user_role', 'USER');
  setPref('user_status', 'ACTIVE');
  setPref('user_organizationNodeIds', JSON.stringify([]));
  setPref('user_organizationAssignments', JSON.stringify([]));
  setPref('user_assignedStores', JSON.stringify([]));
  setPref('user_organizationAccessCodes', JSON.stringify([]));
  setPref('user_featureCodes', JSON.stringify([]));
  setPref('user_assignmentPending', true);
}

function slugRoute(route) {
  return route.replace(/^\/+/, '').replace(/[^a-z0-9]+/gi, '-') || 'home';
}

function fail(message, error) {
  process.stderr.write(`${sanitizeSensitiveText(message)}\n`);
  if (error) {
    process.stderr.write(
      `${sanitizeSensitiveText(error.stack || error.message || error)}\n`,
    );
  }
  process.exit(1);
}

async function launchBrowser(browserType) {
  const channels = preferredBrowserChannel
    ? [preferredBrowserChannel]
    : [undefined, 'chrome', 'msedge'];
  const errors = [];
  for (const channel of channels) {
    try {
      return await browserType.launch({
        headless,
        ...(channel ? { channel } : {}),
      });
    } catch (error) {
      errors.push(`${channel || 'bundled chromium'}: ${error.message}`);
    }
  }
  fail('Unable to launch Playwright browser.', errors.join('\n'));
}

async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch (firstError) {
    try {
      return require('playwright');
    } catch {
      // Try explicit package directories below.
    }

    const candidates = [];
    if (process.env.PLAYWRIGHT_NODE_PATH) {
      candidates.push(process.env.PLAYWRIGHT_NODE_PATH);
    }
    if (process.env.USERPROFILE) {
      candidates.push(
        ...codexRuntimePlaywrightCandidates(process.env.USERPROFILE),
      );
    }

    const candidateErrors = [];
    for (const candidate of candidates) {
      const cjsEntry = path.join(candidate, 'index.js');
      if (fs.existsSync(cjsEntry)) {
        try {
          return require(cjsEntry);
        } catch (error) {
          candidateErrors.push(`${candidate}: ${error.message}`);
          continue;
        }
      }
      const esmEntry = path.join(candidate, 'index.mjs');
      if (fs.existsSync(esmEntry)) {
        try {
          return await import(pathToFileURL(esmEntry).href);
        } catch (error) {
          candidateErrors.push(`${candidate}: ${error.message}`);
        }
      }
    }

    fail(
      'Missing Playwright package. Install it or set PLAYWRIGHT_NODE_PATH to a playwright package directory.',
      candidateErrors.length > 0 ? candidateErrors.join('\n') : firstError,
    );
  }
}

function codexRuntimePlaywrightCandidates(userProfile) {
  const runtimeNodeModules = path.join(
    userProfile,
    '.cache',
    'codex-runtimes',
    'codex-primary-runtime',
    'dependencies',
    'node',
    'node_modules',
  );
  const candidates = [path.join(runtimeNodeModules, 'playwright')];
  const pnpmDir = path.join(runtimeNodeModules, '.pnpm');
  if (!fs.existsSync(pnpmDir)) return candidates;
  for (const entry of fs.readdirSync(pnpmDir, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith('playwright@')) continue;
    candidates.push(path.join(pnpmDir, entry.name, 'node_modules', 'playwright'));
  }
  return candidates;
}
