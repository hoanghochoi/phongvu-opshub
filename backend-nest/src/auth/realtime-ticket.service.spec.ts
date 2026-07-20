import { ForbiddenException } from '@nestjs/common';
import { RealtimeTicketService } from './realtime-ticket.service';

describe('RealtimeTicketService', () => {
  const user = {
    id: 'user-1',
    email: 'staff@phongvu.vn',
    role: 'USER',
    status: 'yes',
    tokenVersion: 3,
    departmentCode: 'SALES',
    organizationNodeId: 'node-cp01',
    store: { storeId: 'CP01' },
    organizationAssignments: [{ organizationNodeId: 'node-cp01' }],
  };
  const authenticatedUser = {
    id: 'user-1',
    authSession: {
      sessionId: 'session-1',
      sessionVersion: 2,
      platform: 'windows',
    },
  };
  const nodes = [
    {
      id: 'root',
      parentId: null,
      code: 'ORG_PV',
      businessCode: null,
      isActive: true,
      stores: [],
    },
    {
      id: 'node-cp01',
      parentId: 'root',
      code: 'STORE_CP01',
      businessCode: 'CP01',
      isActive: true,
      stores: [{ storeId: 'CP01' }],
    },
  ];

  function setup() {
    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue(user) },
      organizationNode: { findMany: jest.fn().mockResolvedValue(nodes) },
    };
    const redis = { setJsonWithTtl: jest.fn().mockResolvedValue(undefined) };
    const featureService = {
      resolveFeatureAccessMap: jest
        .fn()
        .mockResolvedValue({ WARRANTY: true, FEEDBACK: false }),
      canAccessFeature: jest.fn().mockResolvedValue(false),
    };
    const policyService = {
      resolvePolicyAccessMap: jest.fn().mockResolvedValue({}),
    };
    return {
      service: new RealtimeTicketService(
        prisma as any,
        redis as any,
        featureService as any,
        policyService as any,
      ),
      prisma,
      redis,
      featureService,
      policyService,
    };
  }

  it('stores only the ticket hash with a bounded TTL and sanitized claims', async () => {
    const { service, redis } = setup();

    const result = await service.issueTicket(authenticatedUser, 'cp01');

    expect(result.ticket).toMatch(/^[A-Za-z0-9_-]{40,}$/);
    expect(result.expiresInSeconds).toBe(45);
    expect(redis.setJsonWithTtl).toHaveBeenCalledTimes(1);
    const [key, payload, ttl] = redis.setJsonWithTtl.mock.calls[0];
    expect(key).toMatch(/^opshub:realtime:ticket:[a-f0-9]{64}$/);
    expect(key).not.toContain(result.ticket);
    expect(payload).toMatchObject({
      version: 1,
      audience: 'opshub-realtime',
      userId: 'user-1',
      storeCode: 'CP01',
      organizationAccessCodes: ['CP01', 'ORG_PV', 'SALES', 'STORE_CP01'],
      policyCodes: [],
      featureCodes: ['WARRANTY'],
      sessionId: 'session-1',
      sessionVersion: 2,
      tokenVersion: 3,
    });
    expect(JSON.stringify(payload)).not.toContain(result.ticket);
    expect(ttl).toBe(45);
  });

  it('blocks a caller-selected store outside the server-resolved scope', async () => {
    const { service, redis } = setup();

    await expect(
      service.issueTicket(authenticatedUser, 'CP99'),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(redis.setJsonWithTtl).not.toHaveBeenCalled();
  });

  it('reconciles PAYMENT_SPEAKER with the direct HTTP authorization predicate', async () => {
    const { service, redis, featureService } = setup();
    featureService.resolveFeatureAccessMap.mockResolvedValue({
      WARRANTY: true,
      PAYMENT_SPEAKER: false,
    });
    featureService.canAccessFeature.mockResolvedValue(true);

    await service.issueTicket(authenticatedUser, 'CP01');

    expect(featureService.canAccessFeature).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'user-1' }),
      'PAYMENT_SPEAKER',
    );
    expect(redis.setJsonWithTtl.mock.calls[0][1].featureCodes).toEqual([
      'PAYMENT_SPEAKER',
      'WARRANTY',
    ]);
  });

  it('removes a stale PAYMENT_SPEAKER claim when direct authorization denies it', async () => {
    const { service, redis, featureService } = setup();
    featureService.resolveFeatureAccessMap.mockResolvedValue({
      PAYMENT_SPEAKER: true,
      WARRANTY: true,
    });
    featureService.canAccessFeature.mockResolvedValue(false);

    await service.issueTicket(authenticatedUser, 'CP01');

    expect(redis.setJsonWithTtl.mock.calls[0][1].featureCodes).toEqual([
      'WARRANTY',
    ]);
  });

  it('does not advertise disabled features from policy-only access', async () => {
    const { service, redis, featureService, policyService } = setup();
    featureService.resolveFeatureAccessMap.mockResolvedValue({
      BANK_STATEMENTS: false,
      OFFSET_ADJUSTMENTS: false,
    });
    policyService.resolvePolicyAccessMap.mockResolvedValue({
      BANK_STATEMENT_ALL_SCOPE: true,
      OFFSET_ADJUSTMENTS: true,
    });

    await service.issueTicket(authenticatedUser, 'CP01');

    expect(redis.setJsonWithTtl.mock.calls[0][1].featureCodes).toEqual([]);
    expect(redis.setJsonWithTtl.mock.calls[0][1].policyCodes).toEqual([]);
  });

  it('adds only granted finance and payment all-scope markers to the ticket', async () => {
    const { service, redis, policyService } = setup();
    policyService.resolvePolicyAccessMap.mockResolvedValue({
      PAYMENT_MONITOR_ALL_SCOPE: true,
      BANK_STATEMENT_ALL_SCOPE: false,
    });

    await service.issueTicket(authenticatedUser);

    expect(redis.setJsonWithTtl.mock.calls[0][1]).toMatchObject({
      organizationAccessCodes: ['CP01', 'ORG_PV', 'SALES', 'STORE_CP01'],
      policyCodes: ['PAYMENT_MONITOR_ALL_SCOPE'],
    });
    expect(redis.setJsonWithTtl.mock.calls[0][1].featureCodes).toEqual([
      'WARRANTY',
    ]);
  });

  it('keeps an explicitly selected store narrow for an all-scope user', async () => {
    const { service, redis, policyService } = setup();
    policyService.resolvePolicyAccessMap.mockResolvedValue({
      PAYMENT_MONITOR_ALL_SCOPE: true,
      BANK_STATEMENT_ALL_SCOPE: true,
    });

    await service.issueTicket(authenticatedUser, 'CP01');

    expect(redis.setJsonWithTtl.mock.calls[0][1]).toMatchObject({
      storeCode: 'CP01',
      organizationAccessCodes: ['CP01', 'ORG_PV', 'SALES', 'STORE_CP01'],
      policyCodes: [],
    });
  });

  it('does not turn a colliding organization code into an all-scope policy', async () => {
    const { service, prisma, redis } = setup();
    prisma.user.findUnique.mockResolvedValue({
      ...user,
      departmentCode: 'PAYMENT_MONITOR_ALL_SCOPE',
    });

    await service.issueTicket(authenticatedUser);

    expect(
      redis.setJsonWithTtl.mock.calls[0][1].organizationAccessCodes,
    ).toContain('PAYMENT_MONITOR_ALL_SCOPE');
    expect(redis.setJsonWithTtl.mock.calls[0][1].policyCodes).toEqual([]);
  });

  it('allows a super administrator to request an explicit store without expanding normal users', async () => {
    const { service, prisma, redis } = setup();
    prisma.user.findUnique.mockResolvedValue({
      ...user,
      role: 'SUPER_ADMIN',
      organizationNodeId: null,
      organizationAssignments: [],
      store: null,
    });

    const result = await service.issueTicket(authenticatedUser, 'CP99');

    expect(result.ticket).toBeTruthy();
    expect(redis.setJsonWithTtl.mock.calls[0][1].storeCode).toBe('CP99');
  });

  it('keeps a super administrator ticket unscoped unless a store is requested', async () => {
    const { service, prisma, redis } = setup();
    prisma.user.findUnique.mockResolvedValue({
      ...user,
      role: 'SUPER_ADMIN',
    });

    await service.issueTicket(authenticatedUser);

    expect(redis.setJsonWithTtl.mock.calls[0][1].storeCode).toBeNull();
  });
});
