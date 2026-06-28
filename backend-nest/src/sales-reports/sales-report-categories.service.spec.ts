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
