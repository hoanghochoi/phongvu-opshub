import { SalesReportCategoriesService } from './sales-report-categories.service';

describe('SalesReportCategoriesService', () => {
  function createService() {
    const prisma = {
      salesReportCategoryGroup: {
        upsert: jest.fn(({ create }: any) => Promise.resolve(create)),
      },
      $transaction: jest.fn((items: Array<Promise<unknown>>) =>
        Promise.all(items),
      ),
    };
    return new SalesReportCategoriesService(prisma as any);
  }

  it('maps product type from the deepest Listing category level', async () => {
    const service = createService();

    const type = await service.matchTypeFromListingCategories([
      { code: 'NH05', name: 'Apple', level: 1 },
      { code: 'NH05-03-05', name: 'Apple watch', level: 2 },
      { code: 'NH05-02-01-01', name: 'Iphone', level: 3 },
    ]);

    expect(type).toBe('apple');
  });

  it('maps the NH11 gift leaf to gift instead of accessories', async () => {
    const service = createService();

    const match = await service.matchDeepestListingCategory([
      { code: 'NH11', name: 'Accessories', level: 1 },
      {
        code: 'NH11-01-98',
        name: 'Quà tặng phụ kiện máy tính',
        level: 3,
      },
      {
        code: 'NH11-01-98-01',
        name: 'Linh kiện (Quà tặng phụ kiện máy tính)',
        level: 4,
      },
    ]);

    expect(match).toMatchObject({
      categoryType: 'gift',
      categoryGroup: { id: 'NH11' },
      sourceLevel: 4,
    });
  });

  it('does not use a level-1 NHxx category as an autofill signal', async () => {
    const service = createService();

    const type = await service.matchTypeFromListingCategories([
      { code: 'NH03', name: 'Computer components', level: 1 },
    ]);

    expect(type).toBeNull();
  });

  it('does not fall back to a known parent when the deepest node is unknown', async () => {
    const service = createService();

    const match = await service.matchDeepestListingCategory([
      { code: 'NH11', name: 'Accessories', level: 1 },
      { code: 'UNKNOWN-LEAF', name: 'Nhóm chưa có trong CSV', level: 4 },
    ]);

    expect(match).toBeNull();
  });

  it('does not infer category level from array order when level is missing', async () => {
    const service = createService();

    const match = await service.matchDeepestListingCategory([
      { code: 'NH01', name: 'Laptop' },
      { code: 'NH01-01-01-01', name: 'Laptop' },
    ]);

    expect(match).toBeNull();
  });

  it('uses the deepest exact row even when Listing categories are out of order', async () => {
    const service = createService();

    const match = await service.matchDeepestListingCategory([
      {
        code: 'NH05-96-01-01',
        name: 'Củ sạc Apple',
        level: 4,
      },
      { code: 'NH05', name: 'Apple', level: 1 },
    ]);

    expect(match).toMatchObject({
      categoryType: 'accessories',
      categoryGroup: { id: 'NH05' },
      sourceLevel: 4,
    });
  });

  it('provides an immutable exact-ID snapshot with deepest then Subcat 2 fallback', async () => {
    const service = createService();

    const snapshot = await service.exactCategoryTypeSnapshot();

    expect(Object.isFrozen(snapshot)).toBe(true);
    expect(snapshot.lookup('nh03-01-01-01', 'NH03-01-02')).toBe('cpu');
    expect(snapshot.lookup('', 'nh03-01-02')).toBe('mainboard');
    expect(snapshot.lookup('UNKNOWN', 'NH03-01-02')).toBe('mainboard');
    expect(snapshot.lookup('NH03-01-01-01 extra', 'UNKNOWN')).toBeNull();
  });

  it('fails closed when a fallback Subcat 2 ID has conflicting exact types', async () => {
    const service = createService();

    const snapshot = await service.exactCategoryTypeSnapshot();

    expect(snapshot.lookup('', 'NH06-96-02')).toBeNull();
  });
});
