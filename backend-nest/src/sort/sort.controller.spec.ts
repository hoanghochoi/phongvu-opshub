import { SortController } from './sort.controller';

describe('SortController', () => {
  let controller: SortController;
  let sortService: {
    sort: jest.Mock;
    fifoCheck: jest.Mock;
    completionReport: jest.Mock;
  };

  beforeEach(() => {
    sortService = {
      sort: jest.fn(),
      fifoCheck: jest.fn(),
      completionReport: jest.fn(),
    };
    controller = new SortController(sortService as any);
  });

  it('sorts using the authenticated user email', async () => {
    sortService.sort.mockResolvedValue([{ sku: 'SKU1' }]);

    await expect(
      controller.sort(
        { user: { email: 'staff@phongvu-shop.vn' } },
        { text: 'SKU1' },
      ),
    ).resolves.toEqual([{ sku: 'SKU1' }]);
    expect(sortService.sort).toHaveBeenCalledWith('SKU1', 'staff@phongvu-shop.vn');
  });

  it('runs FIFO check with optional quantity', async () => {
    sortService.fifoCheck.mockResolvedValue([{ sku: 'SKU1' }]);

    await expect(
      controller.fifoCheck(
        { user: { email: 'staff@phongvu-shop.vn' } },
        { text: 'SKU1', qty: 2 },
      ),
    ).resolves.toEqual([{ sku: 'SKU1' }]);
    expect(sortService.fifoCheck).toHaveBeenCalledWith(
      'SKU1',
      2,
      'staff@phongvu-shop.vn',
    );
  });

  it('normalizes missing completion report items to an empty list', async () => {
    sortService.completionReport.mockResolvedValue({ status: 'success' });

    await expect(
      controller.completionReport(
        { user: { email: 'staff@phongvu-shop.vn' } },
        { sortedSKUs: undefined as any, timestamp: '2026-04-25T00:00:00.000Z' },
      ),
    ).resolves.toEqual({ status: 'success' });
    expect(sortService.completionReport).toHaveBeenCalledWith(
      [],
      'staff@phongvu-shop.vn',
      '2026-04-25T00:00:00.000Z',
    );
  });
});
