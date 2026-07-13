import {
  APP_LOG_CONTEXT_MAX_ARRAY_ITEMS,
  APP_LOG_CONTEXT_MAX_BYTES,
  APP_LOG_CONTEXT_MAX_KEYS,
  inspectAppLogContext,
} from './app-log-context-policy';

describe('app log context policy', () => {
  it('accepts a small diagnostic context and reports its size', () => {
    expect(
      inspectAppLogContext({ feature: 'fifo', count: 3, nested: { ok: true } }),
    ).toMatchObject({ keys: 4, depth: 2 });
  });

  it('rejects context larger than 16 KiB', () => {
    expect(() =>
      inspectAppLogContext({
        payload: Array.from({ length: 20 }, () => 'x'.repeat(1_000)),
      }),
    ).toThrow(`context_bytes_exceed_${APP_LOG_CONTEXT_MAX_BYTES}`);
  });

  it('rejects excessive keys, arrays and depth', () => {
    expect(() =>
      inspectAppLogContext(
        Object.fromEntries(
          Array.from({ length: APP_LOG_CONTEXT_MAX_KEYS + 1 }, (_, index) => [
            `key${index}`,
            index,
          ]),
        ),
      ),
    ).toThrow(`context_keys_exceed_${APP_LOG_CONTEXT_MAX_KEYS}`);
    expect(() =>
      inspectAppLogContext(
        Array.from({ length: APP_LOG_CONTEXT_MAX_ARRAY_ITEMS + 1 }),
      ),
    ).toThrow(`context_array_exceeds_${APP_LOG_CONTEXT_MAX_ARRAY_ITEMS}`);
    const tooDeep = { a: { b: { c: { d: { e: { f: 1 } } } } } };
    expect(() => inspectAppLogContext(tooDeep)).toThrow(
      'context_depth_exceeds_5',
    );
  });
});
