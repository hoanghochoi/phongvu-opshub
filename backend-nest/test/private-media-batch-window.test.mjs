import assert from 'node:assert/strict';
import test from 'node:test';

import {
  PRIVATE_MEDIA_BATCH_STRATEGY,
  parsePrivateMediaBatchArgs,
  privateMediaBatchQuery,
  resolvePrivateMediaBatchPage,
} from '../scripts/private-media-batch-window.mjs';

test('allows a complete dry-run without a batch limit', () => {
  const batch = parsePrivateMediaBatchArgs([], {
    apply: false,
    strategy: PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset,
  });

  assert.equal(batch.limit, null);
  assert.equal(batch.offset, 0);
  assert.deepEqual(privateMediaBatchQuery(batch), {});
});

test('requires a bounded batch for apply', () => {
  assert.throws(
    () =>
      parsePrivateMediaBatchArgs([], {
        apply: true,
        strategy: PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset,
      }),
    /--limit is required with --apply/,
  );
  assert.throws(
    () =>
      parsePrivateMediaBatchArgs(['--limit', '251'], {
        apply: true,
        strategy: PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset,
      }),
    /must not exceed 250/,
  );
});

test('validates limit and offset arguments', () => {
  const options = {
    apply: false,
    strategy: PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset,
  };
  assert.throws(
    () => parsePrivateMediaBatchArgs(['--offset', '1'], options),
    /--offset requires --limit/,
  );
  assert.throws(
    () => parsePrivateMediaBatchArgs(['--limit', '0'], options),
    /--limit must be a positive integer/,
  );
  assert.throws(
    () => parsePrivateMediaBatchArgs(['--limit', '1e2'], options),
    /--limit must be a positive integer/,
  );
  assert.throws(
    () => parsePrivateMediaBatchArgs(['--limit', '10', '--limit', '20'], options),
    /--limit must be specified once/,
  );
});

test('uses stable offsets for migration batches', () => {
  const batch = parsePrivateMediaBatchArgs(
    ['--limit', '2', '--offset', '4'],
    {
      apply: true,
      strategy: PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset,
    },
  );

  assert.deepEqual(privateMediaBatchQuery(batch), { skip: 4, take: 3 });
  assert.deepEqual(resolvePrivateMediaBatchPage(['a', 'b', 'c'], batch), {
    rows: ['a', 'b'],
    hasMore: true,
    nextOffset: 6,
  });
});

test('rollback always continues from the shrinking head', () => {
  const batch = parsePrivateMediaBatchArgs(['--limit', '2'], {
    apply: true,
    strategy: PRIVATE_MEDIA_BATCH_STRATEGY.shrinkingHead,
  });

  assert.deepEqual(privateMediaBatchQuery(batch), { skip: 0, take: 3 });
  assert.deepEqual(resolvePrivateMediaBatchPage(['a', 'b', 'c'], batch), {
    rows: ['a', 'b'],
    hasMore: true,
    nextOffset: 0,
  });
  assert.throws(
    () =>
      parsePrivateMediaBatchArgs(['--limit', '2', '--offset', '2'], {
        apply: true,
        strategy: PRIVATE_MEDIA_BATCH_STRATEGY.shrinkingHead,
      }),
    /--offset is not supported for rollback/,
  );
});

test('marks the final bounded page complete', () => {
  const batch = parsePrivateMediaBatchArgs(
    ['--limit', '2', '--offset', '4'],
    {
      apply: true,
      strategy: PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset,
    },
  );

  assert.deepEqual(resolvePrivateMediaBatchPage(['a'], batch), {
    rows: ['a'],
    hasMore: false,
    nextOffset: null,
  });
});
