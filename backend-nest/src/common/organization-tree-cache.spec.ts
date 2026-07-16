import {
  clearOrganizationTreeCache,
  getOrganizationTree,
} from './organization-tree-cache';

describe('organization tree cache', () => {
  it('deduplicates in-flight loads and reuses the short-lived result', async () => {
    let resolveLoad!: (value: any[]) => void;
    const load = new Promise<any[]>((resolve) => {
      resolveLoad = resolve;
    });
    const prisma = {
      organizationNode: { findMany: jest.fn().mockReturnValue(load) },
    };

    const first = getOrganizationTree(prisma);
    const second = getOrganizationTree(prisma);
    resolveLoad([{ id: 'node-1' }]);

    await expect(first).resolves.toEqual([{ id: 'node-1' }]);
    await expect(second).resolves.toEqual([{ id: 'node-1' }]);
    await expect(getOrganizationTree(prisma)).resolves.toEqual([
      { id: 'node-1' },
    ]);
    expect(prisma.organizationNode.findMany).toHaveBeenCalledTimes(1);
  });

  it('does not repopulate a stale generation after invalidation', async () => {
    let resolveFirst!: (value: any[]) => void;
    const firstLoad = new Promise<any[]>((resolve) => {
      resolveFirst = resolve;
    });
    const prisma = {
      organizationNode: {
        findMany: jest
          .fn()
          .mockReturnValueOnce(firstLoad)
          .mockResolvedValueOnce([{ id: 'node-new' }]),
      },
    };

    const stale = getOrganizationTree(prisma);
    clearOrganizationTreeCache(prisma);
    resolveFirst([{ id: 'node-old' }]);
    await stale;

    await expect(getOrganizationTree(prisma)).resolves.toEqual([
      { id: 'node-new' },
    ]);
    expect(prisma.organizationNode.findMany).toHaveBeenCalledTimes(2);
  });
});
