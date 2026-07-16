type OrganizationTreeNode = {
  id: string;
  parentId: string | null;
  code: string;
  businessCode: string | null;
  type: string;
  displayName: string;
  abbreviation: string | null;
  isActive: boolean;
  stores: Array<{ storeId: string; storeName?: string | null }>;
};

type CacheEntry = {
  expiresAt: number;
  nodes: OrganizationTreeNode[];
};

const TTL_MS = 30_000;
const cacheByPrisma = new WeakMap<object, CacheEntry>();
const inFlightByPrisma = new WeakMap<object, Promise<OrganizationTreeNode[]>>();
const generationByPrisma = new WeakMap<object, number>();

export async function getOrganizationTree(
  prisma: any,
): Promise<OrganizationTreeNode[]> {
  const organizationNode = prisma?.organizationNode;
  if (!organizationNode?.findMany) return [];

  const now = Date.now();
  const cached = cacheByPrisma.get(prisma);
  if (cached && cached.expiresAt > now) return cached.nodes;

  const pending = inFlightByPrisma.get(prisma);
  if (pending) return pending;

  const generation = generationByPrisma.get(prisma) ?? 0;
  const load = organizationNode
    .findMany({
      select: {
        id: true,
        parentId: true,
        code: true,
        businessCode: true,
        type: true,
        displayName: true,
        abbreviation: true,
        isActive: true,
        stores: { select: { storeId: true, storeName: true } },
      },
    })
    .then((nodes: OrganizationTreeNode[]) => {
      if ((generationByPrisma.get(prisma) ?? 0) === generation) {
        cacheByPrisma.set(prisma, {
          expiresAt: Date.now() + TTL_MS,
          nodes,
        });
      }
      return nodes;
    })
    .finally(() => inFlightByPrisma.delete(prisma));

  inFlightByPrisma.set(prisma, load);
  return load;
}

export function clearOrganizationTreeCache(prisma?: object) {
  if (!prisma) return;
  cacheByPrisma.delete(prisma);
  generationByPrisma.set(prisma, (generationByPrisma.get(prisma) ?? 0) + 1);
}
