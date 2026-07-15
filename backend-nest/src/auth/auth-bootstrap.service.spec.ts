import { AuthBootstrapService } from './auth-bootstrap.service';

describe('AuthBootstrapService', () => {
  let service: AuthBootstrapService;
  let authService: { getUserData: jest.Mock };
  let featureService: { resolveFeatureAccessMap: jest.Mock };
  let policyService: { resolvePolicyAccessMap: jest.Mock };

  const authenticatedUser = {
    id: 'user-1',
    email: 'staff@phongvu-shop.vn',
    role: 'STAFF',
  };

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date('2026-07-15T02:00:00.000Z'));
    authService = {
      getUserData: jest.fn().mockResolvedValue({
        firstName: 'An',
        assignedStores: [{ storeId: 'CP01' }],
        profileCompletedAt: new Date('2026-07-01T01:02:03.000Z'),
      }),
    };
    featureService = {
      resolveFeatureAccessMap: jest.fn().mockResolvedValue({
        HOME_DASHBOARD: true,
        PAYMENT_MONITOR: false,
      }),
    };
    policyService = {
      resolvePolicyAccessMap: jest.fn().mockResolvedValue({
        ADMIN_SETTINGS: false,
      }),
    };
    service = new AuthBootstrapService(
      authService as any,
      featureService as any,
      policyService as any,
    );
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('combines the current user, feature access, policy access and capabilities', async () => {
    const result = await service.resolve(authenticatedUser);

    expect(authService.getUserData).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
    );
    expect(featureService.resolveFeatureAccessMap).toHaveBeenCalledWith(
      authenticatedUser,
    );
    expect(policyService.resolvePolicyAccessMap).toHaveBeenCalledWith(
      authenticatedUser,
    );
    expect(result.body).toEqual({
      schemaVersion: 1,
      generatedAt: '2026-07-15T02:00:00.000Z',
      version: expect.stringMatching(/^[a-f0-9]{64}$/),
      user: {
        firstName: 'An',
        assignedStores: [{ storeId: 'CP01' }],
        profileCompletedAt: new Date('2026-07-01T01:02:03.000Z'),
      },
      featureAccess: {
        HOME_DASHBOARD: true,
        PAYMENT_MONITOR: false,
      },
      policyAccess: { ADMIN_SETTINGS: false },
      capabilities: {
        conditionalGet: true,
        realtimeV2Topics: [
          'access.changed',
          'home.summary',
          'warranty',
          'payment.transactions',
          'payment.speaker',
          'payment.delivery-metrics',
          'notifications.statement-transfer',
          'notifications.offset-adjustment',
          'sales-report.orders',
        ],
      },
    });
    expect(result.etag).toBe(`"${result.body.version}"`);
  });

  it('keeps the version stable when object key order and generated time change', async () => {
    const first = await service.resolve(authenticatedUser);
    jest.setSystemTime(new Date('2026-07-15T03:00:00.000Z'));
    featureService.resolveFeatureAccessMap.mockResolvedValueOnce({
      PAYMENT_MONITOR: false,
      HOME_DASHBOARD: true,
    });

    const second = await service.resolve(authenticatedUser);

    expect(second.body.generatedAt).not.toBe(first.body.generatedAt);
    expect(second.body.version).toBe(first.body.version);
    expect(second.etag).toBe(first.etag);
  });

  it('changes the version when a serialized Date value changes', async () => {
    const first = await service.resolve(authenticatedUser);
    authService.getUserData.mockResolvedValueOnce({
      firstName: 'An',
      assignedStores: [{ storeId: 'CP01' }],
      profileCompletedAt: new Date('2026-07-02T01:02:03.000Z'),
    });

    const second = await service.resolve(authenticatedUser);

    expect(second.body.version).not.toBe(first.body.version);
  });

  it('matches strong, weak and wildcard If-None-Match values', () => {
    expect(service.matchesEtag('"version-1"', '"version-1"')).toBe(true);
    expect(service.matchesEtag('W/"version-1"', '"version-1"')).toBe(true);
    expect(service.matchesEtag('"old", W/"version-1"', '"version-1"')).toBe(
      true,
    );
    expect(service.matchesEtag('*', '"version-1"')).toBe(true);
    expect(service.matchesEtag('"old"', '"version-1"')).toBe(false);
  });
});
