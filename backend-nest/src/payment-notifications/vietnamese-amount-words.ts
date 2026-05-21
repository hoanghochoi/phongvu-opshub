const DIGITS = [
  'không',
  'một',
  'hai',
  'ba',
  'bốn',
  'năm',
  'sáu',
  'bảy',
  'tám',
  'chín',
];

const UNITS = ['', 'nghìn', 'triệu', 'tỷ'];

export function vietnameseAmountWords(amount: number): string {
  const value = Math.trunc(Math.abs(amount));
  if (value === 0) return DIGITS[0];

  const groups: number[] = [];
  let remaining = value;
  while (remaining > 0) {
    groups.push(remaining % 1000);
    remaining = Math.floor(remaining / 1000);
  }

  const words: string[] = [];
  for (let index = groups.length - 1; index >= 0; index -= 1) {
    const group = groups[index];
    if (group === 0) continue;
    const readFull = index < groups.length - 1;
    const groupWords = readThreeDigits(group, readFull);
    const unit = UNITS[index] ?? '';
    words.push([groupWords, unit].filter(Boolean).join(' '));
  }
  return words.join(' ').replace(/\s+/g, ' ').trim();
}

function readThreeDigits(value: number, readFull: boolean): string {
  const hundred = Math.floor(value / 100);
  const ten = Math.floor((value % 100) / 10);
  const one = value % 10;
  const words: string[] = [];

  if (hundred > 0 || readFull) {
    words.push(DIGITS[hundred], 'trăm');
  }

  if (ten > 1) {
    words.push(DIGITS[ten], 'mươi');
    if (one === 1) words.push('mốt');
    else if (one === 5) words.push('lăm');
    else if (one > 0) words.push(DIGITS[one]);
  } else if (ten === 1) {
    words.push('mười');
    if (one === 5) words.push('lăm');
    else if (one > 0) words.push(DIGITS[one]);
  } else if (one > 0) {
    if (hundred > 0 || readFull) words.push('lẻ');
    words.push(one === 5 && (hundred > 0 || readFull) ? 'năm' : DIGITS[one]);
  }

  return words.join(' ');
}
