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

  it('matches the Listing product group code to the OpsHub category group', async () => {
    const service = createService();

    const category = await service.matchCategoryFromErp(['NH08', '80283']);

    expect(category).toEqual(
      expect.objectContaining({
        id: 'NH08',
        catGroupName: 'Network and Security equipment',
        catGroupNameVi: 'Thiết bị mạng và an ninh',
      }),
    );
  });

  it('matches multiple Listing product group codes to OpsHub category groups', async () => {
    const service = createService();

    const categories = await service.matchCategoriesFromErp([
      'NH03',
      'NH08',
      'RAM DDR5',
      'Thiết bị mạng/ Router TPLink Archer C54',
    ]);

    expect(categories.map((category) => category.id)).toEqual(
      expect.arrayContaining(['NH03', 'NH08']),
    );
  });

  it('maps product type from the highest Listing category level', async () => {
    const service = createService();

    const type = await service.matchTypeFromListingCategories([
      { code: 'NH05', name: 'Apple', level: 1 },
      { code: 'NH05-03-05', name: 'Apple watch', level: 2 },
      { code: 'NH05-02-01-01', name: 'Iphone', level: 3 },
    ]);

    expect(type).toBe('apple');
  });

  it('does not infer a type from an ambiguous category group only', async () => {
    const service = createService();

    const type = await service.matchTypeFromListingCategories([], ['NH03']);

    expect(type).toBeNull();
  });

  it('falls back to network router listing names when code is missing', async () => {
    const service = createService();

    const category = await service.matchCategoryFromErp([
      '80283',
      'Thiết bị mạng/ Router TPLink Archer C54',
      'Sản phẩm có thể lưu trữ',
    ]);

    expect(category).toEqual(
      expect.objectContaining({
        id: 'NH08',
        catGroupName: 'Network and Security equipment',
        catGroupNameVi: 'Thiết bị mạng và an ninh',
      }),
    );
  });

  it('does not force a category when listing values are unrelated', async () => {
    const service = createService();

    await expect(
      service.matchCategoryFromErp(['Mã nhóm lạ', 'Sản phẩm không khớp']),
    ).resolves.toBeNull();
  });
});
