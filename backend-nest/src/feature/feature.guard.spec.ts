import { ForbiddenException } from '@nestjs/common';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
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
    policyAllowed = false,
    featureKey = FEATURE_KEYS.BANK_STATEMENTS,
    allowedFeatureKey,
  }: {
    featureAllowed?: boolean;
    policyAllowed?: boolean;
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
    const policyService = {
      canAccessPolicy: jest.fn(async (_user: any, code: string) => {
        if (code === ADMIN_POLICY_CODES.OFFSET_ADJUSTMENTS) {
          return policyAllowed;
        }
        return (
          code === ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE && policyAllowed
        );
      }),
    };
    const guard = new FeatureGuard(
      reflector as any,
      featureService as any,
      policyService as any,
    );
    return { guard, featureService, policyService };
  }

  it('allows bank statement routes when all-scope policy is allowed', async () => {
    const { guard, featureService, policyService } = createGuard({
      featureAllowed: false,
      policyAllowed: true,
    });

    await expect(guard.canActivate(executionContext)).resolves.toBe(true);
    expect(featureService.canAccessFeature).toHaveBeenCalledWith(
      requestUser,
      FEATURE_KEYS.BANK_STATEMENTS,
    );
    expect(policyService.canAccessPolicy).toHaveBeenCalledWith(
      requestUser,
      ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
    );
  });

  it('still denies bank statement routes without feature or all-scope policy', async () => {
    const { guard } = createGuard({
      featureAllowed: false,
      policyAllowed: false,
    });

    await expect(guard.canActivate(executionContext)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('allows offset adjustment routes when offset policy is allowed', async () => {
    const { guard, policyService } = createGuard({
      featureAllowed: false,
      policyAllowed: true,
      featureKey: FEATURE_KEYS.OFFSET_ADJUSTMENTS,
    });

    await expect(guard.canActivate(executionContext)).resolves.toBe(true);
    expect(policyService.canAccessPolicy).toHaveBeenCalledWith(
      requestUser,
      ADMIN_POLICY_CODES.OFFSET_ADJUSTMENTS,
    );
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
