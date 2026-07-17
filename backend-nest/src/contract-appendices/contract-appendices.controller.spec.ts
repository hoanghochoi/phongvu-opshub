import { FEATURE_KEY_METADATA } from '../feature/feature.decorator';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { ContractAppendicesController } from './contract-appendices.controller';

describe('ContractAppendicesController', () => {
  it('guards every route with the contract appendix feature', () => {
    expect(
      Reflect.getMetadata(FEATURE_KEY_METADATA, ContractAppendicesController),
    ).toBe(FEATURE_KEYS.CONTRACT_APPENDIX);
  });

  it('passes the authenticated user to list and detail', async () => {
    const service = {
      list: jest.fn().mockResolvedValue({ items: [] }),
      detail: jest.fn().mockResolvedValue({ id: 'appendix-1' }),
    };
    const controller = new ContractAppendicesController(service as any);
    const req = { user: { id: 'user-1' } };
    await controller.list(req, { page: 0, limit: 20 });
    await controller.detail(req, 'appendix-1');
    expect(service.list).toHaveBeenCalledWith(req.user, {
      page: 0,
      limit: 20,
    });
    expect(service.detail).toHaveBeenCalledWith(req.user, 'appendix-1');
  });
});
