import { FeatureService } from './feature.service';

describe('FeatureService', () => {
  let service: FeatureService;
  let prisma: any;
  let featureActive: boolean;
  let rules: any[];

  const area = {
    code: 'HCM',
    abbreviation: 'HCM',
    regionCode: 'MIEN_NAM',
    region: { code: 'MIEN_NAM', abbreviation: 'MN' },
  };
  const storeUser = {
    id: 'user-1',
    role: 'STAFF',
    departmentCode: 'SALES',
    jobRoleCode: 'SALE',
    workScopeType: 'STORE',
    store: { storeId: 'CP62', storeName: 'CP62', area },
  };

  beforeEach(() => {
    featureActive = true;
    rules = [];
    prisma = {
      featureDefinition: {
        upsert: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(async () => ({ isActive: featureActive })),
      },
      featureAccessRule: {
        findMany: jest.fn(async () => rules),
      },
      user: {
        findUnique: jest.fn(async ({ where }: any) => {
          if (where.id === 'user-1') return storeUser;
          return null;
        }),
      },
    };
    service = new FeatureService(prisma);
  });

  it('keeps legacy access when no feature rule matches', async () => {
    await expect(service.canAccessFeature({ id: 'user-1' }, 'FIFO')).resolves.toBe(true);
    await expect(
      service.canAccessFeature({ ...storeUser, role: 'STAFF' }, 'BANK_STATEMENTS'),
    ).resolves.toBe(false);
  });

  it('applies explicit deny at API gate level', async () => {
    rules = [{ featureCode: 'FIFO', enabled: false }];

    await expect(service.canAccessFeature({ id: 'user-1' }, 'FIFO')).resolves.toBe(false);
  });

  it('lets a more specific allow override a broader deny', async () => {
    rules = [
      { featureCode: 'FIFO', enabled: false },
      { featureCode: 'FIFO', enabled: true, areaCode: 'HCM' },
    ];

    await expect(service.canAccessFeature({ id: 'user-1' }, 'FIFO')).resolves.toBe(true);
  });

  it('does not let feature rules grant access beyond legacy authorization', async () => {
    rules = [{ featureCode: 'BANK_STATEMENTS', enabled: true, userId: 'user-1' }];

    await expect(
      service.canAccessFeature({ id: 'user-1' }, 'BANK_STATEMENTS'),
    ).resolves.toBe(false);
  });

  it('resolves STORE-scope feature context from the assigned SR area', async () => {
    const staleRegion = { code: 'MIEN_CU', abbreviation: 'MC' };
    const staleArea = {
      code: 'VUNG_CU',
      abbreviation: 'VC',
      regionCode: staleRegion.code,
      region: staleRegion,
    };
    prisma.user.findUnique.mockResolvedValueOnce({
      ...storeUser,
      regionCode: staleRegion.code,
      areaCode: staleArea.code,
      region: staleRegion,
      area: staleArea,
    });
    rules = [{ featureCode: 'FIFO', enabled: false, regionCode: staleRegion.code }];

    await expect(service.canAccessFeature({ id: 'user-1' }, 'FIFO')).resolves.toBe(true);
  });

  it('makes disabled win when top matching rules have the same specificity', async () => {
    rules = [
      { featureCode: 'FIFO', enabled: true, areaCode: 'HCM' },
      { featureCode: 'FIFO', enabled: false, areaCode: 'HCM' },
    ];

    await expect(service.canAccessFeature({ id: 'user-1' }, 'FIFO')).resolves.toBe(false);
  });

  it('always bypasses feature gates for super admin', async () => {
    featureActive = false;
    rules = [{ featureCode: 'ADMIN_FEATURES', enabled: false }];

    await expect(
      service.canAccessFeature({ role: 'SUPER_ADMIN' }, 'ADMIN_FEATURES'),
    ).resolves.toBe(true);
  });
});
