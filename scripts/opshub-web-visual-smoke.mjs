import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

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
const headless = process.env.OPSHUB_VISUAL_SMOKE_HEADLESS !== 'false';
const preferredBrowserChannel = process.env.OPSHUB_VISUAL_SMOKE_BROWSER_CHANNEL;
const waitMs = Number(process.env.OPSHUB_VISUAL_SMOKE_WAIT_MS || 1200);
const viewports = parseViewports(
  process.env.OPSHUB_VISUAL_SMOKE_VIEWPORTS || 'desktop=1440x900,mobile=390x844',
);
const routes = parseRoutes(
  process.env.OPSHUB_VISUAL_SMOKE_ROUTES ||
    [
      '/home',
      '/tasks',
      '/fifo-menu',
      '/sort',
      '/warranty-main',
      '/check-warranty',
      '/vietqr',
      '/bank-statement',
      '/reports',
      '/admin/organization',
      '/admin/sales-reports',
      '/profile',
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
const browser = await launchBrowser(chromium);
const startedAt = new Date();
const summary = {
  baseUrl,
  apiBaseUrl,
  storageEnvironment,
  startedAt: startedAt.toISOString(),
  routeCount: routes.length,
  viewportCount: viewports.length,
  routes,
  viewports,
  results: [],
  failures: [],
};

try {
  for (const viewport of viewports) {
    const context = await browser.newContext({
      viewport: { width: viewport.width, height: viewport.height },
      deviceScaleFactor: 1,
    });
    await context.addInitScript(seedSessionStorage, {
      session,
      storageEnvironment,
    });
    const page = await context.newPage();
    const runtimeErrors = [];
    page.on('console', (message) => {
      if (message.type() === 'error') {
        runtimeErrors.push(`console: ${message.text()}`);
      }
    });
    page.on('pageerror', (error) => {
      runtimeErrors.push(`pageerror: ${error.message}`);
    });

    await page.goto(`${baseUrl}/#/home`, {
      waitUntil: 'domcontentloaded',
      timeout: 45000,
    });
    await waitForFlutter(page);
    await waitForNetworkQuiet(page);
    await dismissOptionalUpdate(page);
    await page.waitForTimeout(waitMs);

    for (const route of routes) {
      const errorsBefore = runtimeErrors.length;
      const url = `${baseUrl}/#${route}`;
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
      await waitForFlutter(page);
      await waitForNetworkQuiet(page);
      await dismissOptionalUpdate(page);
      await page.waitForTimeout(waitMs);

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
      const screenshotName = `${viewport.name}-${slugRoute(route)}.png`;
      const screenshotPath = path.join(outputDir, screenshotName);
      await page.screenshot({ path: screenshotPath, fullPage: false });
      const screenshotBytes = fs.statSync(screenshotPath).size;
      const routeErrors = runtimeErrors.slice(errorsBefore);
      const horizontalOverflow =
        metrics.rootScrollWidth > metrics.innerWidth + 2 ||
        metrics.flutterViewWidth > metrics.innerWidth + 2 ||
        metrics.overflowElements.length > 0;
      const result = {
        viewport: viewport.name,
        route,
        actualRoute,
        ok: true,
        screenshot: path.relative(workspace, screenshotPath).replaceAll(path.sep, '/'),
        screenshotBytes,
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
      }

      if (!result.ok) summary.failures.push(result);
      summary.results.push(result);
    }

    await context.close();
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
      failures: summary.failures.map(({ viewport, route, reason }) => ({
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

function normalizeBaseUrl(value) {
  return value.replace(/\/+$/, '');
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

function slugRoute(route) {
  return route.replace(/^\/+/, '').replace(/[^a-z0-9]+/gi, '-') || 'home';
}

function fail(message, error) {
  process.stderr.write(`${message}\n`);
  if (error) process.stderr.write(`${error.stack || error.message || error}\n`);
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
