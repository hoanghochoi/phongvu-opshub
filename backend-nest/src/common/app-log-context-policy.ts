export const APP_LOG_CONTEXT_MAX_BYTES = 16 * 1024;
export const APP_LOG_CONTEXT_MAX_DEPTH = 5;
export const APP_LOG_CONTEXT_MAX_KEYS = 80;
export const APP_LOG_CONTEXT_MAX_ARRAY_ITEMS = 50;
export const APP_LOG_CONTEXT_MAX_STRING_LENGTH = 2_000;

export type AppLogContextStats = {
  bytes: number;
  keys: number;
  depth: number;
};

export function inspectAppLogContext(value: unknown): AppLogContextStats {
  let keys = 0;
  let maxDepth = 0;

  const visit = (item: unknown, depth: number) => {
    maxDepth = Math.max(maxDepth, depth);
    if (depth > APP_LOG_CONTEXT_MAX_DEPTH) {
      throw new Error(`context_depth_exceeds_${APP_LOG_CONTEXT_MAX_DEPTH}`);
    }
    if (typeof item === 'string') {
      if (item.length > APP_LOG_CONTEXT_MAX_STRING_LENGTH) {
        throw new Error(
          `context_string_exceeds_${APP_LOG_CONTEXT_MAX_STRING_LENGTH}`,
        );
      }
      return;
    }
    if (item === null || typeof item !== 'object') return;
    if (Array.isArray(item)) {
      if (item.length > APP_LOG_CONTEXT_MAX_ARRAY_ITEMS) {
        throw new Error(
          `context_array_exceeds_${APP_LOG_CONTEXT_MAX_ARRAY_ITEMS}`,
        );
      }
      for (const child of item) visit(child, depth + 1);
      return;
    }

    for (const [key, child] of Object.entries(
      item as Record<string, unknown>,
    )) {
      if (['__proto__', 'constructor', 'prototype'].includes(key)) {
        throw new Error('context_contains_unsafe_key');
      }
      keys += 1;
      if (keys > APP_LOG_CONTEXT_MAX_KEYS) {
        throw new Error(`context_keys_exceed_${APP_LOG_CONTEXT_MAX_KEYS}`);
      }
      visit(child, depth + 1);
    }
  };

  visit(value, 0);
  const serialized = JSON.stringify(value);
  const bytes = Buffer.byteLength(serialized ?? '', 'utf8');
  if (bytes > APP_LOG_CONTEXT_MAX_BYTES) {
    throw new Error(`context_bytes_exceed_${APP_LOG_CONTEXT_MAX_BYTES}`);
  }
  return { bytes, keys, depth: maxDepth };
}
