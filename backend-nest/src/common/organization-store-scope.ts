import { Prisma } from '@prisma/client';

type StoreLike = {
  storeId?: string | null;
  storeName?: string | null;
  [key: string]: unknown;
};

type OrganizationNodeStoreTree = {
  stores?: StoreLike[] | null;
  parent?: OrganizationNodeStoreTree | null | unknown;
  [key: string]: unknown;
};

export function organizationNodeStoreTreeInclude(
  depth = 6,
): Prisma.OrganizationNodeInclude {
  const includeStores = {
    orderBy: { storeId: Prisma.SortOrder.asc },
  };
  const build = (remainingDepth: number): Prisma.OrganizationNodeInclude => ({
    stores: includeStores,
    ...(remainingDepth > 0
      ? {
          parent: {
            include: build(remainingDepth - 1),
          },
        }
      : {}),
  });
  return build(depth);
}

export function storesForOrganizationNodeTree<
  TStore extends StoreLike = StoreLike,
>(node?: unknown) {
  const storesByCode = new Map<string, TStore>();
  let cursor: OrganizationNodeStoreTree | null =
    node && typeof node === 'object'
      ? (node as OrganizationNodeStoreTree)
      : null;
  for (let guard = 0; cursor && guard < 20; guard += 1) {
    for (const store of cursor.stores ?? []) {
      const code = String(store?.storeId || '')
        .trim()
        .toUpperCase();
      if (code && !storesByCode.has(code)) {
        storesByCode.set(code, store as TStore);
      }
    }
    cursor =
      cursor.parent && typeof cursor.parent === 'object'
        ? (cursor.parent as OrganizationNodeStoreTree)
        : null;
  }
  return Array.from(storesByCode.values());
}

export function firstStoreForOrganizationNodeTree<
  TStore extends StoreLike = StoreLike,
>(node?: unknown) {
  return storesForOrganizationNodeTree(node)[0] ?? null;
}
