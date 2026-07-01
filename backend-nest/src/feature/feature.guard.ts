import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';
import { PolicyService } from '../policy/policy.service';
import { FEATURE_KEY_METADATA } from './feature.decorator';
import { FEATURE_KEYS } from './feature.constants';
import { FeatureService } from './feature.service';

const FEATURE_POLICY_FALLBACKS: Partial<Record<string, string[]>> = {
  [FEATURE_KEYS.BANK_STATEMENTS]: [ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE],
  [FEATURE_KEYS.OFFSET_ADJUSTMENTS]: [ADMIN_POLICY_CODES.OFFSET_ADJUSTMENTS],
};

@Injectable()
export class FeatureGuard implements CanActivate {
  private readonly logger = new Logger(FeatureGuard.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly featureService: FeatureService,
    private readonly policyService: PolicyService,
  ) {}

  async canActivate(context: ExecutionContext) {
    const featureKey = this.reflector.getAllAndOverride<string | string[]>(
      FEATURE_KEY_METADATA,
      [context.getHandler(), context.getClass()],
    );
    if (!featureKey) return true;

    const request = context.switchToHttp().getRequest();
    const featureKeys = Array.isArray(featureKey) ? featureKey : [featureKey];
    let allowed = false;
    for (const key of featureKeys) {
      if (await this.featureService.canAccessFeature(request.user, key)) {
        allowed = true;
        break;
      }
    }
    if (
      !allowed &&
      (await this.canAccessByPolicyFallback(request.user, featureKeys))
    ) {
      this.logger.log(
        `Feature access allowed by policy fallback: feature=${featureKeys.join('|')} userId=${request.user?.id ?? 'unknown'} role=${request.user?.role ?? 'unknown'}`,
      );
      return true;
    }
    if (!allowed) {
      this.logger.warn(
        `Feature access denied: feature=${featureKeys.join('|')} userId=${request.user?.id ?? 'unknown'} role=${request.user?.role ?? 'unknown'}`,
      );
      throw new ForbiddenException('Tính năng đang bị tắt cho phạm vi của bạn');
    }
    return true;
  }

  private async canAccessByPolicyFallback(user: any, featureKeys: string[]) {
    for (const featureKey of featureKeys) {
      const policyCodes = FEATURE_POLICY_FALLBACKS[featureKey] || [];
      for (const policyCode of policyCodes) {
        if (await this.policyService.canAccessPolicy(user, policyCode)) {
          return true;
        }
      }
    }
    return false;
  }
}
