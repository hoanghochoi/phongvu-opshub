import {
  csvCell,
  csvExcelTextCell,
  neutralizeSpreadsheetFormula,
} from './csv-export';

describe('safe CSV export', () => {
  it.each(['=2+2', '+cmd', '-10+20', '@SUM(A1:A2)', '\t=1+1', '\r=1+1', '\n=1+1']) (
    'neutralizes spreadsheet formula prefix %p',
    (value) => {
      expect(neutralizeSpreadsheetFormula(value)).toBe(`'${value}`);
      expect(csvCell(value)).toContain(`'${value}`);
    },
  );

  it('neutralizes a formula after leading whitespace', () => {
    expect(csvCell('  =HYPERLINK("https://invalid.example")')).toBe(
      '"\'  =HYPERLINK(""https://invalid.example"")"',
    );
  });

  it('keeps Vietnamese, commas, quotes and line breaks in RFC 4180 cells', () => {
    expect(csvCell('Tiếng Việt, "đúng"\ndòng 2')).toBe(
      '"Tiếng Việt, ""đúng""\ndòng 2"',
    );
  });

  it('preserves long identifiers as text without creating a formula', () => {
    expect(csvExcelTextCell('00020300000000004567')).toBe(
      "'00020300000000004567",
    );
    expect(
      csvExcelTextCell('26052912345678\r\n26053087654321', {
        preserveLineBreaks: true,
      }),
    ).toBe('"\'26052912345678\n26053087654321"');
  });
});
