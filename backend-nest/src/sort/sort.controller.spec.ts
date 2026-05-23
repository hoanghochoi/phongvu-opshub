import { SortController } from './sort.controller';

describe('SortController', () => {
  let controller: SortController;
  let sortService: {
    sort: jest.Mock;
    fifoCheck: jest.Mock;
    completionReport: jest.Mock;
  };
  let fifoService: {
    sort: jest.Mock;
    check: jest.Mock;
  };

  beforeEach(() => {
    sortService = {
      sort: jest.fn(),
      fifoCheck: jest.fn(),
      completionReport: jest.fn(),
    };
    fifoService = {
      sort: jest.fn(),
      check: jest.fn(),
    };
    controller = new SortController(sortService as any, fifoService as any);
  });

  it('sorts using the authenticated user email', async () => {
    fifoService.sort.mockResolvedValue([{ sku: 'SKU1' }]);

    await expect(
      controller.sort(
        { user: { email: 'staff@phongvu-shop.vn' } },
        { text: 'SKU1' },
      ),
    ).resolves.toEqual([{ sku: 'SKU1' }]);
    expect(fifoService.sort).toHaveBeenCalledWith(
      { email: 'staff@phongvu-shop.vn' },
      { text: 'SKU1' },
    );
    expect(sortService.sort).not.toHaveBeenCalled();
  });

  it('runs FIFO check with optional quantity', async () => {
    fifoService.check.mockResolvedValue([{ sku: 'SKU1' }]);

    await expect(
      controller.fifoCheck(
        { user: { email: 'staff@phongvu-shop.vn' } },
        { text: 'SKU1', qty: 2 },
      ),
    ).resolves.toEqual([{ sku: 'SKU1' }]);
    expect(fifoService.check).toHaveBeenCalledWith(
      { email: 'staff@phongvu-shop.vn' },
      { text: 'SKU1', includeExported: false },
    );
    expect(sortService.fifoCheck).not.toHaveBeenCalled();
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
