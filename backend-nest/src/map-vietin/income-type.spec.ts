import {
  classifyMapVietinIncomeType,
  MAP_VIETIN_INCOME_TYPE,
  mapVietinIncomeTypeLabel,
} from './income-type';

describe('map vietin income type classifier', () => {
  it.each([
    'CT DEN:904T2670PSFCC8JN Nhat Tin Thanh toan tien Cod',
    'VNPAY TT 217344 PHONGVU DV CTT ngay 15.07.26',
    'ShopeePay MS 1607 1607 7844 79283',
    'Shopee WSS seller withdrawal 239915442796237214',
    'BC CN25 3-5.7.26___',
    'BC CTY 15.07.26___',
    'BC CP74 10-12.07.26___',
    'BC DKKD39 13.07.26___',
    'Giaohangtietkiem chuyen tien CoD 15.07.2026',
    'So GD goc: 10009876 TT GD qua vi Zalopay 15-07-2026',
    'Dieu tien tu dong',
  ])('classifies %s as partner/internal', (content) => {
    expect(classifyMapVietinIncomeType(content)).toBe(
      MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL,
    );
  });

  it('ignores whitespace in partner/internal markers', () => {
    expect(classifyMapVietinIncomeType('N H A T   T I N')).toBe(
      MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL,
    );
    expect(classifyMapVietinIncomeType('VNPAYTT 217 344')).toBe(
      MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL,
    );
  });

  it.each([
    'TNG CP69 NOP TIEN N 20.07.2026',
    'TNG CP55 NOP QUY NGAY 19.07.2026',
    'TNG-CP57 NOP TIEN NGAY 20/07/2026',
    'T N G CP61 NOP TIEN DEN NGAY 20.07.2026',
  ])('classifies content starting with TNG as partner/internal: %s', (content) => {
    expect(classifyMapVietinIncomeType(content)).toBe(
      MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL,
    );
  });

  it('does not classify TNG appearing after the content prefix', () => {
    expect(classifyMapVietinIncomeType('KHACH CHUYEN TIEN TNG CP61')).toBe(
      MAP_VIETIN_INCOME_TYPE.SALES,
    );
  });

  it.each([
    '8637988888',
    '0302607125',
    '113000179095',
    '110600994666',
    '1011103131001',
    '0071001142275',
    '117601180666',
  ])('classifies payer account %s as partner/internal', (payerAccount) => {
    expect(
      classifyMapVietinIncomeType('Khach chuyen tien', payerAccount),
    ).toBe(MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL);
  });

  it('ignores whitespace in payer accounts', () => {
    expect(
      classifyMapVietinIncomeType(
        'Khach chuyen tien',
        '113 000 179 095',
      ),
    ).toBe(MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL);
  });

  it.each([
    'So GD goc: 503220420102328 DVH TAIVIETINBANK',
    'VNPAY TT 999999 PHONGVU DV CTT ngay 15.07.26',
    'Nguoi gui 8637988888 nhung tai khoan gui khong co trong field payerAccount',
    'CT DEN:904D60713M9LLR5M THANH TOAN DH 26070839000000',
    '904D60709X434VMV KHACH HANG CHUYEN TIEN 26071312345678',
    '',
  ])('keeps sales content %s as sales', (content) => {
    expect(classifyMapVietinIncomeType(content)).toBe(
      MAP_VIETIN_INCOME_TYPE.SALES,
    );
  });

  it('maps labels for the product UI', () => {
    expect(mapVietinIncomeTypeLabel('PARTNER_INTERNAL')).toBe('Đối tác/Nội bộ');
    expect(mapVietinIncomeTypeLabel('SALES')).toBe('Bán hàng');
  });
});
