import 'dotenv/config';
import { createPrismaClient } from './prisma-local.mjs';

const CONFIRM_VALUE = 'reset-org-tree-to-roots';
const ROOT_PHONGVU_ID = 'org-domain-phongvu-vn';
const ROOT_ACARE_ID = 'org-domain-acaretek-vn';
const RESET_NODE_TYPES = [
  'SUBDOMAIN',
  'REGION',
  'AREA',
  'DEPARTMENT',
  'JOB_ROLE',
  'BLOCK',
  'VIRTUAL_SCOPE',
];

const apply = process.argv.includes('--apply');
const dryRun = !apply || process.argv.includes('--dry-run');

if (apply && process.env.OPSHUB_ORG_TREE_RESET_CONFIRM !== CONFIRM_VALUE) {
  fail(
    `Refusing to apply. Set OPSHUB_ORG_TREE_RESET_CONFIRM=${CONFIRM_VALUE}.`,
  );
}

const { prisma, close } = createPrismaClient();

try {
  const before = await collectSummary();
  if (dryRun) {
    console.log(JSON.stringify({ mode: 'dry-run', before, plan: planSummary(before) }, null, 2));
    console.log('No data changed. Re-run with --apply and OPSHUB_ORG_TREE_RESET_CONFIRM to mutate the database.');
  } else {
    const result = await prisma.$transaction(async (tx) => {
      await ensureRootDomains(tx);
      const linkedStores = await moveStoresToDomainRoots(tx);
      const orphanShowrooms = await moveOrphanShowroomsToDomainRoots(tx);
      const clearedReferences = await clearLegacyOrganizationReferences(tx);
      const deletedNodes = await deleteResetNodesDeepestFirst(tx);
      return { linkedStores, orphanShowrooms, clearedReferences, deletedNodes };
    });
    const after = await collectSummary();
    verifyAfterReset(after);
    console.log(JSON.stringify({ mode: 'apply', before, result, after }, null, 2));
    console.log('Organization tree reset completed. Stores are now attached directly to root domains.');
  }
} finally {
  await close();
}

async function collectSummary() {
  const [stores, transferAccounts, mapUsers, nodesByType, storesMissingNode, storesWithArea, usersWithLegacyScope] =
    await Promise.all([
      prisma.store.count(),
      prisma.store.count({ where: { transferAccountNumber: { not: null } } }),
      prisma.store.count({ where: { mapVietinUsername: { not: null } } }),
      prisma.organizationNode.groupBy({ by: ['type'], _count: { _all: true } }),
      prisma.store.count({ where: { organizationNodeId: null } }),
      prisma.store.count({ where: { areaCode: { not: null } } }),
      prisma.user.count({
        where: { OR: [{ regionCode: { not: null } }, { areaCode: { not: null } }] },
      }),
    ]);
  const nodeCounts = Object.fromEntries(
    nodesByType.map((item) => [item.type, item._count._all]),
  );
  const resetNodeCount = RESET_NODE_TYPES.reduce(
    (total, type) => total + (nodeCounts[type] || 0),
    0,
  );
  const showroomsNotUnderRoot = await prisma.organizationNode.count({
    where: {
      type: 'SHOWROOM',
      NOT: { parentId: { in: [ROOT_PHONGVU_ID, ROOT_ACARE_ID] } },
    },
  });
  return {
    stores,
    transferAccounts,
    mapUsers,
    nodesByType: nodeCounts,
    resetNodeCount,
    storesMissingNode,
    storesWithArea,
    usersWithLegacyScope,
    showroomsNotUnderRoot,
  };
}

function planSummary(summary) {
  return {
    ensureRootDomains: [ROOT_PHONGVU_ID, ROOT_ACARE_ID],
    moveOrCreateShowroomsForStores: summary.stores,
    clearStoreAreaCode: summary.storesWithArea,
    clearUserRegionAreaCode: summary.usersWithLegacyScope,
    deleteNodeTypes: RESET_NODE_TYPES,
    deleteNodeCount: summary.resetNodeCount,
    preservedStorePaymentAndMapCounts: {
      transferAccounts: summary.transferAccounts,
      mapUsers: summary.mapUsers,
    },
  };
}

