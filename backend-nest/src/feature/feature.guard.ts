import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FEATURE_KEY_METADATA } from './feature.decorator';
import { FeatureService } from './feature.service';

@Injectable()
export class FeatureGuard implements CanActivate {
  private readonly logger = new Logger(FeatureGuard.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly featureService: FeatureService,
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
    if (!allowed) {
      this.logger.warn(
        `Feature access denied: feature=${featureKeys.join('|')} userId=${request.user?.id ?? 'unknown'} role=${request.user?.role ?? 'unknown'}`,
      );
      throw new ForbiddenException('Tính năng đang bị tắt cho phạm vi của bạn');
    }
    return true;
  }
}
