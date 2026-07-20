const FEEDBACK_IMAGE_MARKER = 'Hình ảnh:';

export function parsePrivateMediaAuditArgs(argv) {
  const supported = new Set(['--strict', '--fail-on-legacy']);
  const seen = new Set();
  for (const value of argv) {
    if (!supported.has(value)) {
      throw new Error(`Unsupported argument: ${value}`);
    }
    if (seen.has(value)) {
      throw new Error(`${value} must be specified once`);
    }
    seen.add(value);
  }
  return {
    strict: seen.has('--strict'),
    failOnLegacy: seen.has('--fail-on-legacy'),
  };
}

export function summarizePrivateMediaReferences({
  avatars,
  warranties,
  feedbackItems,
  legacyBaseUrl,
  privatePublicBaseUrl,
}) {
  const legacyBase = normalizedBaseUrl(legacyBaseUrl);
  const privateBase = normalizedBaseUrl(privatePublicBaseUrl);
  const records = {
    avatar: emptyRecordSummary(),
    warranty: emptyRecordSummary(),
    feedback: emptyRecordSummary(),
  };
  const references = {
    legacy: emptyFeatureCounts(),
    protected: emptyFeatureCounts(),
    externalOrUnsupported: emptyFeatureCounts(),
  };

  summarizeFeature(
    'avatar',
    avatars,
    (value) => splitReferences(value),
    records,
    references,
    legacyBase,
    privateBase,
  );
  summarizeFeature(
    'warranty',
    warranties,
    (value) => splitReferences(value),
    records,
    references,
    legacyBase,
    privateBase,
  );
  summarizeFeature(
    'feedback',
    feedbackItems,
    extractFeedbackImageReferences,
    records,
    references,
    legacyBase,
    privateBase,
  );

  for (const counts of Object.values(references)) {
    counts.total = counts.avatar + counts.warranty + counts.feedback;
  }
  return { records, references };
}

export function extractFeedbackImageReferences(content) {
  const value = String(content || '');
  const markerIndex = value.lastIndexOf(FEEDBACK_IMAGE_MARKER);
  if (markerIndex < 0) return [];
  const lineStart = markerIndex + FEEDBACK_IMAGE_MARKER.length;
  const lineEndCandidate = value.indexOf('\n', lineStart);
  const lineEnd = lineEndCandidate < 0 ? value.length : lineEndCandidate;
  return splitReferences(value.slice(lineStart, lineEnd));
}

function summarizeFeature(
  feature,
  values,
  extractReferences,
  records,
  references,
  legacyBase,
  privateBase,
) {
  for (const value of values) {
    records[feature].scanned += 1;
    const classifications = new Set();
    for (const reference of extractReferences(value)) {
      const classification = classifyReference(
        reference,
        legacyBase,
        privateBase,
      );
      references[classification][feature] += 1;
      classifications.add(classification);
    }
    for (const classification of classifications) {
      records[feature][recordCounter(classification)] += 1;
    }
  }
}

function classifyReference(value, legacyBase, privateBase) {
  const raw = String(value || '').trim();
  if (!raw) return 'externalOrUnsupported';
  let target;
  try {
    target = new URL(raw, legacyBase.origin);
  } catch {
    return 'externalOrUnsupported';
  }
  if (matchesRoute(target, legacyBase, legacyBase.pathname)) return 'legacy';
  if (
    matchesRoute(
      target,
      privateBase,
      `${privateBase.pathname.replace(/\/+$/, '')}/media`,
    )
  ) {
    return 'protected';
  }
  return 'externalOrUnsupported';
}

function matchesRoute(target, base, routePath) {
  if (target.origin !== base.origin) return false;
  const prefix = `${routePath.replace(/\/+$/, '')}/`;
  return (
    target.pathname.startsWith(prefix) && target.pathname.length > prefix.length
  );
}

function normalizedBaseUrl(value) {
  const parsed = new URL(value);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Private media audit base URL is invalid');
  }
  parsed.username = '';
  parsed.password = '';
  parsed.search = '';
  parsed.hash = '';
  parsed.pathname = parsed.pathname.replace(/\/+$/, '') || '/';
  return parsed;
}

function splitReferences(value) {
  return String(value || '')
    .split(';')
    .map((item) => item.trim())
    .filter(Boolean);
}

function emptyRecordSummary() {
  return {
    scanned: 0,
    withLegacy: 0,
    withProtected: 0,
    withExternalOrUnsupported: 0,
  };
}

function emptyFeatureCounts() {
  return { avatar: 0, warranty: 0, feedback: 0, total: 0 };
}

function recordCounter(classification) {
  if (classification === 'legacy') return 'withLegacy';
  if (classification === 'protected') return 'withProtected';
  return 'withExternalOrUnsupported';
}
