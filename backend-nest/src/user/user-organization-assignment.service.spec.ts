import { UserOrganizationAssignmentService } from './user-organization-assignment.service';

describe('UserOrganizationAssignmentService', () => {
  it('writes deactivation and primary assignment changes through the explicit transaction client', async () => {
    const rootAssignment = {
      updateMany: jest.fn(),
      upsert: jest.fn(),
    };
    const transactionAssignment = {
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      upsert: jest.fn().mockResolvedValue(undefined),
    };
    const logger = { log: jest.fn(), warn: jest.fn() };
    const service = new UserOrganizationAssignmentService(
      { userOrganizationAssignment: rootAssignment } as any,
      { logger } as any,
    );
    const tx = {
      userOrganizationAssignment: transactionAssignment,
    };

    await (service.syncUserOrganizationAssignments as any)(
      tx,
      'user-1',
      ['node-1', 'node-2'],
      { id: 'admin-1' },
    );

    expect(rootAssignment.updateMany).not.toHaveBeenCalled();
    expect(rootAssignment.upsert).not.toHaveBeenCalled();
    expect(transactionAssignment.updateMany).toHaveBeenCalledWith({
      where: {
        userId: 'user-1',
        organizationNodeId: { notIn: ['node-1', 'node-2'] },
      },
      data: { isActive: false, isPrimary: false },
    });
    expect(transactionAssignment.upsert).toHaveBeenNthCalledWith(1, {
      where: {
        userId_organizationNodeId: {
          userId: 'user-1',
          organizationNodeId: 'node-1',
        },
      },
      create: {
        userId: 'user-1',
        organizationNodeId: 'node-1',
        isPrimary: true,
        isActive: true,
        assignedById: 'admin-1',
        note: 'Admin user assignment',
      },
      update: {
        isPrimary: true,
        isActive: true,
        assignedById: 'admin-1',
      },
    });
    expect(transactionAssignment.upsert).toHaveBeenNthCalledWith(2, {
      where: {
        userId_organizationNodeId: {
          userId: 'user-1',
          organizationNodeId: 'node-2',
        },
      },
      create: {
        userId: 'user-1',
        organizationNodeId: 'node-2',
        isPrimary: false,
        isActive: true,
        assignedById: 'admin-1',
        note: 'Admin user assignment',
      },
      update: {
        isPrimary: false,
        isActive: true,
        assignedById: 'admin-1',
      },
    });
    expect(logger.log).toHaveBeenCalledWith(
      'User organization assignments synced: userId=user-1 count=2',
    );
  });
});
