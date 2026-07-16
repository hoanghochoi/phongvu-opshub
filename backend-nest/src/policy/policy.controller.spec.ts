import { PolicyController } from './policy.controller';

describe('PolicyController', () => {
  it('projects compatibility access from the shared auth context', async () => {
    const policyService = {
      resolvePolicyAccessMap: jest.fn(),
    };
    const authContextService = {
      getContext: jest
        .fn()
        .mockResolvedValue({ policyAccess: { ADMIN_USERS: true } }),
    };
    const controller = new PolicyController(
      policyService as any,
      authContextService as any,
    );
    const req = { user: { id: 'user-1' } };

    await expect(controller.getMyPolicies(req)).resolves.toEqual({
      ADMIN_USERS: true,
    });
    expect(authContextService.getContext).toHaveBeenCalledWith(req.user);
    expect(policyService.resolvePolicyAccessMap).not.toHaveBeenCalled();
  });

  it('keeps the legacy resolver fallback when context is unavailable', async () => {
    const policyService = {
      resolvePolicyAccessMap: jest.fn().mockResolvedValue({ REPORT: true }),
    };
    const controller = new PolicyController(policyService as any);
    const req = { user: { id: 'user-1' } };

    await expect(controller.getMyPolicies(req)).resolves.toEqual({
      REPORT: true,
    });
  });
});
