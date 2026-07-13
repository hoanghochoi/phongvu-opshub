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
    };
    return {
      service: new RealtimeTicketService(
        prisma as any,
        redis as any,
        featureService as any,
      ),
      prisma,
      redis,
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
});
