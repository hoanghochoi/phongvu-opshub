import { UserAccessScopeService } from './user-access-scope.service';

describe('UserAccessScopeService', () => {
  function createHarness() {
    const prisma = { user: { count: jest.fn().mockResolvedValue(1) } };
    const runtime = {
      isScopedAdmin: jest.fn((admin: any) => admin.role === 'ADMIN'),
      effectiveWorkScope: jest.fn((admin: any) => admin.workScopeType),
      adminDomainScope: jest
        .fn()
        .mockResolvedValue({ email: { endsWith: '@phongvu.vn' } }),
      adminManagementScopeRootId: jest.fn().mockResolvedValue(null),
      userOrganizationNodeWhere: jest.fn().mockResolvedValue(null),
      combineUserScope: jest.fn((domain, location) => ({
        AND: [domain, location],
      })),
      adminOrgRootId: jest.fn().mockReturnValue('org-root'),
      adminStoreOrganizationScope: jest.fn().mockResolvedValue({
        organizationNodeId: { in: ['org-root', 'org-child'] },
      }),
      organizationDescendantIds: jest
        .fn()
        .mockImplementation(async (rootId: string) => [rootId, 'org-child']),
      combineStoreScope: jest.fn((organization, location) =>
        organization && location
          ? { AND: [organization, location] }
          : organization || location,
      ),
    };
    return {
      prisma,
      runtime,
      service: new UserAccessScopeService(prisma as any, runtime as any),
    };
  }

  it('keeps super-admin scope unbounded', async () => {
    const { service, runtime } = createHarness();
    await expect(
      service.adminScope({ role: 'SUPER_ADMIN', workScopeType: 'NATIONAL' }),
    ).resolves.toEqual({});
    expect(runtime.adminDomainScope).not.toHaveBeenCalled();
  });

  it('combines the domain and region scope for a scoped admin', async () => {
    const { service, runtime } = createHarness();
    const scope = await service.adminScope({
      role: 'ADMIN',
      workScopeType: 'REGION',
      regionCode: 'HCM',
    });
    expect(scope).toEqual({
      AND: [
        { email: { endsWith: '@phongvu.vn' } },
        {
          OR: [
            { regionCode: 'HCM' },
            { store: { area: { regionCode: 'HCM' } } },
          ],
        },
      ],
    });
    expect(runtime.combineUserScope).toHaveBeenCalled();
  });

  it('preserves direct store area matching for an area-scoped admin', async () => {
    const { service } = createHarness();
    await expect(
      service.adminScope({
        role: 'ADMIN',
        workScopeType: 'AREA',
        areaCode: 'HCM',
      }),
    ).resolves.toEqual({
      AND: [
        { email: { endsWith: '@phongvu.vn' } },
        {
          OR: [{ areaCode: 'HCM' }, { store: { areaCode: 'HCM' } }],
        },
      ],
    });
  });

  it('uses the organization subtree before location fallback', async () => {
    const { service, runtime } = createHarness();
    runtime.adminManagementScopeRootId.mockResolvedValue('org-manager');
    runtime.userOrganizationNodeWhere.mockResolvedValue({
      organizationNodeId: { in: ['org-manager'] },
    });
    await expect(
      service.adminScope({
        role: 'ADMIN',
        workScopeType: 'AREA',
        areaCode: 'HCM',
        organizationNodeId: 'org-position',
      }),
    ).resolves.toEqual({
      AND: [
        { email: { endsWith: '@phongvu.vn' } },
        { organizationNodeId: { in: ['org-manager'] } },
      ],
    });
  });

  it('checks user membership with the composed scope', async () => {
    const { service, prisma } = createHarness();
    await expect(
      service.userWithinAdminScope(
        { role: 'ADMIN', workScopeType: 'STORE', storeId: 'store-1' },
        { id: 'user-1' },
      ),
    ).resolves.toBe(true);
    expect(prisma.user.count).toHaveBeenCalledWith({
      where: {
        AND: [
          { id: 'user-1' },
          {
            AND: [
              { email: { endsWith: '@phongvu.vn' } },
              { storeId: 'store-1' },
            ],
          },
        ],
      },
    });
  });

  it('composes store search scope and protects store membership', async () => {
    const { service, runtime } = createHarness();
    const where = await service.adminStoreScope(
      { role: 'ADMIN', workScopeType: 'AREA', areaCode: 'HCM' },
      'CP',
    );
    expect(where).toEqual({
      AND: [
        {
          AND: [
            { organizationNodeId: { in: ['org-root', 'org-child'] } },
            { areaCode: 'HCM' },
          ],
        },
        {
          OR: [
            { storeId: { contains: 'CP', mode: 'insensitive' } },
            { storeName: { contains: 'CP', mode: 'insensitive' } },
            { transferAccountNumber: { contains: 'CP', mode: 'insensitive' } },
            { transferAccountName: { contains: 'CP', mode: 'insensitive' } },
            { transferBankName: { contains: 'CP', mode: 'insensitive' } },
            { mapVietinUsername: { contains: 'CP', mode: 'insensitive' } },
          ],
        },
      ],
    });
    expect(runtime.combineStoreScope).toHaveBeenCalled();
    await expect(
      service.storeWithinAdminScope(
        { role: 'ADMIN', workScopeType: 'NATIONAL' },
        { id: 'store-1', organizationNodeId: 'outside' },
      ),
    ).resolves.toBe(false);
  });
});
