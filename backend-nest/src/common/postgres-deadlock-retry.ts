const POSTGRES_DEADLOCK_SQLSTATE = '40P01';
const DEFAULT_MAX_ATTEMPTS = 3;
const MAX_ALLOWED_ATTEMPTS = 3;
const DEFAULT_BASE_DELAY_MS = 25;
const DEFAULT_MAX_DELAY_MS = 250;

const SQLSTATE_KEYS = ['originalCode', 'sqlState', 'sqlstate', 'code'] as const;
const NESTED_ERROR_KEYS = [
  'cause',
  'meta',
  'driverAdapterError',
  'originalError',
  'error',
] as const;

export interface PostgresDeadlockRetryLogger {
  log(message: string): unknown;
  warn(message: string): unknown;
  error(message: string): unknown;
}

interface PostgresDeadlockRetryOptions {
  operation: string;
  logger: PostgresDeadlockRetryLogger;
  maxAttempts?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  random?: () => number;
  sleep?: (delayMs: number) => Promise<void>;
}

function structuredRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : null;
}

function normalizedCode(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().toUpperCase();
  return normalized.length > 0 ? normalized : null;
}

export function findPostgresSqlState(error: unknown): string | null {
  const pending: Array<{ value: unknown; depth: number }> = [
    { value: error, depth: 0 },
  ];
  const seen = new Set<object>();
  let firstStructuredCode: string | null = null;

  while (pending.length > 0) {
    const current = pending.shift()!;
    if (current.depth > 6) continue;
    const record = structuredRecord(current.value);
    if (!record || seen.has(record)) continue;
    seen.add(record);

    for (const key of SQLSTATE_KEYS) {
      const code = normalizedCode(record[key]);
      if (!code) continue;
      if (code === POSTGRES_DEADLOCK_SQLSTATE) return code;
      firstStructuredCode ??= code;
    }
    for (const key of NESTED_ERROR_KEYS) {
      const nested = record[key];
      if (nested !== undefined && nested !== null) {
        pending.push({ value: nested, depth: current.depth + 1 });
      }
    }
  }

  return firstStructuredCode;
}

export function isPostgresDeadlock(error: unknown) {
  return findPostgresSqlState(error) === POSTGRES_DEADLOCK_SQLSTATE;
}

function defaultSleep(delayMs: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, delayMs));
}

function boundedPositiveInteger(value: number | undefined, fallback: number) {
  if (!Number.isFinite(value) || value === undefined) return fallback;
  return Math.max(1, Math.floor(value));
}

export async function withPostgresDeadlockRetry<T>(
  execute: () => Promise<T>,
  options: PostgresDeadlockRetryOptions,
): Promise<T> {
  const maxAttempts = Math.min(
    boundedPositiveInteger(options.maxAttempts, DEFAULT_MAX_ATTEMPTS),
    MAX_ALLOWED_ATTEMPTS,
  );
  const baseDelayMs = boundedPositiveInteger(
    options.baseDelayMs,
    DEFAULT_BASE_DELAY_MS,
  );
  const maxDelayMs = Math.max(
    baseDelayMs,
    boundedPositiveInteger(options.maxDelayMs, DEFAULT_MAX_DELAY_MS),
  );
  const random = options.random ?? Math.random;
  const sleep = options.sleep ?? defaultSleep;
  const startedAt = Date.now();

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const result = await execute();
      if (attempt > 1) {
        options.logger.log(
          `Postgres deadlock retry succeeded: operation=${options.operation} attempt=${attempt} maxAttempts=${maxAttempts} sqlState=${POSTGRES_DEADLOCK_SQLSTATE} durationMs=${Date.now() - startedAt}`,
        );
      }
      return result;
    } catch (error) {
      if (!isPostgresDeadlock(error)) throw error;
      if (attempt >= maxAttempts) {
        options.logger.error(
          `Postgres deadlock retry exhausted: operation=${options.operation} attempt=${attempt} maxAttempts=${maxAttempts} sqlState=${POSTGRES_DEADLOCK_SQLSTATE} durationMs=${Date.now() - startedAt}`,
        );
        throw error;
      }

      const exponentialDelay = Math.min(
        baseDelayMs * 2 ** (attempt - 1),
        maxDelayMs,
      );
      const randomUnit = Math.min(Math.max(random(), 0), 0.999999);
      const delayMs = Math.min(
        exponentialDelay + Math.floor(randomUnit * baseDelayMs),
        maxDelayMs,
      );
      options.logger.warn(
        `Postgres deadlock retry scheduled: operation=${options.operation} attempt=${attempt} nextAttempt=${attempt + 1} maxAttempts=${maxAttempts} delayMs=${delayMs} sqlState=${POSTGRES_DEADLOCK_SQLSTATE} durationMs=${Date.now() - startedAt}`,
      );
      await sleep(delayMs);
    }
  }

  throw new Error('Postgres deadlock retry reached an unreachable state');
}
