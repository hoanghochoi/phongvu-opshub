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
    const featureKey = this.reflector.getAllAndOverride<string>(
      FEATURE_KEY_METADATA,
      [context.getHandler(), context.getClass()],
    );
    if (!featureKey) return true;

    const request = context.switchToHttp().getRequest();
    const allowed = await this.featureService.canAccessFeature(
      request.user,
      featureKey,
    );
    if (
      !allowed &&
      (await this.canAccessByPolicyFallback(request.user, featureKey))
    ) {
      this.logger.log(
        `Feature access allowed by policy fallback: feature=${featureKey} userId=${request.user?.id ?? 'unknown'} role=${request.user?.role ?? 'unknown'}`,
      );
      return true;
    }
    if (!allowed) {
      this.logger.warn(
        `Feature access denied: feature=${featureKey} userId=${request.user?.id ?? 'unknown'} role=${request.user?.role ?? 'unknown'}`,
      );
      throw new ForbiddenException('Tính năng đang bị tắt cho phạm vi của bạn');
    }
    return true;
  }

  private async canAccessByPolicyFallback(user: any, featureKey: string) {
    const policyCodes = FEATURE_POLICY_FALLBACKS[featureKey] || [];
    for (const policyCode of policyCodes) {
      if (await this.policyService.canAccessPolicy(user, policyCode)) {
        return true;
      }
    }
    return false;
  }
}
