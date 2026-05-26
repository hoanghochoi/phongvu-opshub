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
  JWT_SECRET: ['change-me', 'super-secret-key-change-me'],
  IMAGE_BASE_URL: ['https://img.example.com'],
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
  validateFifoDateTolerance(env);
  validateAllowedOrigins(env);
  validateBigQueryEnv(env);
  validateProductionPlaceholders(env);
}

function validateRedisPort(env: EnvMap): void {
  const rawPort = getRequiredEnv('REDIS_PORT', env);
  const port = Number(rawPort);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`Invalid REDIS_PORT value: ${rawPort}`);
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

function validateAllowedOrigins(env: EnvMap): void {
  const allowedOrigins = getEnvValue(env, 'ALLOWED_ORIGINS');
  if (env.NODE_ENV === 'production' && !allowedOrigins) {
    throw new Error('Missing required environment variable: ALLOWED_ORIGINS');
  }
  if (env.NODE_ENV === 'production' && allowedOrigins === '*') {
    throw new Error('ALLOWED_ORIGINS cannot be * in production');
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

  if (unsafe.length > 0) {
    throw new Error(
      `Unsafe placeholder environment values in production: ${unsafe.join(', ')}`,
    );
  }
}
