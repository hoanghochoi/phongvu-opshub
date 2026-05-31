import {
  getDataSyncSource,
  getPort,
  isCorsOriginAllowed,
  getRequiredEnv,
  validateRuntimeEnv,
} from './env';

const baseEnv = {
  DATABASE_URL: 'postgresql://user:pass@localhost:5432/opshub',
  JWT_SECRET: 'local-secret',
  REDIS_HOST: 'localhost',
  REDIS_PORT: '6379',
  UPLOAD_BASE_DIR: '/data/app_images',
  IMAGE_BASE_URL: 'https://img.example.com',
  PUBLIC_BASE_URL: 'http://localhost:3000',
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
