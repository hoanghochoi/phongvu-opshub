import { ForbiddenException } from '@nestjs/common';
import { SalesTargetsService } from './sales-targets.service';

describe('SalesTargetsService', () => {
  function createHarness() {
    const scopedStore = {
      storeId: 'CP01',
      storeName: 'Phong Vũ Quận 1',
      organizationNodeId: 'node-cp01',
    };
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          store: null,
          organizationNode: null,
          organizationAssignments: [
            {
              organizationNode: {
                id: 'area-hcm',
                stores: [],
                children: [
                  {
                    id: 'node-cp01',
                    stores: [scopedStore],
                    children: [],
                  },
                ],
              },
            },
          ],
        }),
      },
      store: { findMany: jest.fn().mockResolvedValue([scopedStore]) },
      salesTarget: {
        findMany: jest.fn().mockResolvedValue([
          {
            organizationNodeId: 'node-cp01',
            targetBeforeTax: BigInt(300000000),
            updatedAt: new Date('2026-07-05T00:00:00Z'),
          },
        ]),
        upsert: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      $transaction: jest.fn(async (writes: Promise<unknown>[]) =>
        Promise.all(writes),
      ),
    };
    return {
      service: new SalesTargetsService(prisma as any),
      prisma,
    };
  }

  it('lists only SR stores in the assigned organization subtree', async () => {
    const { service, prisma } = createHarness();

    await expect(
      service.list({ id: 'manager-1', role: 'USER' }, '2026-07'),
    ).resolves.toMatchObject({
      month: '2026-07',
      items: [
        {
          organizationNodeId: 'node-cp01',
          storeCode: 'CP01',
          targetBeforeTax: 300000000,
        },
      ],
    });
    expect(prisma.user.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'manager-1' } }),
    );
  });

  it('updates targets inside scope and records the editor', async () => {
    const { service, prisma } = createHarness();

    await service.updateBatch(
      { id: 'manager-1', email: 'manager@phongvu.vn', role: 'USER' },
      {
        month: '2026-07',
        targets: [
          { organizationNodeId: 'node-cp01', targetBeforeTax: 320000000 },
        ],
      },
    );

    expect(prisma.salesTarget.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          organizationNodeId: 'node-cp01',
          targetBeforeTax: BigInt(320000000),
          updatedByUserId: 'manager-1',
        }),
      }),
    );
  });

  it('rejects updates for SR stores outside the assigned subtree', async () => {
    const { service, prisma } = createHarness();

    await expect(
      service.updateBatch(
        { id: 'manager-1', role: 'USER' },
        {
          month: '2026-07',
          targets: [
            { organizationNodeId: 'node-cp99', targetBeforeTax: 100000000 },
          ],
        },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.salesTarget.upsert).not.toHaveBeenCalled();
  });
});
