import { AccessChangeService } from './access-change.service';

describe('AccessChangeService', () => {
  let service: AccessChangeService;
  let prisma: any;
  let redis: any;

  beforeEach(() => {
    prisma = {
      organizationNode: { findMany: jest.fn().mockResolvedValue([]) },
      user: {
        findMany: jest.fn().mockResolvedValue([]),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };
    redis = {
      publishMessageOrThrow: jest.fn().mockResolvedValue(undefined),
    };
    service = new AccessChangeService(prisma, redis);
  });

  it('publishes a strict recipient-scoped ACCESS_CHANGED envelope', async () => {
    await expect(
      service.publishForUserIds(
        ['user-1', ' user-1 ', 'user-2'],
        'Feature Assignment Updated',
      ),
    ).resolves.toEqual({
      recipientCount: 2,
      eventCount: 1,
      failedEventCount: 0,
    });

    expect(redis.publishMessageOrThrow).toHaveBeenCalledWith(
      'ACCESS_CHANGED',
      expect.objectContaining({
        schemaVersion: 1,
        type: 'ACCESS_CHANGED',
        eventId: expect.any(String),
        occurredAt: expect.any(String),
        audience: expect.objectContaining({
          recipientUserIds: ['user-1', 'user-2'],
        }),
        payload: { reason: 'feature-assignment-updated' },
      }),
    );
    expect(prisma.user.updateMany).not.toHaveBeenCalled();
  });

  it('resolves users from descendant and alternate organization assignments', async () => {
    prisma.organizationNode.findMany.mockResolvedValue([
      { id: 'root', parentId: null },
      { id: 'area-1', parentId: 'root' },
      { id: 'store-1', parentId: 'area-1' },
      { id: 'other', parentId: null },
    ]);
    prisma.user.findMany.mockResolvedValue([{ id: 'user-1' }]);

    await service.publishForOrganizationNodeIds(
      ['area-1'],
      'policy-rule-updated',
    );

    expect(prisma.user.findMany).toHaveBeenCalledWith({
      where: {
        OR: [
          { organizationNodeId: { in: ['area-1', 'store-1'] } },
          {
            organizationAssignments: {
              some: {
                isActive: true,
                organizationNodeId: { in: ['area-1', 'store-1'] },
              },
            },
          },
        ],
      },
      select: { id: true },
    });
    expect(redis.publishMessageOrThrow).toHaveBeenCalledTimes(1);
  });

  it('keeps the completed admin mutation successful when Redis is unavailable', async () => {
    redis.publishMessageOrThrow.mockRejectedValue(
      new Error('redis unavailable'),
    );

    await expect(
      service.publishForUserIds(['user-1'], 'user-access-updated'),
    ).resolves.toEqual({
      recipientCount: 1,
      eventCount: 1,
      failedEventCount: 1,
    });
  });

  it('keeps the completed admin mutation successful when recipient lookup fails', async () => {
    prisma.organizationNode.findMany.mockRejectedValue(
      new Error('database unavailable'),
    );

    await expect(
      service.publishForOrganizationNodeIds(
        ['node-1'],
        'organization-node-updated',
      ),
    ).resolves.toEqual({
      recipientCount: 0,
      eventCount: 0,
      failedLookupCount: 1,
    });
    expect(redis.publishMessageOrThrow).not.toHaveBeenCalled();
  });

  it('keeps all-user invalidation best-effort when its lookup fails', async () => {
    prisma.user.findMany.mockRejectedValue(new Error('database unavailable'));

    await expect(
      service.publishForAllUsers('personnel-catalog-updated'),
    ).resolves.toEqual({
      recipientCount: 0,
      eventCount: 0,
      failedLookupCount: 1,
    });
    expect(redis.publishMessageOrThrow).not.toHaveBeenCalled();
  });

  it('skips Redis when no recipient is impacted', async () => {
    await expect(
      service.publishForOrganizationNodeIds([], 'feature-assignment-updated'),
    ).resolves.toEqual({ recipientCount: 0, eventCount: 0 });
    expect(redis.publishMessageOrThrow).not.toHaveBeenCalled();
  });
});
