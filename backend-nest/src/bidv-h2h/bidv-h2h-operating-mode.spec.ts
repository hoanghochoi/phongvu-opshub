import {
  legacyControlsFromMode,
  modeFromLegacyControls,
  normalizedOperatingMode,
} from './bidv-h2h-operating-mode';

describe('BIDV operating mode compatibility', () => {
  it.each([
    ['STOPPED', false, false],
    ['UAT_INGEST_ONLY', true, false],
    ['LIVE', true, true],
  ] as const)('maps %s to its legacy pair', (mode, ingress, projection) => {
    expect(legacyControlsFromMode(mode)).toEqual({
      ingressEnabled: ingress,
      projectionEnabled: projection,
    });
    expect(modeFromLegacyControls(ingress, projection)).toBe(mode);
  });

  it('rejects the unsafe legacy projection-only pair', () => {
    expect(() => modeFromLegacyControls(false, true)).toThrow(
      'projection_requires_ingress',
    );
  });

  it('prefers the persisted mode while accepting legacy records', () => {
    expect(
      normalizedOperatingMode({
        operatingMode: 'STOPPED',
        ingressEnabled: true,
        projectionEnabled: true,
      }),
    ).toBe('STOPPED');
    expect(normalizedOperatingMode({ projectionEnabled: true })).toBe('LIVE');
  });
});
