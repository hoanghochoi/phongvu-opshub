import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const backendDir = resolve(scriptDir, '..');
const repoDir = resolve(backendDir, '..');

const checks = [];

function read(relativePath) {
  return readFileSync(join(repoDir, relativePath), 'utf8');
}

function addCheck(name, ok, detail) {
  checks.push({ name, ok, detail: ok ? '' : detail });
}

function includesAny(text, values) {
  return values.some((value) => text.includes(value));
}

const runtimeFiles = [
  'backend-nest/src/user/user.service.ts',
  'backend-nest/src/feature/feature.service.ts',
  'backend-nest/src/policy/policy.service.ts',
  'backend-nest/scripts/reset-organization-tree-to-roots.mjs',
  'lib/features/admin/domain/admin_organization_node.dart',
  'lib/features/admin/presentation/screens/organization_tree_admin_screen.dart',
];

const oldAcareMarkers = ['org-domain-acaretek-vn', 'DOMAIN_ACARETEK_VN'];
const oldAcareHits = runtimeFiles.filter((file) =>
  includesAny(read(file), oldAcareMarkers),
);
addCheck(
  'no old ACare root markers in runtime code',
  oldAcareHits.length === 0,
  oldAcareHits.join(', '),
);

const userService = read('backend-nest/src/user/user.service.ts');
addCheck(
  'backend guards writable org node types',
  userService.includes('RUNTIME_ORG_TREE_NODE_TYPES') &&
    userService.includes('ORG_TYPE_LV0_DOMAIN') &&
    userService.includes('ORG_TYPE_LV4_STORE') &&
    userService.includes('ORG_TYPE_LV5_POSITION') &&
    userService.includes('Cây tổ chức runtime chỉ hỗ trợ'),
  'missing runtime node type guard',
);
addCheck(
  'backend enforces Lv4/Lv5 parent chain',
  userService.includes('childType === ORG_TYPE_LV4_STORE') &&
    userService.includes('normalizedParentType === ORG_TYPE_LV0_DOMAIN') &&
    userService.includes('childType === ORG_TYPE_LV5_POSITION') &&
    userService.includes('normalizedParentType === ORG_TYPE_LV4_STORE'),
  'missing strict parent-chain checks',
);
addCheck(
  'backend keeps store users on Lv5 CASH by default',
  userService.includes('defaultStoreCashNodeIdForClient') &&
    userService.includes("businessCode: 'CASH'") &&
    userService.includes("jobRoleCode: 'CASH'") &&
    !userService.includes('organizationNodeId: syncResult.nodeId,') &&
    !userService.includes('organizationNodeId: organizationSync.nodeId,'),
  'store user relink/default assignment can still fall back to Lv4 store node',
);

const nodeModel = read('lib/features/admin/domain/admin_organization_node.dart');
const definitionsMatch = nodeModel.match(
  /static const definitions = \[(?<body>[\s\S]*?)\];/,
);
const definitionsBody = definitionsMatch?.groups?.body ?? '';
const retiredTypesInPicker = [
  'LV1_BLOCK',
  'LV2_DEPARTMENT',
  'LV2_REGION',
  'LV3_AREA',
  'LV3_UNIT',
].filter((type) => definitionsBody.includes(type));
addCheck(
  'Flutter org-node picker exposes only runtime node types',
  definitionsMatch !== null &&
    definitionsBody.includes('LV0_DOMAIN') &&
    definitionsBody.includes('LV4_STORE') &&
    definitionsBody.includes('LV5_POSITION') &&
    retiredTypesInPicker.length === 0,
  retiredTypesInPicker.join(', ') || 'definitions block missing',
);

const orgTreeScreen = read(
  'lib/features/admin/presentation/screens/organization_tree_admin_screen.dart',
);
addCheck(
  'Flutter defaults new children to Lv4/Lv5 runtime chain',
  orgTreeScreen.includes("'LV0_DOMAIN' => 'LV4_STORE'") &&
    orgTreeScreen.includes("'LV4_STORE' => 'LV5_POSITION'") &&
    !orgTreeScreen.includes("0 => 'LV1_BLOCK'"),
  'default child type still references retired hierarchy',
);

const failed = checks.filter((check) => !check.ok);
const result = {
  ok: failed.length === 0,
  generatedAt: new Date().toISOString(),
  checks,
};
console.log(JSON.stringify(result, null, 2));

if (failed.length > 0) {
  process.exitCode = 2;
}
