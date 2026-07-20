export const PRIVATE_MEDIA_MAX_APPLY_BATCH_SIZE = 250;

export const PRIVATE_MEDIA_BATCH_STRATEGY = Object.freeze({
  stableOffset: 'stable-offset',
  shrinkingHead: 'shrinking-head',
});

export function parsePrivateMediaBatchArgs(
  argv,
  {
    apply,
    strategy,
    maxApplyBatchSize = PRIVATE_MEDIA_MAX_APPLY_BATCH_SIZE,
  },
) {
  if (!Object.values(PRIVATE_MEDIA_BATCH_STRATEGY).includes(strategy)) {
    throw new Error('Unsupported private media batch strategy');
  }
  if (!Number.isSafeInteger(maxApplyBatchSize) || maxApplyBatchSize <= 0) {
    throw new Error('maxApplyBatchSize must be a positive integer');
  }

  const limit = integerArg(argv, 'limit', { minimum: 1 });
  const offsetProvided = argv.includes('--offset');
  const offset = integerArg(argv, 'offset', { minimum: 0 }) ?? 0;

  if (offsetProvided && strategy === PRIVATE_MEDIA_BATCH_STRATEGY.shrinkingHead) {
    throw new Error(
      '--offset is not supported for rollback because restored rows leave the candidate set',
    );
  }
  if (offset > 0 && limit === null) {
    throw new Error('--offset requires --limit');
  }
  if (apply && limit === null) {
    throw new Error('--limit is required with --apply');
  }
  if (apply && limit > maxApplyBatchSize) {
    throw new Error(
      `--limit must not exceed ${maxApplyBatchSize} with --apply`,
    );
  }

  return {
    strategy,
    limit,
    offset,
    maxApplyBatchSize,
  };
}

export function privateMediaBatchQuery(batch) {
  if (batch.limit === null) return {};
  return {
    skip:
      batch.strategy === PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset
        ? batch.offset
        : 0,
    take: batch.limit + 1,
  };
}

export function resolvePrivateMediaBatchPage(rows, batch) {
  if (!Array.isArray(rows)) throw new Error('rows must be an array');
  if (batch.limit === null) {
    return { rows, hasMore: false, nextOffset: null };
  }

  const hasMore = rows.length > batch.limit;
  return {
    rows: rows.slice(0, batch.limit),
    hasMore,
    nextOffset: hasMore
      ? batch.strategy === PRIVATE_MEDIA_BATCH_STRATEGY.stableOffset
        ? batch.offset + batch.limit
        : 0
      : null,
  };
}

function integerArg(argv, name, { minimum }) {
  const flag = `--${name}`;
  const indexes = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === flag) indexes.push(index);
  }
  if (indexes.length === 0) return null;
  if (indexes.length > 1) throw new Error(`${flag} must be specified once`);

  const raw = argv[indexes[0] + 1];
  if (raw === undefined || raw.startsWith('--')) {
    throw new Error(`${flag} requires an integer value`);
  }
  if (!/^(0|[1-9]\d*)$/.test(raw)) {
    const requirement = minimum === 0 ? 'a non-negative' : 'a positive';
    throw new Error(`${flag} must be ${requirement} integer`);
  }
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed < minimum) {
    const requirement = minimum === 0 ? 'a non-negative' : 'a positive';
    throw new Error(`${flag} must be ${requirement} integer`);
  }
  return parsed;
}
