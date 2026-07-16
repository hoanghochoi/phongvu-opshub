import { FeatureController } from './feature.controller';

describe('FeatureController', () => {
  it('projects compatibility access from the shared auth context', async () => {
    const featureService = {
      resolveFeatureAccessMap: jest.fn(),
    };
    const authContextService = {
      getContext: jest
        .fn()
        .mockResolvedValue({ featureAccess: { HOME_DASHBOARD_SALES: true } }),
    };
    const controller = new FeatureController(
      featureService as any,
      authContextService as any,
    );
    const req = { user: { id: 'user-1' } };

    await expect(controller.getMyFeatures(req)).resolves.toEqual({
      HOME_DASHBOARD_SALES: true,
    });
    expect(authContextService.getContext).toHaveBeenCalledWith(req.user);
    expect(featureService.resolveFeatureAccessMap).not.toHaveBeenCalled();
  });

  it('keeps the legacy resolver fallback when context is unavailable', async () => {
    const featureService = {
      resolveFeatureAccessMap: jest.fn().mockResolvedValue({ HOME: true }),
    };
    const controller = new FeatureController(featureService as any);
    const req = { user: { id: 'user-1' } };

    await expect(controller.getMyFeatures(req)).resolves.toEqual({
      HOME: true,
    });
  });
});
