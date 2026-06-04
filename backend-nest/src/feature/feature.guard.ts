import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FEATURE_KEY_METADATA } from './feature.decorator';
import { FeatureService } from './feature.service';

@Injectable()
export class FeatureGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly featureService: FeatureService,
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
    if (!allowed) {
      throw new ForbiddenException('Tính năng đang bị tắt cho phạm vi của bạn');
    }
    return true;
  }
}
