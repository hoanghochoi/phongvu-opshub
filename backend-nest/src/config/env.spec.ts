import {
  getDataSyncSource,
  getPort,
  getRequiredEnv,
  validateRuntimeEnv,
} from './env';

const baseEnv = {
  DATABASE_URL: 'postgresql://user:pass@localhost:5432/opshub',
  JWT_SECRET: 'local-secret',
  GOOGLE_CLIENT_ID: 'client-id.apps.googleusercontent.com',
  ALLOWED_DOMAIN: 'phongvu.vn',
  REDIS_HOST: 'localhost',
  REDIS_PORT: '6379',
  UPLOAD_BASE_DIR: '/data/app_images',
  IMAGE_BASE_URL: 'https://img.example.com',
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

  it('requires complete BigQuery config when any BigQuery value is set', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        BIGQUERY_PROJECT_ID: 'project-id',
      }),
    ).toThrow('Incomplete BigQuery configuration');
  });

  it('allows production local data sync without BigQuery config', () => {
    expect(() =>
      validateRuntimeEnv({
        ...baseEnv,
        NODE_ENV: 'production',
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
});
