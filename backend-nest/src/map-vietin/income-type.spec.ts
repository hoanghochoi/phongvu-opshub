import {
  classifyMapVietinIncomeType,
  MAP_VIETIN_INCOME_TYPE,
  mapVietinIncomeTypeLabel,
} from './income-type';

describe('map vietin income type classifier', () => {
  it.each([
    'BC CN25 3-5.7.26___',
    'BC CP74 10-12.07.26___',
    'So GD goc: 503220420102328 DVH TAIVIETINBANK',
    'Shopee WSS seller withdrawal 239915442796237214',
    'CT DEN:904T2670PSFCC8JN Nhat Tin Thanh toan tien Cod',
    'Giaohangtietkiem chuyen tien CoD 15.07.2026',
    'VNPAY TT 217344 PHONGVU DV CTT ngay 15.07.26',
  ])('classifies %s as partner/internal', (content) => {
    expect(classifyMapVietinIncomeType(content)).toBe(
      MAP_VIETIN_INCOME_TYPE.PARTNER_INTERNAL,
    );
  });

  it.each([
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
