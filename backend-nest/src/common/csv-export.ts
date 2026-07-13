const CSV_FORMULA_PREFIX = /^[\u0000-\u0020]*[=+\-@]/;

export function csvValue(value: unknown): string {
  return value === null || value === undefined ? '' : String(value);
}

export function csvCell(value: unknown): string {
  const text = neutralizeSpreadsheetFormula(csvValue(value));
  if (!/[",\r\n]/.test(text)) return text;
  return `"${text.replace(/"/g, '""')}"`;
}

export function csvExcelTextCell(
  value: unknown,
  options: { preserveLineBreaks?: boolean } = {},
): string {
  const text = csvValue(value);
  if (!text) return '';
  const normalized = options.preserveLineBreaks
    ? text.replace(/\r\n?/g, '\n')
    : text.replace(/[\r\n]+/g, ' ');

  // A leading apostrophe asks spreadsheet applications to keep identifiers as
  // text without executing a formula. It replaces the legacy ="..." formula.
  return csvCell(`'${normalized}`);
}

export function neutralizeSpreadsheetFormula(value: string): string {
  return CSV_FORMULA_PREFIX.test(value) ? `'${value}` : value;
}
