import { BadRequestException } from '@nestjs/common';
import { UserService } from './user.service';

describe('UserService.prepareAdminUserMutation', () => {
  let service: UserService;
  let resolutions: {
    assertEmailCreatableByAdmin: jest.SpyInstance;
    resolveAssignableRole: jest.SpyInstance;
    assertRoleEditable: jest.SpyInstance;
    resolveUserOrganizationAssignmentNodeIds: jest.SpyInstance;
    resolveWorkScopeTypeForAssignment: jest.SpyInstance;
    resolveUserAssignmentStoreUuid: jest.SpyInstance;
    resolvePersonnelAssignment: jest.SpyInstance;
  };

  const admin = {
    id: 'admin-1',
    email: 'admin@phongvu.vn',
    role: 'SUPER_ADMIN',
  };

  beforeEach(() => {
    process.env.DATA_SYNC_SOURCE = 'local';
    const prisma = {};
    const policyService = {
      canAccessPolicy: jest.fn().mockResolvedValue(true),
      getAllowedEmailDomains: jest.fn().mockResolvedValue(['phongvu.vn']),
    };
    service = new UserService(
      prisma as any,
      {} as any,
      {} as any,
      policyService as any,
      {} as any,
      undefined,
    );

    resolutions = {
      assertEmailCreatableByAdmin: jest
        .spyOn(service as any, 'assertEmailCreatableByAdmin')
        .mockResolvedValue(undefined),
      resolveAssignableRole: jest
        .spyOn(service as any, 'resolveAssignableRole')
        .mockImplementation(async (value: string) => value),
      assertRoleEditable: jest
        .spyOn(service as any, 'assertRoleEditable')
        .mockResolvedValue(undefined),
      resolveUserOrganizationAssignmentNodeIds: jest
        .spyOn(service as any, 'resolveUserOrganizationAssignmentNodeIds')
        .mockResolvedValue(['node-1', 'node-2']),
      resolveWorkScopeTypeForAssignment: jest
        .spyOn(service as any, 'resolveWorkScopeTypeForAssignment')
        .mockResolvedValue('STORE'),
      resolveUserAssignmentStoreUuid: jest
        .spyOn(service as any, 'resolveUserAssignmentStoreUuid')
        .mockResolvedValue('store-1'),
      resolvePersonnelAssignment: jest
        .spyOn(service as any, 'resolvePersonnelAssignment')
        .mockResolvedValue({
          departmentCode: 'SALES',
          jobRoleCode: 'SELLER',
          regionCode: 'MIEN_NAM',
          areaCode: 'HCM',
          organizationNodeId: 'node-1',
          workScopeType: 'STORE',
        }),
    };
  });

  async function prepare(body: any, current: any | null = null) {
    return (service as any).prepareAdminUserMutation(admin, body, current);
  }

  it('normalizes a create, resolves the primary organization node and builds both payload shapes', async () => {
    const body = {
      email: ' New@PhongVu.VN ',
      firstName: ' Nguyen ',
      lastName: ' Van A ',
      status: 'NO',
      organizationNodeIds: ['node-1', 'node-2'],
    };

    const result = await prepare(body);

    expect(result.email).toBe('new@phongvu.vn');
    expect(result.role).toBe('USER');
    expect(result.workScopeType).toBe('STORE');
    expect(result.organizationNodeIds).toEqual(['node-1', 'node-2']);
    expect(result.personnel).toEqual(
      expect.objectContaining({
        departmentCode: 'SALES',
        jobRoleCode: 'SELLER',
        regionCode: 'MIEN_NAM',
        areaCode: 'HCM',
        organizationNodeId: 'node-1',
        workScopeType: 'STORE',
      }),
    );
    expect(result.createData).toEqual(
      expect.objectContaining({
        email: 'new@phongvu.vn',
        password: '',
        firstName: 'Nguyen',
        lastName: 'Van A',
        role: 'USER',
        status: 'no',
        workScopeType: 'STORE',
        store: { connect: { id: 'store-1' } },
        department: { connect: { code: 'SALES' } },
        jobRole: { connect: { code: 'SELLER' } },
        region: { connect: { code: 'MIEN_NAM' } },
        area: { connect: { code: 'HCM' } },
        organizationNode: { connect: { id: 'node-1' } },
        branchLockedAt: expect.any(Date),
        profileCompletedAt: expect.any(Date),
      }),
    );
    expect(result.updateData).toEqual(
      expect.objectContaining({
        firstName: 'Nguyen',
        lastName: 'Van A',
        role: 'USER',
        status: 'no',
        workScopeType: 'STORE',
        store: { connect: { id: 'store-1' } },
        organizationNode: { connect: { id: 'node-1' } },
        branchLockedAt: expect.any(Date),
        profileCompletedAt: expect.any(Date),
      }),
    );

    expect(resolutions.resolveAssignableRole).toHaveBeenCalledWith('USER');
    expect(resolutions.assertEmailCreatableByAdmin).toHaveBeenCalledWith(
      admin,
      'new@phongvu.vn',
    );
    expect(
      resolutions.resolveUserOrganizationAssignmentNodeIds,
    ).toHaveBeenCalledWith(admin, body, null);
    expect(resolutions.resolveWorkScopeTypeForAssignment).toHaveBeenCalledWith(
      { ...body, organizationNodeId: 'node-1' },
      null,
      'USER',
    );
    expect(resolutions.resolveUserAssignmentStoreUuid).toHaveBeenCalledWith(
      admin,
      { ...body, organizationNodeId: 'node-1' },
      { current: null, workScopeType: 'STORE' },
    );
    expect(resolutions.resolvePersonnelAssignment).toHaveBeenCalledWith(
      admin,
      { ...body, organizationNodeId: 'node-1' },
      {
        current: null,
        role: 'USER',
        storeUuid: 'store-1',
        workScopeType: 'STORE',
      },
    );
  });

  it('preserves update-only fields and existing branch/profile timestamps', async () => {
    const branchLockedAt = new Date('2025-01-02T03:04:05.000Z');
    const profileCompletedAt = new Date('2025-01-03T03:04:05.000Z');
    const current = {
      id: 'user-1',
      email: 'STAFF@PHONGVU.VN',
      firstName: 'Old',
      lastName: 'Name',
      role: 'STAFF',
      status: 'yes',
      branchLockedAt,
      profileCompletedAt,
    };
    const body = {
      firstName: ' New ',
      organizationNodeIds: ['node-1'],
    };

    const result = await prepare(body, current);

    expect(result.email).toBe('staff@phongvu.vn');
    expect(result.role).toBe('USER');
    expect(resolutions.resolveAssignableRole).not.toHaveBeenCalled();
    expect(resolutions.assertEmailCreatableByAdmin).not.toHaveBeenCalled();
    expect(resolutions.assertRoleEditable).toHaveBeenCalledWith(
      admin,
      'USER',
      'STAFF',
    );
    expect(result.updateData).toEqual(
      expect.objectContaining({
        firstName: 'New',
        lastName: 'Name',
        role: 'USER',
        status: 'yes',
        workScopeType: 'STORE',
        branchLockedAt,
        profileCompletedAt,
      }),
    );
  });

  it('keeps callback ordering authorization -> role -> organization -> scope -> store -> personnel', async () => {
    const order: string[] = [];
    for (const [name, spy] of Object.entries(resolutions)) {
      spy.mockImplementationOnce(async (...args: any[]) => {
        order.push(name);
        if (name === 'resolveAssignableRole') return args[0];
        if (name === 'resolveUserOrganizationAssignmentNodeIds') {
          return ['node-1'];
        }
        if (name === 'resolveWorkScopeTypeForAssignment') return 'STORE';
        if (name === 'resolveUserAssignmentStoreUuid') return 'store-1';
        if (name === 'resolvePersonnelAssignment') {
          return { organizationNodeId: 'node-1', workScopeType: 'STORE' };
        }
        return undefined;
      });
    }

    await prepare({ email: 'new@phongvu.vn' });

    expect(order).toEqual([
      'assertEmailCreatableByAdmin',
      'resolveAssignableRole',
      'assertRoleEditable',
      'resolveUserOrganizationAssignmentNodeIds',
      'resolveWorkScopeTypeForAssignment',
      'resolveUserAssignmentStoreUuid',
      'resolvePersonnelAssignment',
    ]);
  });

  it('rejects invalid email before any role or assignment resolution', async () => {
    await expect(prepare({ email: 'not-an-email' })).rejects.toEqual(
      new BadRequestException('Email không hợp lệ'),
    );

    expect(resolutions.assertEmailCreatableByAdmin).not.toHaveBeenCalled();
    expect(resolutions.resolveAssignableRole).not.toHaveBeenCalled();
    expect(
      resolutions.resolveUserOrganizationAssignmentNodeIds,
    ).not.toHaveBeenCalled();
    expect(resolutions.resolvePersonnelAssignment).not.toHaveBeenCalled();
  });
});