async function ensureRootDomains(client) {
  await client.organizationNode.upsert({
    where: { code: 'DOMAIN_PHONGVU_VN' },
    update: {
      displayName: 'phongvu.vn',
      businessCode: 'phongvu.vn',
      abbreviation: 'PV',
      description: 'Domain dang nhap Phong Vu',
      type: 'ROOT_DOMAIN',
      parentId: null,
      emailDomain: 'phongvu.vn',
      loginAllowed: true,
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    },
    create: {
      id: ROOT_PHONGVU_ID,
      code: 'DOMAIN_PHONGVU_VN',
      displayName: 'phongvu.vn',
      businessCode: 'phongvu.vn',
      abbreviation: 'PV',
      description: 'Domain dang nhap Phong Vu',
      type: 'ROOT_DOMAIN',
      parentId: null,
      emailDomain: 'phongvu.vn',
      loginAllowed: true,
      isSystem: true,
      isActive: true,
      sortOrder: 10,
    },
  });
  await client.organizationNode.upsert({
    where: { code: 'DOMAIN_ACARETEK_VN' },
    update: {
      displayName: 'acare.vn',
      businessCode: 'acare.vn',
      abbreviation: 'ACARE',
      description: 'Domain dang nhap A Care',
      type: 'ROOT_DOMAIN',
      parentId: null,
      emailDomain: 'acare.vn',
      loginAllowed: true,
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    },
    create: {
      id: ROOT_ACARE_ID,
      code: 'DOMAIN_ACARETEK_VN',
      displayName: 'acare.vn',
      businessCode: 'acare.vn',
      abbreviation: 'ACARE',
      description: 'Domain dang nhap A Care',
      type: 'ROOT_DOMAIN',
      parentId: null,
      emailDomain: 'acare.vn',
      loginAllowed: true,
      isSystem: true,
      isActive: true,
      sortOrder: 20,
    },
  });
}

async function moveStoresToDomainRoots(client) {
  const stores = await client.store.findMany({ orderBy: { storeId: 'asc' } });
  let linked = 0;
  let created = 0;
  let moved = 0;

  for (const store of stores) {
    const nodeCode = normalizeOrganizationNodeCode('STORE_' + store.storeId);
    const rootId = rootIdForStore(store.storeId);
    const displayName = store.storeName || store.storeId;
    const existingByCode = await client.organizationNode.findUnique({
      where: { code: nodeCode },
    });
    let node = existingByCode;
    if (!node && store.organizationNodeId) {
      const linkedNode = await client.organizationNode.findUnique({
        where: { id: store.organizationNodeId },
      });
      if (linkedNode?.type === 'SHOWROOM' && !linkedNode.isSystem) {
        const duplicate = await client.organizationNode.findUnique({
          where: { code: nodeCode },
        });
        if (duplicate && duplicate.id !== linkedNode.id) {
          throw new Error(
            `Duplicate showroom nodes for store ${store.storeId}: ${linkedNode.id} and ${duplicate.id}`,
          );
        }
        node = linkedNode;
      }
    }

    const data = {
      code: nodeCode,
      displayName,
      businessCode: store.storeId,
      abbreviation: store.storeId,
      description: displayName,
      type: 'SHOWROOM',
      parentId: rootId,
      emailDomain: null,
      loginAllowed: false,
      isSystem: false,
      isActive: true,
      sortOrder: rootId === ROOT_ACARE_ID ? 20300 : 10300,
    };

    const savedNode = node
      ? await client.organizationNode.update({ where: { id: node.id }, data })
      : await client.organizationNode.create({ data });
    if (!node) created += 1;
    if (node && node.parentId !== rootId) moved += 1;

    await client.store.update({
      where: { id: store.id },
      data: { organizationNodeId: savedNode.id, areaCode: null },
    });
    await client.user.updateMany({
      where: { storeId: store.id },
      data: {
        organizationNodeId: savedNode.id,
        regionCode: null,
        areaCode: null,
      },
    });
    linked += 1;
  }

  return { stores: stores.length, linked, created, moved };
}

async function moveOrphanShowroomsToDomainRoots(client) {
  const showrooms = await client.organizationNode.findMany({
    where: {
      type: 'SHOWROOM',
      NOT: { parentId: { in: [ROOT_PHONGVU_ID, ROOT_ACARE_ID] } },
      stores: { none: {} },
    },
    orderBy: { code: 'asc' },
  });
  let moved = 0;
  for (const node of showrooms) {
    const token = node.businessCode || node.code.replace(/^STORE_/i, '');
    await client.organizationNode.update({
      where: { id: node.id },
      data: { parentId: rootIdForStore(token) },
    });
    moved += 1;
  }
  return { moved };
}

