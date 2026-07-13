import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { QuickActionsService } from './quick-actions.service';

describe('QuickActionsService', () => {
  const manager = {
    id: 'manager-1',
    role: 'USER',
    email: 'manager@example.com',
  };

  function createService() {
    const prisma: any = {
      user: { findUnique: jest.fn() },
      store: { findMany: jest.fn() },
      quickActionLink: {
        findMany: jest.fn(),
        upsert: jest.fn((args) => ({ kind: 'upsert', args })),
        deleteMany: jest.fn((args) => ({ kind: 'deleteMany', args })),
      },
      $transaction: jest.fn(async () => []),
    };
    const features: any = { canAccessFeature: jest.fn(async () => true) };
    return {
      prisma,
      features,
      service: new QuickActionsService(prisma, features),
    };
  }

  const scopedUser = (jobRoleCode = 'STORE_MANAGER') => ({
    jobRoleCode,
    store: {
      storeId: 'HCM01',
      storeName: 'Showroom 1',
      organizationNodeId: 'node-1',
    },
    organizationNode: null,
    organizationAssignments: [],
  });

  it('denies configuration when a regular employee receives the feature by mistake', async () => {
    const { prisma, service } = createService();
    prisma.user.findUnique
      .mockResolvedValueOnce(scopedUser('SALES_STAFF'))
      .mockResolvedValueOnce({ jobRoleCode: 'SALES_STAFF' });

    await expect(service.getManagedStores(manager)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('rejects non-http links before starting the transaction', async () => {
    const { prisma, service } = createService();
    prisma.user.findUnique
      .mockResolvedValueOnce(scopedUser())
      .mockResolvedValueOnce({ jobRoleCode: 'STORE_MANAGER' });

    await expect(
      service.updateAdminLinks(manager, 'HCM01', {
        APP_DOWNLOAD: 'javascript:alert(1)',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('upserts configured values and deletes blank values atomically', async () => {
    const { prisma, service } = createService();
    prisma.user.findUnique
      .mockResolvedValueOnce(scopedUser())
      .mockResolvedValueOnce({ jobRoleCode: 'STORE_MANAGER' })
      .mockResolvedValueOnce(scopedUser())
      .mockResolvedValueOnce({ jobRoleCode: 'STORE_MANAGER' });
    prisma.quickActionLink.findMany.mockResolvedValue([]);

    await service.updateAdminLinks(manager, 'HCM01', {
      APP_DOWNLOAD: 'https://example.com/app',
      CHECK_IN: '',
      ZALO_OA: null,
      GOOGLE_MAP: 'https://maps.example.com/store',
    });

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    const writes = prisma.$transaction.mock.calls[0][0];
    expect(writes).toHaveLength(4);
    expect(writes.filter((write: any) => write.kind === 'upsert')).toHaveLength(
      2,
    );
    expect(
      writes.filter((write: any) => write.kind === 'deleteMany'),
    ).toHaveLength(2);
  });

  it('rejects a showroom outside the assigned scope', async () => {
    const { prisma, service } = createService();
    prisma.user.findUnique
      .mockResolvedValueOnce(scopedUser())
      .mockResolvedValueOnce({ jobRoleCode: 'STORE_MANAGER' });

    await expect(
      service.updateAdminLinks(manager, 'HN99', {}),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });
});
