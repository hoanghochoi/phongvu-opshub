export const BIDV_OPERATING_MODES = [
  'STOPPED',
  'UAT_INGEST_ONLY',
  'LIVE',
] as const;

export type BidvOperatingMode = (typeof BIDV_OPERATING_MODES)[number];

export function modeFromLegacyControls(
  ingressEnabled: boolean,
  projectionEnabled: boolean,
): BidvOperatingMode {
  if (projectionEnabled && !ingressEnabled) {
    throw new Error('projection_requires_ingress');
  }
  if (projectionEnabled) return 'LIVE';
  if (ingressEnabled) return 'UAT_INGEST_ONLY';
  return 'STOPPED';
}

export function legacyControlsFromMode(mode: BidvOperatingMode) {
  return {
    ingressEnabled: mode !== 'STOPPED',
    projectionEnabled: mode === 'LIVE',
  };
}

export function normalizedOperatingMode(
  control: {
    operatingMode?: unknown;
    ingressEnabled?: unknown;
    projectionEnabled?: unknown;
  } | null,
): BidvOperatingMode {
  if (control && BIDV_OPERATING_MODES.includes(control.operatingMode as any)) {
    return control.operatingMode as BidvOperatingMode;
  }
  if (control?.projectionEnabled === true) return 'LIVE';
  if (control?.ingressEnabled === true) return 'UAT_INGEST_ONLY';
  return 'STOPPED';
}
