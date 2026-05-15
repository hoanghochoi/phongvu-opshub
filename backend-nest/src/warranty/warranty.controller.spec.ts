import { WarrantyController } from './warranty.controller';

describe('WarrantyController', () => {
  let controller: WarrantyController;
  let warrantyService: {
    createWarranty: jest.Mock;
    getAllWarranties: jest.Mock;
    searchByReceipt: jest.Mock;
    getByReceipt: jest.Mock;
    getWarrantyById: jest.Mock;
    updateWarrantyStatus: jest.Mock;
  };

  beforeEach(() => {
    warrantyService = {
      createWarranty: jest.fn(),
      getAllWarranties: jest.fn(),
      searchByReceipt: jest.fn(),
      getByReceipt: jest.fn(),
      getWarrantyById: jest.fn(),
      updateWarrantyStatus: jest.fn(),
    };
    controller = new WarrantyController(warrantyService as any);
  });

  it('creates warranty records for the authenticated user', async () => {
    const body = { receipt: 'CP01-J12345678' };
    warrantyService.createWarranty.mockResolvedValue({ id: 'warranty-1' });

    await expect(
      controller.create({ user: { id: 'user-1' } }, body),
    ).resolves.toEqual({ id: 'warranty-1' });
    expect(warrantyService.createWarranty).toHaveBeenCalledWith('user-1', body);
  });

  it('searches warranties with an empty string fallback', async () => {
    warrantyService.searchByReceipt.mockResolvedValue([]);

    await expect(controller.search(undefined as any)).resolves.toEqual([]);
    expect(warrantyService.searchByReceipt).toHaveBeenCalledWith('');
  });

  it('updates warranty status with handler id', async () => {
    warrantyService.updateWarrantyStatus.mockResolvedValue({ status: 'DONE' });

    await expect(
      controller.updateStatus({ user: { id: 'handler-1' } }, 'warranty-1', {
        status: 'DONE',
      }),
    ).resolves.toEqual({ status: 'DONE' });
    expect(warrantyService.updateWarrantyStatus).toHaveBeenCalledWith(
      'warranty-1',
      'handler-1',
      'DONE',
    );
  });
});
