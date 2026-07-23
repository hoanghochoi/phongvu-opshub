import * as path from 'path';
import { resolveMapVietinBigQueryConfig } from '../map-vietin-bigquery/map-vietin-bigquery.config';

type EnvMap = Record<string, string | undefined>;

const REQUIRED_RUNTIME_KEYS = [
  'DATABASE_URL',
  'JWT_SECRET',
  'REDIS_HOST',
  'REDIS_PORT',
  'UPLOAD_BASE_DIR',
  'IMAGE_BASE_URL',
] as const;

const BIGQUERY_RUNTIME_KEYS = [
  'BIGQUERY_PROJECT_ID',
  'BIGQUERY_DATASET_ID',
  'BIGQUERY_TABLE_ID',
  'BIGQUERY_USER_DATASET_ID',
  'BIGQUERY_USER_TABLE_ID',
] as const;

const SYNC_SOURCES = ['local', 'bigquery'] as const;
type SyncSource = (typeof SYNC_SOURCES)[number];

const PRODUCTION_PLACEHOLDERS: Record<string, string[]> = {
  JWT_SECRET: [
    'change-me',
    'super-secret-key-change-me',
    'replace-with-long-random-jwt-secret',
  ],
  REDIS_PASSWORD: [
    'change-me',
    'opshub_password',
    'replace-with-a-long-random-secret',
    'replace-with-long-random-redis-password',
  ],
  IMAGE_BASE_URL: ['https://img.example.com'],
  PRIVATE_MEDIA_PUBLIC_BASE_URL: ['https://api.example.com/api'],
};

const PLACEHOLDER_SENSITIVE_KEYS = [
  'DATABASE_URL',
  'JWT_SECRET',
  'REDIS_PASSWORD',
  'SMTP_PASS',
  'VIETIN_EFAST_PASSWORD',
  'ERP_CLIENT_SECRET',
] as const;

const PRODUCTION_EXTERNAL_HOSTS: Record<string, Set<string>> = {
  MAP_VIETIN_NO_AUTH_BASE_URL: new Set(['map.vietinbank.vn']),
  MAP_VIETIN_TRANSACTION_BASE_URL: new Set(['map.vietinbank.vn']),
  VIETIN_EFAST_BASE_URL: new Set(['efast.vietinbank.vn']),
  ERP_IDENTITY_BASE_URL: new Set(['identity.tekoapis.com']),
  ERP_OAUTH_BASE_URL: new Set(['oauth-merchant.phongvu.vn']),
  ERP_STAFF_BFF_BASE_URL: new Set(['staff-bff.tekoapis.com']),
  ERP_LISTING_BASE_URL: new Set(['listing.tekoapis.com']),
  ERP_PPM_BASE_URL: new Set(['ppm.tekoapis.com']),
};

const LOCAL_ORIGIN_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);

function getEnvValue(env: EnvMap, key: string): string | undefined {
  const value = env[key]?.trim();
  return value ? value : undefined;
}

export function getRequiredEnv(key: string, env: EnvMap = process.env): string {
  const value = getEnvValue(env, key);
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

export function getPort(env: EnvMap = process.env): number {
  const rawPort = getEnvValue(env, 'PORT') ?? '3000';
  const port = Number(rawPort);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`Invalid PORT value: ${rawPort}`);
  }
  return port;
}

export function getDataSyncSource(env: EnvMap = process.env): SyncSource {
  const rawSource = getEnvValue(env, 'DATA_SYNC_SOURCE') ?? 'local';
  if (SYNC_SOURCES.includes(rawSource as SyncSource)) {
    return rawSource as SyncSource;
  }
  throw new Error(`Invalid DATA_SYNC_SOURCE value: ${rawSource}`);
}

export function getRequestBodyLimit(env: EnvMap = process.env): string {
  return getEnvValue(env, 'REQUEST_BODY_LIMIT') ?? '1mb';
}

export function isCorsOriginAllowed(
  origin?: string,
  env: EnvMap = process.env,
): boolean {
  if (!origin) {
    return true;
  }

  const allowedOrigins = getEnvValue(env, 'ALLOWED_ORIGINS');
  if (allowedOrigins === '*') {
    return env.NODE_ENV !== 'production';
  }

  if (allowedOrigins) {
    return allowedOrigins
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean)
      .includes(origin);
  }

  if (env.NODE_ENV === 'production') {
    return false;
  }

  try {
    const parsed = new URL(origin);
    return LOCAL_ORIGIN_HOSTS.has(parsed.hostname);
  } catch {
    return false;
  }
}

