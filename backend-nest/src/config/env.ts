type EnvMap = Record<string, string | undefined>;

const REQUIRED_RUNTIME_KEYS = [
  'DATABASE_URL',
  'JWT_SECRET',
  'GOOGLE_CLIENT_ID',
  'ALLOWED_DOMAIN',
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

const PRODUCTION_PLACEHOLDERS: Record<string, string[]> = {
  JWT_SECRET: ['change-me', 'super-secret-key-change-me'],
  GOOGLE_CLIENT_ID: ['your-google-oauth-client-id.apps.googleusercontent.com'],
  IMAGE_BASE_URL: ['https://img.example.com'],
};

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

export function validateRuntimeEnv(env: EnvMap = process.env): void {
  const missing = REQUIRED_RUNTIME_KEYS.filter((key) => !getEnvValue(env, key));

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(', ')}`,
    );
  }

  getPort(env);
  validateRedisPort(env);
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

function validateBigQueryEnv(env: EnvMap): void {
  const configured = BIGQUERY_RUNTIME_KEYS.filter((key) =>
    getEnvValue(env, key),
  );
  const isProduction = env.NODE_ENV === 'production';

  if (configured.length === 0 && !isProduction) {
    return;
  }

  const missing = BIGQUERY_RUNTIME_KEYS.filter((key) => !getEnvValue(env, key));
  if (missing.length > 0) {
    throw new Error(
      `Incomplete BigQuery configuration. Missing: ${missing.join(', ')}`,
    );
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
