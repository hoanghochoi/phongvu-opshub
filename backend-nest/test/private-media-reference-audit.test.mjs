import assert from 'node:assert/strict';
import test from 'node:test';
import {
  extractFeedbackImageReferences,
  parsePrivateMediaAuditArgs,
  summarizePrivateMediaReferences,
} from '../scripts/private-media-reference-audit.mjs';

const legacyBaseUrl = 'https://opshub.example/uploads';
const privatePublicBaseUrl = 'https://opshub.example/api';

test('summarizes legacy and protected references without exposing values', () => {
  const summary = summarizePrivateMediaReferences({
    avatars: [
      'https://opshub.example/uploads/private-customer-avatar.jpg',
      'https://opshub.example/api/media/11111111-1111-1111-1111-111111111111',
      'https://images.example/external-avatar.jpg',
      '/uploads/root-relative-avatar.jpg?temporary=secret',
    ],
    warranties: [
      'https://opshub.example/uploads/warranty-secret.jpg;https://opshub.example/api/media/22222222-2222-2222-2222-222222222222;https://images.example/external.jpg',
      '/uploads/relative-warranty.jpg;/api/media/33333333-3333-3333-3333-333333333333?version=1',
    ],
    feedbackItems: [
      'Hình ảnh: https://ignored.example/old.jpg\nNội dung\nHình ảnh: /uploads/feedback-secret.jpg;/api/media/44444444-4444-4444-4444-444444444444\nSau ảnh',
      'Hình ảnh: https://images.example/external-feedback.jpg',
    ],
    legacyBaseUrl,
    privatePublicBaseUrl,
  });

  assert.deepEqual(summary.references.legacy, {
    avatar: 2,
    warranty: 2,
    feedback: 1,
    total: 5,
  });
  assert.deepEqual(summary.references.protected, {
    avatar: 1,
    warranty: 2,
    feedback: 1,
    total: 4,
  });
  assert.deepEqual(summary.references.externalOrUnsupported, {
    avatar: 1,
    warranty: 1,
    feedback: 1,
    total: 3,
  });
  assert.deepEqual(summary.records.avatar, {
    scanned: 4,
    withLegacy: 2,
    withProtected: 1,
    withExternalOrUnsupported: 1,
  });
  assert.deepEqual(summary.records.warranty, {
    scanned: 2,
    withLegacy: 2,
    withProtected: 2,
    withExternalOrUnsupported: 1,
  });
  assert.deepEqual(summary.records.feedback, {
    scanned: 2,
    withLegacy: 1,
    withProtected: 1,
    withExternalOrUnsupported: 1,
  });

  const serialized = JSON.stringify(summary);
  for (const forbidden of [
    'private-customer-avatar.jpg',
    'warranty-secret.jpg',
    'feedback-secret.jpg',
    'temporary=secret',
  ]) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test('requires an exact legacy route and conservatively catches relative paths', () => {
  const summary = summarizePrivateMediaReferences({
    avatars: [
      'https://evil.example/uploads/not-ours.jpg',
      'https://opshub.example/uploads-archive/not-live.jpg',
      'uploads/not-root-relative.jpg',
    ],
    warranties: [],
    feedbackItems: [],
    legacyBaseUrl,
    privatePublicBaseUrl,
  });

  assert.equal(summary.references.legacy.total, 1);
  assert.equal(summary.references.externalOrUnsupported.total, 2);
});

test('uses only the final feedback image marker, matching migration behavior', () => {
  assert.deepEqual(
    extractFeedbackImageReferences(
      'Hình ảnh: /uploads/old.jpg\nText\nHình ảnh: /uploads/final.jpg;/api/media/final-id\nTail',
    ),
    ['/uploads/final.jpg', '/api/media/final-id'],
  );
});

test('audit arguments fail closed on typos and duplicates', () => {
  assert.deepEqual(parsePrivateMediaAuditArgs([]), {
    strict: false,
    failOnLegacy: false,
  });
  assert.deepEqual(
    parsePrivateMediaAuditArgs(['--strict', '--fail-on-legacy']),
    { strict: true, failOnLegacy: true },
  );
  assert.throws(
    () => parsePrivateMediaAuditArgs(['--fail-on-legcy']),
    /Unsupported argument/,
  );
  assert.throws(
    () => parsePrivateMediaAuditArgs(['--strict', '--strict']),
    /must be specified once/,
  );
});