export function validateRuntimeEnv(env: EnvMap = process.env): void {
  const missing = REQUIRED_RUNTIME_KEYS.filter((key) => !getEnvValue(env, key));

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(', ')}`,
    );
  }

  getPort(env);
  getDataSyncSource(env);
  validateRedisPort(env);
  validateRedisSecurity(env);
  validateFifoDateTolerance(env);
  validateAllowedOrigins(env);
  validatePublicBaseUrl(env);
  validatePrivateMediaEnv(env);
  validateVietinEfastEnv(env);
  validateBigQueryEnv(env);
  validateMapVietinBigQueryEnv(env);
  validateProductionPlaceholders(env);
  validateProductionExternalUrls(env);
}

function validateRedisPort(env: EnvMap): void {
  const rawPort = getRequiredEnv('REDIS_PORT', env);
  const port = Number(rawPort);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`Invalid REDIS_PORT value: ${rawPort}`);
  }
}

function validatePrivateMediaEnv(env: EnvMap): void {
  const privateBaseDir = getEnvValue(env, 'PRIVATE_MEDIA_BASE_DIR');
  const publicMediaUrl = getEnvValue(env, 'PRIVATE_MEDIA_PUBLIC_BASE_URL');
  if (env.NODE_ENV === 'production' && !privateBaseDir) {
    throw new Error(
      'Missing required environment variable: PRIVATE_MEDIA_BASE_DIR',
    );
  }
  if (env.NODE_ENV === 'production' && !publicMediaUrl) {
    throw new Error(
      'Missing required environment variable: PRIVATE_MEDIA_PUBLIC_BASE_URL',
    );
  }
  if (publicMediaUrl) {
    const parsed =
      env.NODE_ENV === 'production'
        ? validateHttpsUrl('PRIVATE_MEDIA_PUBLIC_BASE_URL', publicMediaUrl)
        : validateHttpUrl('PRIVATE_MEDIA_PUBLIC_BASE_URL', publicMediaUrl);
    if (parsed.search || parsed.hash) {
      throw new Error(
        'PRIVATE_MEDIA_PUBLIC_BASE_URL must not include query or fragment',
      );
    }
  }
  if (privateBaseDir) {
    if (!path.isAbsolute(privateBaseDir)) {
      throw new Error('PRIVATE_MEDIA_BASE_DIR must be an absolute path');
    }
    const publicBaseDir = path.resolve(getRequiredEnv('UPLOAD_BASE_DIR', env));
    const privateResolved = path.resolve(privateBaseDir);
    if (
      privateResolved === publicBaseDir ||
      privateResolved.startsWith(publicBaseDir + path.sep) ||
      publicBaseDir.startsWith(privateResolved + path.sep)
    ) {
      throw new Error(
        'PRIVATE_MEDIA_BASE_DIR must be separate from UPLOAD_BASE_DIR',
      );
    }
  }
  validatePositiveIntegerEnv(env, 'UPLOAD_AGGREGATE_MAX_BYTES', 500_000_000);
  validatePositiveIntegerEnv(env, 'PRIVATE_MEDIA_MAX_PIXELS', 100_000_000);
}

function validateRedisSecurity(env: EnvMap): void {
  const password = getEnvValue(env, 'REDIS_PASSWORD');
  if (env.NODE_ENV === 'production' && !password) {
    throw new Error('Missing required environment variable: REDIS_PASSWORD');
  }
  if (getEnvValue(env, 'REDIS_USERNAME') && !password) {
    throw new Error('REDIS_USERNAME requires REDIS_PASSWORD');
  }
  for (const key of ['REDIS_TLS', 'REDIS_TLS_REJECT_UNAUTHORIZED']) {
    const value = getEnvValue(env, key);
    if (value && !['true', 'false'].includes(value.toLowerCase())) {
      throw new Error(`Invalid boolean environment variable: ${key}`);
    }
  }
  if (
    getEnvValue(env, 'REDIS_TLS_CA_FILE') &&
    getEnvValue(env, 'REDIS_TLS') !== 'true'
  ) {
    throw new Error('REDIS_TLS_CA_FILE requires REDIS_TLS=true');
  }
}

function validateFifoDateTolerance(env: EnvMap): void {
  const raw = getEnvValue(env, 'FIFO_DATE_TOLERANCE_DAYS');
  if (!raw) return;
  const days = Number(raw);
  if (!Number.isInteger(days) || days < 0 || days > 365) {
    throw new Error(`Invalid FIFO_DATE_TOLERANCE_DAYS value: ${raw}`);
  }
}

function validateBigQueryEnv(env: EnvMap): void {
  const usesLegacyBigQuery = getDataSyncSource(env) === 'bigquery';

  if (usesLegacyBigQuery) {
    const missing = BIGQUERY_RUNTIME_KEYS.filter(
      (key) => !getEnvValue(env, key),
    );
    if (missing.length > 0) {
      throw new Error(
        `Incomplete BigQuery configuration. Missing: ${missing.join(', ')}`,
      );
    }
  }

  const fifoConfigured = [
    'BIGQUERY_PROJECT_ID',
    'BIGQUERY_DATASET_ID',
    'BIGQUERY_TABLE_ID',
    'BIGQUERY_FIFO_DATASET_ID',
    'BIGQUERY_FIFO_TABLE_ID',
    'PRICE_WATCHDOG_BIGQUERY_PROJECT_ID',
    'PRICE_WATCHDOG_BIGQUERY_DATASET',
    'PRICE_WATCHDOG_BIGQUERY_TABLE',
  ].some((key) => getEnvValue(env, key));
  if (!fifoConfigured) {
    return;
  }

  const missing: string[] = [];
  if (
    !getEnvValue(env, 'BIGQUERY_PROJECT_ID') &&
    !getEnvValue(env, 'PRICE_WATCHDOG_BIGQUERY_PROJECT_ID')
  ) {
    missing.push('BIGQUERY_PROJECT_ID or PRICE_WATCHDOG_BIGQUERY_PROJECT_ID');
  }
  if (
    !getEnvValue(env, 'BIGQUERY_FIFO_DATASET_ID') &&
    !getEnvValue(env, 'BIGQUERY_DATASET_ID') &&
    !getEnvValue(env, 'PRICE_WATCHDOG_BIGQUERY_DATASET')
  ) {
    missing.push(
      'BIGQUERY_FIFO_DATASET_ID or BIGQUERY_DATASET_ID or PRICE_WATCHDOG_BIGQUERY_DATASET',
    );
  }
  if (
    !getEnvValue(env, 'BIGQUERY_FIFO_TABLE_ID') &&
    !getEnvValue(env, 'BIGQUERY_TABLE_ID') &&
    !getEnvValue(env, 'PRICE_WATCHDOG_BIGQUERY_TABLE')
  ) {
    missing.push(
      'BIGQUERY_FIFO_TABLE_ID or BIGQUERY_TABLE_ID or PRICE_WATCHDOG_BIGQUERY_TABLE',
    );
  }

  if (missing.length > 0) {
    throw new Error(
      `Incomplete FIFO BigQuery configuration. Missing: ${missing.join(', ')}`,
    );
  }
}

function validateMapVietinBigQueryEnv(env: EnvMap): void {
  resolveMapVietinBigQueryConfig(env as NodeJS.ProcessEnv);
}

function validateAllowedOrigins(env: EnvMap): void {
  const allowedOrigins = getEnvValue(env, 'ALLOWED_ORIGINS');
  if (env.NODE_ENV === 'production' && !allowedOrigins) {
    throw new Error('Missing required environment variable: ALLOWED_ORIGINS');
  }
  if (env.NODE_ENV === 'production' && allowedOrigins === '*') {
    throw new Error('ALLOWED_ORIGINS cannot be * in production');
  }
}

function validatePublicBaseUrl(env: EnvMap): void {
  const value = getEnvValue(env, 'PUBLIC_BASE_URL');
  if (env.NODE_ENV === 'production' && !value) {
    throw new Error('Missing required environment variable: PUBLIC_BASE_URL');
  }
  if (!value) return;
  try {
    const parsed = new URL(value);
    if (
      parsed.protocol !== 'https:' &&
      (env.NODE_ENV === 'production' || parsed.protocol !== 'http:')
    ) {
      throw new Error('invalid protocol');
    }
  } catch {
    throw new Error('Invalid PUBLIC_BASE_URL value');
  }
}

function validateVietinEfastEnv(env: EnvMap): void {
  if (getEnvValue(env, 'VIETIN_EFAST_SYNC_ENABLED') !== 'true') {
    return;
  }

  const required = [
    'VIETIN_EFAST_USERNAME',
    'VIETIN_EFAST_PASSWORD',
    'VIETIN_EFAST_BANK_ACCOUNTS',
  ];
  const missing = required.filter((key) => !getEnvValue(env, key));
  if (missing.length > 0) {
    throw new Error(
      `Incomplete VietinBank eFAST configuration. Missing: ${missing.join(', ')}`,
    );
  }

  const accounts = parseVietinEfastBankAccounts(
    getEnvValue(env, 'VIETIN_EFAST_BANK_ACCOUNTS') || '',
  );
  if (accounts.length === 0) {
    throw new Error(
      'VIETIN_EFAST_BANK_ACCOUNTS must include at least one account',
    );
  }

  validatePositiveIntegerEnv(env, 'VIETIN_EFAST_SYNC_MAX_PAGES', 1);
  validatePositiveIntegerEnv(env, 'VIETIN_EFAST_SESSION_TTL_SECONDS', 86400);
  validatePositiveIntegerEnv(env, 'VIETIN_EFAST_PAGE_SIZE', 150);
  const baseUrl = getEnvValue(env, 'VIETIN_EFAST_BASE_URL');
  if (baseUrl) {
    try {
      const parsed = new URL(baseUrl);
      if (
        parsed.protocol !== 'https:' &&
        (env.NODE_ENV === 'production' || parsed.protocol !== 'http:')
      ) {
        throw new Error('invalid protocol');
      }
    } catch {
      throw new Error('Invalid VIETIN_EFAST_BASE_URL value');
    }
  }
}

function parseVietinEfastBankAccounts(value: string): string[] {
  return value
    .split(',')
    .map((item) => item.trim().replace(/[^A-Z0-9]/gi, ''))
    .filter(Boolean);
}

function validatePositiveIntegerEnv(
  env: EnvMap,
  key: string,
  maxValue: number,
): void {
  const raw = getEnvValue(env, key);
  if (!raw) return;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0 || value > maxValue) {
    throw new Error(`Invalid ${key} value: ${raw}`);
  }
}

function validateProductionPlaceholders(env: EnvMap): void {
  if (env.NODE_ENV !== 'production') {
    return;
  }

  const unsafe = Object.entries(PRODUCTION_PLACEHOLDERS)
    .filter(([key, values]) => {
      const value = getEnvValue(env, key);
      return value ? values.includes(value) : false;
    })
    .map(([key]) => key);

  for (const key of PLACEHOLDER_SENSITIVE_KEYS) {
    const value = getEnvValue(env, key);
    if (
      value &&
      /(?:replace[-_]?with|change[-_]?me|opshub_password|example[-_]?secret)/i.test(
        value,
      ) &&
      !unsafe.includes(key)
    ) {
      unsafe.push(key);
    }
  }

  if (unsafe.length > 0) {
    throw new Error(
      `Unsafe placeholder environment values in production: ${unsafe.join(', ')}`,
    );
  }
}

function validateProductionExternalUrls(env: EnvMap): void {
  if (env.NODE_ENV !== 'production') return;

  const imageBaseUrl = getEnvValue(env, 'IMAGE_BASE_URL');
  if (imageBaseUrl) validateHttpsUrl('IMAGE_BASE_URL', imageBaseUrl);

  for (const [key, allowedHosts] of Object.entries(PRODUCTION_EXTERNAL_HOSTS)) {
    const value = getEnvValue(env, key);
    if (!value) continue;
    const parsed = validateHttpsUrl(key, value);
    if (!allowedHosts.has(parsed.hostname.toLowerCase())) {
      throw new Error(`${key} host is not allowed in production`);
    }
  }

  const ttsServiceUrl = getEnvValue(env, 'TTS_SERVICE_URL');
  if (ttsServiceUrl) validateTtsServiceUrl(ttsServiceUrl);
}

function validateHttpsUrl(key: string, value: string): URL {
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password) {
      throw new Error('invalid URL');
    }
    return parsed;
  } catch {
    throw new Error(`${key} must be an HTTPS URL without embedded credentials`);
  }
}

function validateHttpUrl(key: string, value: string): URL {
  try {
    const parsed = new URL(value);
    if (
      !['http:', 'https:'].includes(parsed.protocol) ||
      parsed.username ||
      parsed.password
    ) {
      throw new Error('invalid URL');
    }
    return parsed;
  } catch {
    throw new Error(
      `${key} must be an HTTP(S) URL without embedded credentials`,
    );
  }
}

function validateTtsServiceUrl(value: string): void {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error('Invalid TTS_SERVICE_URL value');
  }
  if (parsed.username || parsed.password) {
    throw new Error('TTS_SERVICE_URL must not contain embedded credentials');
  }
  if (parsed.protocol === 'https:') return;
  if (parsed.protocol !== 'http:' || !isPrivateServiceHost(parsed.hostname)) {
    throw new Error(
      'TTS_SERVICE_URL must use HTTPS unless it targets a private service host',
    );
  }
}

function isPrivateServiceHost(hostname: string): boolean {
  const normalized = hostname.toLowerCase();
  if (
    LOCAL_ORIGIN_HOSTS.has(normalized) ||
    normalized === 'host.docker.internal'
  ) {
    return true;
  }
  const parts = normalized.split('.').map(Number);
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part))) {
    return false;
  }
  return (
    parts[0] === 10 ||
    parts[0] === 127 ||
    (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
    (parts[0] === 192 && parts[1] === 168)
  );
}
