import {
  conflictingStatementProviderIdentifiers,
  mergeStatementProviderIdentifiers,
  readStatementProviderIdentifiers,
  resolveStoredStatementNumber,
} from './statement-identifiers';

describe('statement identifiers', () => {
  const mapRow = {
    transactionNumber: '2026198056714',
    rawData: { transactionNumber: '2026198056714' },
  };
  const efastRow = {
    transactionNumber: '333985',
    rawData: {
      source: 'VIETIN_EFAST',
      transactionNumber: '333985',
      trxId: '333985',
      trxRefNo: '331225',
    },
  };

  it.each([
    ['MAP-first', mapRow.rawData, mapRow, efastRow],
    ['eFAST-first', efastRow.rawData, efastRow, mapRow],
  ])('preserves both provider identifiers when %s', (_label, base, first, second) => {
    const rawData = mergeStatementProviderIdentifiers(base, first, second);

    expect(readStatementProviderIdentifiers({
      transactionNumber: first.transactionNumber,
      rawData,
    })).toEqual({
      mapTransactionNumber: '2026198056714',
      efastTrxId: '333985',
      efastTrxRefNo: '331225',
    });
    expect(resolveStoredStatementNumber({
      transactionNumber: first.transactionNumber,
      rawData,
    })).toBe('333985');
  });

  it('reports conflicting canonical identifiers instead of overwriting them', () => {
    expect(
      conflictingStatementProviderIdentifiers(efastRow, {
        transactionNumber: 'DIFFERENT',
        rawData: {
          source: 'VIETIN_EFAST',
          trxId: 'DIFFERENT',
          trxRefNo: '331225',
        },
      }),
    ).toEqual(['efastTrxId']);
  });
});
