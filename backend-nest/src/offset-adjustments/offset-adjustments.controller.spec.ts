import { OffsetAdjustmentsController } from './offset-adjustments.controller';
import { OffsetAdjustmentsService } from './offset-adjustments.service';

describe('OffsetAdjustmentsController', () => {
  it('routes batch completion to the service', async () => {
    const batchComplete = jest.fn().mockResolvedValue({ processedCount: 2 });
    const controller = new OffsetAdjustmentsController({
      batchComplete,
    } as unknown as OffsetAdjustmentsService);
    const user = { id: 'acc-1' };
    const body = { ids: ['offset-1', 'offset-2'] };

    await expect(controller.batchComplete({ user }, body)).resolves.toEqual({
      processedCount: 2,
    });
    expect(batchComplete).toHaveBeenCalledWith(user, body);
  });
});
