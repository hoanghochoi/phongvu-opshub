export const STATEMENT_PROVIDER_IDENTIFIERS_KEY = 'providerIdentifiers';

export type StatementProviderIdentifiers = {
  mapTransactionNumber: string | null;
  efastTrxId: string | null;
  efastTrxRefNo: string | null;
};

export type StoredStatementIdentifierRow = {
  transactionNumber?: string | null;
  rawData?: unknown;
};

type JsonRecord = Record<string, unknown>;

function asRecord(value: unknown): JsonRecord | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  return value as JsonRecord;
}

function text(value: unknown) {
  return value === null || value === undefined ? '' : String(value).trim();
}

function firstText(...values: unknown[]) {
  for (const value of values) {
    const normalized = text(value);
    if (normalized) return normalized;
  }
  return '';
}

export function readStatementProviderIdentifiers(
  row: StoredStatementIdentifierRow,
): StatementProviderIdentifiers {
  const rawData = asRecord(row.rawData) || {};
  const stored = asRecord(rawData[STATEMENT_PROVIDER_IDENTIFIERS_KEY]) || {};
  const isEfast = text(rawData.source) === 'VIETIN_EFAST';
  const transactionNumber = firstText(
    row.transactionNumber,
    rawData.transactionNumber,
  );

  return {
    mapTransactionNumber:
      firstText(
        stored.mapTransactionNumber,
        isEfast ? '' : transactionNumber,
      ) || null,
    efastTrxId:
      firstText(stored.efastTrxId, isEfast ? rawData.trxId : '') || null,
    efastTrxRefNo:
      firstText(stored.efastTrxRefNo, isEfast ? rawData.trxRefNo : '') ||
      null,
  };
}

export function mergeStatementProviderIdentifiers(
  baseRawData: unknown,
  ...rows: StoredStatementIdentifierRow[]
): JsonRecord {
  const base = asRecord(baseRawData) || {};
  const identifiers: StatementProviderIdentifiers = {
    mapTransactionNumber: null,
    efastTrxId: null,
    efastTrxRefNo: null,
  };

  for (const row of [{ rawData: baseRawData }, ...rows]) {
    const next = readStatementProviderIdentifiers(row);
    identifiers.mapTransactionNumber ||= next.mapTransactionNumber;
    identifiers.efastTrxId ||= next.efastTrxId;
    identifiers.efastTrxRefNo ||= next.efastTrxRefNo;
  }

  const providerIdentifiers = Object.fromEntries(
    Object.entries(identifiers).filter(([, value]) => Boolean(value)),
  );
  return Object.keys(providerIdentifiers).length > 0
    ? { ...base, [STATEMENT_PROVIDER_IDENTIFIERS_KEY]: providerIdentifiers }
    : { ...base };
}

export function conflictingStatementProviderIdentifiers(
  left: StoredStatementIdentifierRow,
  right: StoredStatementIdentifierRow,
) {
  const leftIdentifiers = readStatementProviderIdentifiers(left);
  const rightIdentifiers = readStatementProviderIdentifiers(right);
  return (
    Object.keys(leftIdentifiers) as Array<keyof StatementProviderIdentifiers>
  ).filter((key) => {
    const leftValue = leftIdentifiers[key];
    const rightValue = rightIdentifiers[key];
    return Boolean(leftValue && rightValue && leftValue !== rightValue);
  });
}

export function resolveStoredStatementNumber(
  row: StoredStatementIdentifierRow,
) {
  const rawData = asRecord(row.rawData) || {};
  const identifiers = readStatementProviderIdentifiers(row);
  if (identifiers.efastTrxId) return identifiers.efastTrxId;

  const isEfast = text(rawData.source) === 'VIETIN_EFAST';
  if (isEfast) {
    return (
      firstText(
        row.transactionNumber,
        rawData.transactionNumber,
        identifiers.efastTrxRefNo,
        rawData.txnReference,
      ) || null
    );
  }

  return (
    firstText(
      rawData.transactionReference,
      rawData.txnReference,
      identifiers.mapTransactionNumber,
      row.transactionNumber,
    ) || null
  );
}
