import { readFileSync } from 'fs';
import { resolve } from 'path';
import { FeatureService } from '../feature/feature.service';
import { PolicyService } from '../policy/policy.service';
import { AuthBootstrapService } from './auth-bootstrap.service';
import { AuthService } from './auth.service';

type AuthBootstrapV1Fixture = {
  schemaVersion: number;
  generatedAt: string;
  version: string;
  user: Record<string, unknown>;
  featureAccess: Record<string, boolean>;
  policyAccess: Record<string, boolean>;
  capabilities: {
    conditionalGet: boolean;
    realtimeV2Topics: string[];
  };
};

function loadAuthBootstrapV1Fixture(): AuthBootstrapV1Fixture {
  const parsed: unknown = JSON.parse(
    readFileSync(
      resolve(
        process.cwd(),
        '..',
        'test',
        'fixtures',
        'auth_bootstrap_v1.json',
      ),
      'utf8',
    ),
  );
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('Shared auth bootstrap fixture must be a JSON object');
  }
  return parsed as AuthBootstrapV1Fixture;
}

const authBootstrapV1Fixture = loadAuthBootstrapV1Fixture();

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
      authService as unknown as AuthService,
      featureService as unknown as FeatureService,
      policyService as unknown as PolicyService,
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
      version: result.body.version,
      user: {
        firstName: 'An',
        assignedStores: [{ storeId: 'CP01' }],
        profileCompletedAt: new Date('2026-07-01T01:02:03.000Z'),
        id: 'user-1',
        email: 'staff@phongvu-shop.vn',
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
          'quick-actions.links',
        ],
      },
    });
    expect(result.body.version).toMatch(/^[a-f0-9]{64}$/);
    expect(result.etag).toBe(`"${result.body.version}"`);
  });

  it('rejects a bootstrap snapshot when authenticated identity is incomplete', async () => {
    await expect(
      service.resolve({ id: 'user-1', email: '   ' }),
    ).rejects.toMatchObject({ status: 401 });
  });

  it('serializes the shared bootstrap v1 contract fixture', async () => {
    const result = await service.resolve(authenticatedUser);
    const serialized: unknown = JSON.parse(
      JSON.stringify({
        ...result.body,
        version: authBootstrapV1Fixture.version,
      }),
    );

    expect(serialized).toEqual(authBootstrapV1Fixture);
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
