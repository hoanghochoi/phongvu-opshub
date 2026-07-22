import assert from 'node:assert/strict';
import test from 'node:test';
import {
  bankFingerprint,
  decideRepair,
  extractEvidenceTransactions,
} from './repair-map-efast-identifiers.mjs';

const evidence = {
  id: 'deleted-efast',
  storeCode: 'CP61',
  transactionNumber: '333985',
  amount: 9146000,
  content: 'XNLD CAO THE TT TIEN CAMERA HD 2807',
  paidAt: '2026-07-17T10:25:40.000Z',
  rawData: {
    source: 'VIETIN_EFAST',
    trxId: '333985',
    trxRefNo: '331225',
  },
};

const mapCandidate = {
  id: 'retained-map',
  storeCode: 'CP61',
  transactionNumber: '2026198056714',
  amount: 9146000,
  content: evidence.content,
  paidAt: evidence.paidAt,
  rawData: { transactionNumber: '2026198056714' },
};

test('extracts eFAST transaction evidence from a mixed checkpoint', () => {
  const jsonl = [
    JSON.stringify({ table: 'PaymentNotification', row: { id: 'note-1' } }),
    JSON.stringify({ table: 'MapVietinTransaction', row: evidence }),
  ].join('\n');

  assert.deepEqual(extractEvidenceTransactions(jsonl), [evidence]);
});

test('builds an exact fingerprint and enriches the one MAP survivor', () => {
  assert.equal(
    bankFingerprint(evidence),
    'CP61|9146000|2026-07-17T10:25:40.000Z|XNLD CAO THE TT TIEN CAMERA HD 2807',
  );
  const decision = decideRepair(evidence, [mapCandidate]);
  assert.equal(decision.status, 'ready');
  assert.equal(decision.canonicalStatementNumber, '333985');
  assert.deepEqual(decision.rawData.providerIdentifiers, {
    mapTransactionNumber: '2026198056714',
    efastTrxId: '333985',
    efastTrxRefNo: '331225',
  });
});

test('stops instead of choosing between multiple MAP survivors', () => {
  assert.deepEqual(
    decideRepair(evidence, [
      mapCandidate,
      { ...mapCandidate, id: 'retained-map-2' },
    ]),
    { status: 'ambiguous', candidateCount: 2 },
  );
});

test('stops when an existing eFAST identifier conflicts', () => {
  const decision = decideRepair(evidence, [
    {
      ...mapCandidate,
      rawData: {
        ...mapCandidate.rawData,
        providerIdentifiers: {
          mapTransactionNumber: '2026198056714',
          efastTrxId: 'DIFFERENT',
        },
      },
    },
  ]);
  assert.equal(decision.status, 'conflict');
  assert.deepEqual(decision.conflicts, ['efastTrxId']);
});
