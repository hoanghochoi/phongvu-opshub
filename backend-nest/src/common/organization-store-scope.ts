import { Prisma } from '@prisma/client';

type StoreLike = {
  storeId?: string | null;
  storeName?: string | null;
  [key: string]: unknown;
};

type OrganizationNodeStoreTree = {
  id?: string | null;
  type?: string | null;
  stores?: StoreLike[] | null;
  parent?: OrganizationNodeStoreTree | null | unknown;
  children?: OrganizationNodeStoreTree[] | null | unknown;
  [key: string]: unknown;
};

export function organizationNodeStoreTreeInclude(
  depth = 6,
): Prisma.OrganizationNodeInclude {
  const includeStores = {
    orderBy: { storeId: Prisma.SortOrder.asc },
  };
  const childBranch = (
    remainingDepth: number,
  ): Prisma.OrganizationNodeInclude => ({
    stores: includeStores,
    ...(remainingDepth > 0
      ? {
          children: {
            orderBy: { sortOrder: Prisma.SortOrder.asc },
            include: childBranch(remainingDepth - 1),
          },
        }
      : {}),
  });
  const parentBranch = (
    remainingDepth: number,
  ): Prisma.OrganizationNodeInclude => ({
    stores: includeStores,
    ...(remainingDepth > 0
      ? {
          parent: {
            include: parentBranch(remainingDepth - 1),
          },
        }
      : {}),
  });
  return {
    stores: includeStores,
    ...(depth > 0
      ? {
          parent: {
            include: {
              ...parentBranch(depth - 1),
              children: {
                orderBy: { sortOrder: Prisma.SortOrder.asc },
                include: childBranch(depth - 1),
              },
            },
          },
          children: {
            orderBy: { sortOrder: Prisma.SortOrder.asc },
            include: childBranch(depth - 1),
          },
        }
      : {}),
  };
}

export function storesForOrganizationNodeTree<
  TStore extends StoreLike = StoreLike,
>(node?: unknown) {
  const storesByCode = new Map<string, TStore>();
  const root: OrganizationNodeStoreTree | null =
    node && typeof node === 'object'
      ? (node as OrganizationNodeStoreTree)
      : null;
  const pushStore = (store?: StoreLike | null) => {
    const code = String(store?.storeId || '')
      .trim()
      .toUpperCase();
    if (code && !storesByCode.has(code)) {
      storesByCode.set(code, store as TStore);
    }
  };
  const visited = new Set<unknown>();
  const visitKey = (current: OrganizationNodeStoreTree, fallback: string) =>
    current.id ?? fallback;
  const collectDescendantStores = (
    current: OrganizationNodeStoreTree | null,
    path: string,
    depth: number,
  ) => {
    if (!current || depth > 20) return;
    const key = visitKey(current, path);
    if (visited.has(key)) return;
    visited.add(key);
    for (const store of current.stores ?? []) {
      pushStore(store);
    }
    const children = Array.isArray(current.children) ? current.children : [];
    children.forEach((child, index) => {
      collectDescendantStores(child, `${path}.${index}`, depth + 1);
    });
  };

  const normalizedType = (current?: OrganizationNodeStoreTree | null) =>
    String(current?.type || '')
      .trim()
      .toUpperCase();
  const rootType = normalizedType(root);
  const rootParent =
    root?.parent && typeof root.parent === 'object'
      ? (root.parent as OrganizationNodeStoreTree)
      : null;
  const parentType = normalizedType(rootParent);
  const isPositionNode = ['LV5_POSITION', 'JOB_ROLE', 'POSITION'].includes(
    rootType,
  );
  const isStoreNode = ['LV4_STORE', 'SHOWROOM', 'STORE'].includes(parentType);

  // A position under an area/region manages that parent's whole subtree.
  // Store positions remain limited to their direct showroom.
  const descendantRoot =
    isPositionNode && rootParent && !isStoreNode ? rootParent : root;
  collectDescendantStores(descendantRoot, 'root', 0);

  let cursor: OrganizationNodeStoreTree | null = rootParent;
  for (let guard = 0; cursor && guard < 20; guard += 1) {
    for (const store of cursor.stores ?? []) {
      pushStore(store);
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
