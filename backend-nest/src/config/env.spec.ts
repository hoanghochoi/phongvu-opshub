import {
  getDataSyncSource,
  getPort,
  getRequestBodyLimit,
  isCorsOriginAllowed,
  getRequiredEnv,
  validateRuntimeEnv,
} from './env';

const baseEnv = {
  DATABASE_URL: 'postgresql://user:pass@localhost:5432/opshub',
  JWT_SECRET: 'local-secret',
  REDIS_HOST: 'localhost',
  REDIS_PORT: '6379',
  REDIS_PASSWORD: 'test-redis-password',
  UPLOAD_BASE_DIR: '/data/app_images',
  IMAGE_BASE_URL: 'https://img.example.com',
  PUBLIC_BASE_URL: 'https://opshub.example.com',
  PRIVATE_MEDIA_BASE_DIR: '/data/private-media',
  PRIVATE_MEDIA_PUBLIC_BASE_URL: 'https://opshub.example.com/api',
};

describe('env validation', () => {
  it('accepts required local runtime variables without BigQuery config', () => {
    expect(() => validateRuntimeEnv(baseEnv)).not.toThrow();
  });

  it('throws when required variables are missing', () => {
    expect(() => validateRuntimeEnv({ ...baseEnv, JWT_SECRET: '' })).toThrow(
      'Missing required environment variables: JWT_SECRET',
    );
  });

  it('rejects invalid port values', () => {
    expect(() => getPort({ ...baseEnv, PORT: 'not-a-port' })).toThrow(
      'Invalid PORT value: not-a-port',
    );
    expect(() =>
      validateRuntimeEnv({ ...baseEnv, REDIS_PORT: '70000' }),
    ).toThrow('Invalid REDIS_PORT value: 70000');
  });

  it('requires complete FIFO BigQuery config when any FIFO BigQuery value is set', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        BIGQUERY_PROJECT_ID: 'project-id',
      }),
    ).toThrow('Incomplete FIFO BigQuery configuration');
  });

  it('allows FIFO BigQuery config without enabling legacy data sync', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        BIGQUERY_PROJECT_ID: 'project-id',
        BIGQUERY_FIFO_DATASET_ID: 'fifo_dataset',
        BIGQUERY_FIFO_TABLE_ID: 'fifo_table',
      }),
    ).not.toThrow();
  });

  it('allows FIFO BigQuery config from price watchdog env names', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        PRICE_WATCHDOG_BIGQUERY_PROJECT_ID: 'project-id',
        PRICE_WATCHDOG_BIGQUERY_DATASET: 'Inventory',
        PRICE_WATCHDOG_BIGQUERY_TABLE: 'inv_seri_1',
      }),
    ).not.toThrow();
  });

  it('rejects invalid FIFO date tolerance values', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        FIFO_DATE_TOLERANCE_DAYS: 'twenty',
      }),
    ).toThrow('Invalid FIFO_DATE_TOLERANCE_DAYS value: twenty');
  });

  it('allows production local data sync without BigQuery config', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
      }),
    ).not.toThrow();
  });

  it('requires complete BigQuery config when BigQuery sync is enabled', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        DATA_SYNC_SOURCE: 'bigquery',
      }),
    ).toThrow('Incomplete BigQuery configuration');
  });

  it('rejects invalid data sync source values', () => {
    expect(() => getDataSyncSource({ DATA_SYNC_SOURCE: 'sheets' })).toThrow(
      'Invalid DATA_SYNC_SOURCE value: sheets',
    );
  });

  it('keeps the default request body limit and trims configured values', () => {
    expect(getRequestBodyLimit({})).toBe('1mb');
    expect(getRequestBodyLimit({ REQUEST_BODY_LIMIT: ' 2mb ' })).toBe('2mb');
  });

  it('rejects placeholder values in production', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        JWT_SECRET: 'change-me',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
      }),
    ).toThrow(
      'Unsafe placeholder environment values in production: JWT_SECRET',
    );
  });

  it('returns trimmed required values', () => {
    expect(getRequiredEnv('JWT_SECRET', { JWT_SECRET: '  secret  ' })).toBe(
      'secret',
    );
  });

  it('requires explicit CORS origins in production', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
      }),
    ).toThrow('Missing required environment variable: ALLOWED_ORIGINS');
  });

  it('requires public base URL in production', () => {
    const { PUBLIC_BASE_URL, ...env } = baseEnv;
    expect(() =>
      validateRuntimeEnv({
        ...env,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
      }),
    ).toThrow('Missing required environment variable: PUBLIC_BASE_URL');
  });

  it('rejects placeholder credentials embedded inside production URLs', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
        DATABASE_URL:
          'postgresql://user:replace-with-long-random-db-password@postgres:5432/opshub',
      }),
    ).toThrow(
      'Unsafe placeholder environment values in production: DATABASE_URL',
    );
  });

  it('requires Redis authentication in production', () => {
    const { REDIS_PASSWORD, ...env } = baseEnv;
    expect(() =>
      validateRuntimeEnv({
        ...env,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
      }),
    ).toThrow('Missing required environment variable: REDIS_PASSWORD');
  });

  it('requires private media configuration to be isolated in production', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
        PRIVATE_MEDIA_BASE_DIR: '',
      }),
    ).toThrow('Missing required environment variable: PRIVATE_MEDIA_BASE_DIR');

    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
        PRIVATE_MEDIA_BASE_DIR: '/data/app_images/private',
      }),
    ).toThrow('must be separate from UPLOAD_BASE_DIR');

    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
        IMAGE_BASE_URL: 'https://img.phongvu.example',
        PRIVATE_MEDIA_PUBLIC_BASE_URL: 'http://opshub.example.com/api',
      }),
    ).toThrow('must be an HTTPS URL');
  });

  it('validates Redis TLS settings without exposing credential values', () => {
    expect(() =>
      validateRuntimeEnv({ ...baseEnv, REDIS_TLS: 'sometimes' }),
    ).toThrow('Invalid boolean environment variable: REDIS_TLS');
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        REDIS_TLS_CA_FILE: '/run/secrets/redis-ca.pem',
      }),
    ).toThrow('REDIS_TLS_CA_FILE requires REDIS_TLS=true');
  });

  it('enforces HTTPS and exact known integration hosts in production', () => {
    const production = {
      ...baseEnv,
      NODE_ENV: 'production',
      ALLOWED_ORIGINS: 'https://opshub.example.com',
      IMAGE_BASE_URL: 'https://img.phongvu.example',
    };
    expect(() =>
      validateRuntimeEnv({
        ...production,
        MAP_VIETIN_TRANSACTION_BASE_URL: 'http://map.vietinbank.vn/api',
      }),
    ).toThrow('must be an HTTPS URL');
    expect(() =>
      validateRuntimeEnv({
        ...production,
        ERP_OAUTH_BASE_URL: 'https://evil.example/oauth',
      }),
    ).toThrow('host is not allowed in production');
    expect(() =>
      validateRuntimeEnv({
        ...production,
        TTS_SERVICE_URL: 'http://172.20.0.1:18081',
      }),
    ).not.toThrow();
  });

  it('requires eFAST credential and bank accounts only when eFAST sync is enabled', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        VIETIN_EFAST_SYNC_ENABLED: 'false',
      }),
    ).not.toThrow();

    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        VIETIN_EFAST_SYNC_ENABLED: 'true',
        VIETIN_EFAST_USERNAME: 'efast-user',
        VIETIN_EFAST_PASSWORD: 'efast-pass',
      }),
    ).toThrow(
      'Incomplete VietinBank eFAST configuration. Missing: VIETIN_EFAST_BANK_ACCOUNTS',
    );

    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        VIETIN_EFAST_SYNC_ENABLED: 'true',
        VIETIN_EFAST_USERNAME: 'efast-user',
        VIETIN_EFAST_PASSWORD: 'efast-pass',
        VIETIN_EFAST_BANK_ACCOUNTS: '1234567890, 0987654321',
        VIETIN_EFAST_CIFNO: 'enterprise-cifno',
        VIETIN_EFAST_PAGE_SIZE: '150',
        VIETIN_EFAST_SYNC_MAX_PAGES: '1',
        VIETIN_EFAST_SESSION_TTL_SECONDS: '600',
      }),
    ).not.toThrow();

    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        VIETIN_EFAST_SYNC_ENABLED: 'true',
        VIETIN_EFAST_USERNAME: 'efast-user',
        VIETIN_EFAST_PASSWORD: 'efast-pass',
        VIETIN_EFAST_BANK_ACCOUNTS: '1234567890',
        VIETIN_EFAST_PAGE_SIZE: '151',
      }),
    ).toThrow('Invalid VIETIN_EFAST_PAGE_SIZE value: 151');

    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        VIETIN_EFAST_SYNC_ENABLED: 'true',
        VIETIN_EFAST_USERNAME: 'efast-user',
        VIETIN_EFAST_PASSWORD: 'efast-pass',
        VIETIN_EFAST_BANK_ACCOUNTS: '1234567890',
        VIETIN_EFAST_SYNC_MAX_PAGES: '2',
      }),
    ).toThrow('Invalid VIETIN_EFAST_SYNC_MAX_PAGES value: 2');
  });

  it('checks CORS origins against the configured allowlist', () => {
    expect(
      isCorsOriginAllowed('https://opshub.example.com', {
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
      }),
    ).toBe(true);
    expect(
      isCorsOriginAllowed('https://evil.example.com', {
        NODE_ENV: 'production',
        ALLOWED_ORIGINS: 'https://opshub.example.com',
      }),
    ).toBe(false);
  });
});