async function clearLegacyOrganizationReferences(client) {
  const resetNodes = await client.organizationNode.findMany({
    where: { type: { in: RESET_NODE_TYPES } },
    select: { id: true },
  });
  const ids = resetNodes.map((node) => node.id);
  const counts = {
    usersLegacyScope: await client.user.updateMany({
      data: { regionCode: null, areaCode: null },
    }),
    departments: { count: 0 },
    jobRoles: { count: 0 },
    regions: { count: 0 },
    areas: { count: 0 },
    featureRulesDeleted: { count: 0 },
    featureRulesUnlinked: { count: 0 },
    policyRulesDeleted: { count: 0 },
    policyRulesUnlinked: { count: 0 },
  };
  if (ids.length === 0) return normalizeUpdateCounts(counts);

  counts.departments = await client.departmentDefinition.updateMany({
    where: { organizationNodeId: { in: ids } },
    data: { organizationNodeId: null },
  });
  counts.jobRoles = await client.jobRoleDefinition.updateMany({
    where: { organizationNodeId: { in: ids } },
    data: { organizationNodeId: null },
  });
  counts.regions = await client.regionDefinition.updateMany({
    where: { organizationNodeId: { in: ids } },
    data: { organizationNodeId: null },
  });
  counts.areas = await client.areaDefinition.updateMany({
    where: { organizationNodeId: { in: ids } },
    data: { organizationNodeId: null },
  });
  counts.featureRulesDeleted = await client.featureAccessRule.deleteMany({
    where: {
      organizationNodeId: { in: ids },
      ...unscopedRuleWhere(),
    },
  });
  counts.featureRulesUnlinked = await client.featureAccessRule.updateMany({
    where: { organizationNodeId: { in: ids } },
    data: { organizationNodeId: null },
  });
  counts.policyRulesDeleted = await client.adminPolicyRule.deleteMany({
    where: {
      organizationNodeId: { in: ids },
      ...unscopedPolicyRuleWhere(),
    },
  });
  counts.policyRulesUnlinked = await client.adminPolicyRule.updateMany({
    where: { organizationNodeId: { in: ids } },
    data: { organizationNodeId: null },
  });
  await client.user.updateMany({
    where: { organizationNodeId: { in: ids } },
    data: { organizationNodeId: null },
  });
  return normalizeUpdateCounts(counts);
}

function unscopedRuleWhere() {
  return {
    emailDomain: null,
    systemRole: null,
    departmentCode: null,
    jobRoleCode: null,
    workScopeType: null,
    regionCode: null,
    areaCode: null,
    storeCode: null,
    userId: null,
  };
}

function unscopedPolicyRuleWhere() {
  return {
    ...unscopedRuleWhere(),
    scopeContains: null,
  };
}

async function deleteResetNodesDeepestFirst(client) {
  const nodes = await client.organizationNode.findMany({
    select: { id: true, parentId: true, type: true, code: true },
  });
  const resetIds = new Set(
    nodes.filter((node) => RESET_NODE_TYPES.includes(node.type)).map((node) => node.id),
  );
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const depthOf = (node) => {
    let depth = 0;
    let cursor = node;
    for (let guard = 0; cursor?.parentId && guard < 80; guard += 1) {
      depth += 1;
      cursor = byId.get(cursor.parentId);
    }
    return depth;
  };
  const toDelete = nodes
    .filter((node) => resetIds.has(node.id))
    .sort((a, b) => depthOf(b) - depthOf(a));
  let deleted = 0;
  for (const node of toDelete) {
    await client.organizationNode.delete({ where: { id: node.id } });
    deleted += 1;
  }
  return { deleted };
}

function verifyAfterReset(summary) {
  const failures = [];
  if (summary.resetNodeCount !== 0) failures.push(`resetNodeCount=${summary.resetNodeCount}`);
  if (summary.storesMissingNode !== 0) failures.push(`storesMissingNode=${summary.storesMissingNode}`);
  if (summary.storesWithArea !== 0) failures.push(`storesWithArea=${summary.storesWithArea}`);
  if (summary.usersWithLegacyScope !== 0) failures.push(`usersWithLegacyScope=${summary.usersWithLegacyScope}`);
  if (summary.showroomsNotUnderRoot !== 0) failures.push(`showroomsNotUnderRoot=${summary.showroomsNotUnderRoot}`);
  if (failures.length > 0) {
    throw new Error('Reset verification failed: ' + failures.join(', '));
  }
}

function normalizeUpdateCounts(value) {
  return Object.fromEntries(
    Object.entries(value).map(([key, result]) => [key, result?.count ?? 0]),
  );
}

function rootIdForStore(storeId) {
  return String(storeId || '').trim().toUpperCase().startsWith('AC')
    ? ROOT_ACARE_ID
    : ROOT_PHONGVU_ID;
}

function normalizeOrganizationNodeCode(value) {
  return String(value || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
