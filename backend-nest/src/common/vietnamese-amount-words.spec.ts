import {
  vietnameseAmountWords,
  vietnameseContractAmountWords,
} from './vietnamese-amount-words';

describe('Vietnamese amount words', () => {
  it.each([
    [0, 'không'],
    [15, 'mười lăm'],
    [21, 'hai mươi mốt'],
    [24, 'hai mươi bốn'],
    [25, 'hai mươi lăm'],
    [105, 'một trăm lẻ năm'],
    [1_005_000, 'một triệu không trăm lẻ năm nghìn'],
    [55_180_000, 'năm mươi lăm triệu một trăm tám mươi nghìn'],
  ])('reads %d', (amount, expected) => {
    expect(vietnameseAmountWords(amount)).toBe(expected);
  });

  it('formats a contract sentence', () => {
    expect(vietnameseContractAmountWords(55_180_000)).toBe(
      'Năm mươi lăm triệu một trăm tám mươi nghìn đồng chẵn.',
    );
  });

  it.each([-1, 1.5, Number.MAX_SAFE_INTEGER + 1])(
    'rejects unsafe amount %s',
    (amount) => {
      expect(() => vietnameseAmountWords(amount)).toThrow(RangeError);
    },
  );
});
