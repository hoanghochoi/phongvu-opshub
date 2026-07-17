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
] as const;

const GROUP_UNITS = [
  '',
  'nghìn',
  'triệu',
  'tỷ',
  'nghìn tỷ',
  'triệu tỷ',
] as const;

/**
 * Đọc một số tiền VND nguyên, không kèm tên đơn vị.
 *
 * Hàm chủ động từ chối số âm, số thập phân và số vượt giới hạn an toàn của
 * JavaScript để tiền hiển thị không thể bị sai do mất độ chính xác.
 */
export function vietnameseAmountWords(amount: number): string {
  if (!Number.isSafeInteger(amount) || amount < 0) {
    throw new RangeError('Số tiền phải là số nguyên VND không âm hợp lệ.');
  }
  if (amount === 0) return DIGITS[0];

  const groups: number[] = [];
  let remaining = amount;
  while (remaining > 0) {
    groups.push(remaining % 1000);
    remaining = Math.floor(remaining / 1000);
  }
  if (groups.length > GROUP_UNITS.length) {
    throw new RangeError('Số tiền vượt giới hạn hỗ trợ.');
  }

  const words: string[] = [];
  for (let index = groups.length - 1; index >= 0; index -= 1) {
    const group = groups[index];
    if (group === 0) continue;
    const readFull = index < groups.length - 1;
    words.push(
      [readThreeDigits(group, readFull), GROUP_UNITS[index]]
        .filter(Boolean)
        .join(' '),
    );
  }
  return words.join(' ').replace(/\s+/g, ' ').trim();
}

export function vietnameseContractAmountWords(amount: number): string {
  const words = vietnameseAmountWords(amount);
  return `${words.charAt(0).toUpperCase()}${words.slice(1)} đồng chẵn.`;
}

function readThreeDigits(value: number, readFull: boolean): string {
  const hundred = Math.floor(value / 100);
  const ten = Math.floor((value % 100) / 10);
  const one = value % 10;
  const words: string[] = [];

  if (hundred > 0 || readFull) words.push(DIGITS[hundred], 'trăm');

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
    words.push(DIGITS[one]);
  }

  return words.join(' ');
}
