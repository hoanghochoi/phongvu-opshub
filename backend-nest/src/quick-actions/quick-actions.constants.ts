import { FEATURE_KEYS } from '../feature/feature.constants';

export const QUICK_ACTION_LINK_CODES = [
  'APP_DOWNLOAD',
  'CHECK_IN',
  'ZALO_OA',
  'GOOGLE_MAP',
] as const;

export type QuickActionLinkCode = (typeof QUICK_ACTION_LINK_CODES)[number];

export const QUICK_ACTION_LINK_FEATURES: Record<QuickActionLinkCode, string> = {
  APP_DOWNLOAD: FEATURE_KEYS.QUICK_ACTION_APP_DOWNLOAD,
  CHECK_IN: FEATURE_KEYS.QUICK_ACTION_CHECK_IN,
  ZALO_OA: FEATURE_KEYS.QUICK_ACTION_ZALO_OA,
  GOOGLE_MAP: FEATURE_KEYS.QUICK_ACTION_GOOGLE_MAP,
};
