import { BidvH2hParser } from './bidv-h2h-parser';

describe('BidvH2hParser', () => {
  const parser = new BidvH2hParser();
  const row = {
    accountNo: '000012345678',
    amount: '125000.000000',
    currency: 'VND',
    transDate: '300726',
    transTime: '101804',
    dorc: 'C',
    seq: '4235',
    refNo: 'REF-4235',
    remark: 'THANH TOAN DON HANG CP69 BOT',
    frBankCode: '01202001',
    frAccName: 'NGUYEN VAN A',
    frAccNo: '000098765432',
    frBankName: 'BIDV',
    endBal: '2697940292.25',
    channelRef: 'CHANNEL-1',
    channelID: '113',
    businessDate: '300726',
    toBankCode: null,
    toAccName: null,
    toAccNo: null,
    toBankName: null,
    va: 'BIDV-VIRTUAL-ACCOUNT',
    transCode: 'DD',
    ext1: null,
    ext2: 'two',
    ext3: null,
    ext4: null,
    ext5: null,
  };

  it('parses all 28 revision 1.3 fields with Vietnam time', () => {
    const [parsed] = parser.parsePayload(JSON.stringify([row]), 100);
    expect(parsed.amount.toString()).toBe('125000');
    expect(parsed.endBal?.toString()).toBe('2697940292.25');
    expect(parsed.paidAt.toISOString()).toBe('2026-07-30T03:18:04.000Z');
    expect(parsed.businessDateValue.toISOString()).toBe(
      '2026-07-30T00:00:00.000Z',
    );
    expect(parsed.showroomCodeHint).toBe('CP69');
    expect(parsed.extensions.ext2).toBe('two');
    expect(parsed.identityHash).toHaveLength(64);
  });

  it('fails the complete payload for unknown, invalid or oversized data', () => {
    expect(() =>
      parser.parsePayload(JSON.stringify([{ ...row, surprise: true }]), 100),
    ).toThrow('trường chưa được hỗ trợ');
    expect(() =>
      parser.parsePayload(
        JSON.stringify([row, { ...row, transDate: '310226' }]),
        100,
      ),
    ).toThrow('transDate');
    expect(() => parser.parsePayload(JSON.stringify([row, row]), 1)).toThrow(
      'vượt giới hạn',
    );
  });

  it('extracts only the exact remark suffix candidate', () => {
    expect(parser.showroomCodeFromRemark('THANH TOAN CP123 BOT')).toBe('CP123');
    expect(parser.showroomCodeFromRemark('THANH TOAN CP69')).toBe('CP69');
    expect(parser.showroomCodeFromRemark('THANH TOAN CP69 BOT THEM')).toBe(
      'THEM',
    );
    expect(parser.showroomCodeFromRemark('THANH TOAN CP69.')).toBeNull();
    const [withoutRemarkSuffix] = parser.parsePayload(
      JSON.stringify([
        {
          ...row,
          remark: 'THANH TOAN DON HANG.',
          va: 'BIDV-CP69',
        },
      ]),
      100,
    );
    expect(withoutRemarkSuffix.showroomCodeHint).toBeNull();
  });
});
