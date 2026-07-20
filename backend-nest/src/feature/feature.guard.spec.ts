import { ForbiddenException } from '@nestjs/common';
import { FEATURE_KEYS } from './feature.constants';
import { FeatureGuard } from './feature.guard';

describe('FeatureGuard', () => {
  const requestUser = { id: 'finance-1', role: 'USER' };
  const executionContext = {
    getHandler: jest.fn(),
    getClass: jest.fn(),
    switchToHttp: jest.fn(() => ({
      getRequest: () => ({ user: requestUser }),
    })),
  } as any;

  function createGuard({
    featureAllowed = false,
    featureKey = FEATURE_KEYS.BANK_STATEMENTS,
    allowedFeatureKey,
  }: {
    featureAllowed?: boolean;
    featureKey?: string | string[];
    allowedFeatureKey?: string;
  }) {
    const reflector = {
      getAllAndOverride: jest.fn(() => featureKey),
    };
    const featureService = {
      canAccessFeature: jest.fn(async (_user: any, key: string) =>
        allowedFeatureKey ? key === allowedFeatureKey : featureAllowed,
      ),
    };
    const guard = new FeatureGuard(reflector as any, featureService as any);
    return { guard, featureService };
  }

  it('denies feature routes when only a policy is allowed', async () => {
    const { guard, featureService } = createGuard({
      featureAllowed: false,
    });

    await expect(guard.canActivate(executionContext)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(featureService.canAccessFeature).toHaveBeenCalledWith(
      requestUser,
      FEATURE_KEYS.BANK_STATEMENTS,
    );
  });

  it('allows offset adjustment routes when the feature is enabled', async () => {
    const { guard } = createGuard({
      featureAllowed: true,
      featureKey: FEATURE_KEYS.OFFSET_ADJUSTMENTS,
    });

    await expect(guard.canActivate(executionContext)).resolves.toBe(true);
  });

  it('allows routes that accept any one of multiple feature keys', async () => {
    const { guard, featureService } = createGuard({
      featureAllowed: false,
      featureKey: [FEATURE_KEYS.SALES_REPORT, FEATURE_KEYS.ADMIN_SALES_REPORTS],
      allowedFeatureKey: FEATURE_KEYS.ADMIN_SALES_REPORTS,
    });

    await expect(guard.canActivate(executionContext)).resolves.toBe(true);
    expect(featureService.canAccessFeature).toHaveBeenCalledWith(
      requestUser,
      FEATURE_KEYS.SALES_REPORT,
    );
    expect(featureService.canAccessFeature).toHaveBeenCalledWith(
      requestUser,
      FEATURE_KEYS.ADMIN_SALES_REPORTS,
    );
  });
});
