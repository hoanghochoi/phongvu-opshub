import { SetMetadata } from '@nestjs/common';

export const FEATURE_KEY_METADATA = 'opshub:featureKey';

export const RequireFeature = (featureKey: string | string[]) =>
  SetMetadata(FEATURE_KEY_METADATA, featureKey);
