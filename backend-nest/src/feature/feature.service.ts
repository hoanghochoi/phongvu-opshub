import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DEFAULT_FEATURE_DEFINITIONS } from './feature.constants';
import {
  SYSTEM_ROLE_ADMIN,
  SYSTEM_ROLE_SUPER_ADMIN,
  normalizeSystemRoleCode,
  isSuperAdminRole,
} from '../common/system-role';
import { logFingerprint } from '../common/log-sanitizer';
import { AccessChangeService } from '../auth/access-change.service';

const SUPER_ADMIN_ROLE = SYSTEM_ROLE_SUPER_ADMIN;
const ADMIN_ROLE = SYSTEM_ROLE_ADMIN;
const VALID_WORK_SCOPES = new Set(['NATIONAL', 'REGION', 'AREA', 'STORE']);

type FeatureNodeTarget = {
  scopeRootNodeId: string;
  nodeType: string;
  nodeKey: string;
  organizationNodeId?: string | null;
};

type FeatureContext = {
  id?: string | null;
  email?: string | null;
  emailDomain?: string | null;
  role?: string | null;
  departmentCode?: string | null;
  jobRoleCode?: string | null;
  workScopeType?: string | null;
  regionCode?: string | null;
  areaCode?: string | null;
  storeCode?: string | null;
  organizationNodeId?: string | null;
  organizationNodeIds?: string[];
  organizationNodeActive?: boolean;
  organizationScopeRootId?: string | null;
  organizationNodeType?: string | null;
  organizationNodeKey?: string | null;
  organizationNodeFeatureTargets?: FeatureNodeTarget[];
  storeName?: string | null;
  alternateContexts?: FeatureContext[];
};

@Injectable()
export class FeatureService implements OnModuleInit {
  private readonly logger = new Logger(FeatureService.name);

  constructor(
    private prisma: PrismaService,
    private readonly accessChangeService: AccessChangeService,
  ) {}

  async onModuleInit() {
    await this.seedDefaultFeatures();
  }

  async seedDefaultFeatures() {
    await Promise.all(
      DEFAULT_FEATURE_DEFINITIONS.map((feature) => {
        const featureData = feature as any;
        return this.prisma.featureDefinition.upsert({
          where: { code: featureData.code },
          update: {
            displayName: featureData.displayName,
            description: featureData.description,
            parentCode: featureData.parentCode ?? null,
            sortOrder: featureData.sortOrder ?? 0,
            visibleInUserPicker: featureData.visibleInUserPicker !== false,
            isSystem: true,
            isActive: true,
          },
          create: {
            ...featureData,
            parentCode: featureData.parentCode ?? null,
            sortOrder: featureData.sortOrder ?? 0,
            visibleInUserPicker: featureData.visibleInUserPicker !== false,
            isSystem: true,
            isActive: true,
          },
        });
      }),
    );
  }

  async resolveFeatureAccessMap(user: any) {
    const features = await this.prisma.featureDefinition.findMany({
      where: { isActive: true },
      orderBy: { code: 'asc' },
    });
    const context = await this.resolveContext(user);
    if (this.normalizeSystemRole(context.role) === SUPER_ADMIN_ROLE) {
      return Object.fromEntries(
        features.map((feature) => [feature.code, true]),
      );
    }

    const featureCodes = features.map((feature) => feature.code);
    const targetGroups = this.requiredFeatureTargetGroups(context);
    if (targetGroups.length === 0) {
      return Object.fromEntries(
        featureCodes.map((featureCode) => [featureCode, false]),
      );
    }

    const enabledAssignments = await this.enabledFeatureAssignmentKeys(
      targetGroups.flat(),
      featureCodes,
    );
    return Object.fromEntries(
      featureCodes.map((featureCode) => [
        featureCode,
        targetGroups.some((targets) =>
          targets.every((target) =>
            enabledAssignments.has(this.featureTargetKey(target, featureCode)),
          ),
        ),
      ]),
    );
  }

  async canAccessFeature(user: any, featureCode: string) {
    const context = await this.resolveContext(user);
    return this.canAccessFeatureWithContext(context, featureCode);
  }

  async adminListFeatures(admin: any) {
    this.assertSuperAdmin(admin);
    await this.seedDefaultFeatures();
    return this.prisma.featureDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { sortOrder: 'asc' }, { code: 'asc' }],
      include: { _count: { select: { rules: true, nodeAssignments: true } } },
    });
  }

  async adminListFeatureTree(admin: any) {
    this.assertSuperAdmin(admin);
    await this.seedDefaultFeatures();
    return this.prisma.featureDefinition.findMany({
      where: { isActive: true, visibleInUserPicker: true },
      orderBy: [{ sortOrder: 'asc' }, { code: 'asc' }],
      include: {
        _count: {
          select: {
            rules: true,
            userAssignments: true,
            nodeAssignments: true,
          },
        },
      },
    });
  }

  async adminCreateFeature(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeCode(body.code, 'Mã tính năng không hợp lệ');
    const existing = await this.prisma.featureDefinition.findUnique({
      where: { code },
    });
    if (existing) throw new BadRequestException('Tính năng đã tồn tại');
    const created = await this.prisma.featureDefinition.create({
      data: {
        code,
        displayName: this.requiredText(
          body.displayName,
          'Tên tính năng không được để trống',
          120,
        ),
        description: this.optionalText(body.description, 240),
        parentCode: this.normalizeOptionalCode(body.parentCode),
        sortOrder: this.normalizeSortOrder(body.sortOrder),
        visibleInUserPicker: body.visibleInUserPicker !== false,
        isSystem: false,
        isActive: body.isActive !== false,
      },
    });
    await this.accessChangeService.publishForAllUsers(
      'feature-definition-created',
    );
    return created;
  }

  async adminUpdateFeature(admin: any, codeInput: string, body: any) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeCode(codeInput, 'Mã tính năng không hợp lệ');
    const current = await this.prisma.featureDefinition.findUnique({
      where: { code },
    });
    if (!current) throw new NotFoundException('Không tìm thấy tính năng');

    const nextCode = body.code
      ? this.normalizeCode(body.code, 'Mã tính năng không hợp lệ')
      : current.code;
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Không được đổi mã tính năng hệ thống');
    }

    const updated = await this.prisma.featureDefinition.update({
      where: { code: current.code },
      data: {
        code: nextCode,
        displayName:
          body.displayName === undefined
            ? current.displayName
            : this.requiredText(
                body.displayName,
                'Tên tính năng không được để trống',
                120,
              ),
        description:
          body.description === undefined
            ? current.description
            : this.optionalText(body.description, 240),
        parentCode:
          body.parentCode === undefined
            ? current.parentCode
            : this.normalizeOptionalCode(body.parentCode),
        sortOrder:
          body.sortOrder === undefined
            ? current.sortOrder
            : this.normalizeSortOrder(body.sortOrder),
        visibleInUserPicker:
          body.visibleInUserPicker === undefined
            ? current.visibleInUserPicker
            : body.visibleInUserPicker === true,
        isActive:
          body.isActive === undefined
            ? current.isActive
            : body.isActive === true,
      },
    });
    const accessContractChanged =
      updated.code !== current.code ||
      updated.parentCode !== current.parentCode ||
      updated.isActive !== current.isActive;
    if (accessContractChanged) {
      await this.accessChangeService.publishForAllUsers(
        'feature-definition-updated',
      );
    }
    return updated;
  }

  async adminDeleteFeature(admin: any, codeInput: string) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeCode(codeInput, 'Mã tính năng không hợp lệ');
    const feature = await this.prisma.featureDefinition.findUnique({
      where: { code },
      include: {
        _count: {
          select: {
            rules: true,
            userAssignments: true,
            nodeAssignments: true,
          },
        },
      },
    });
    if (!feature) throw new NotFoundException('Không tìm thấy tính năng');
    if (feature.isSystem) {
      throw new BadRequestException('Không được xóa tính năng hệ thống');
    }
    if (feature._count.rules > 0) {
      throw new BadRequestException('Tính năng đang có rule, không thể xóa');
    }
    if (feature._count.userAssignments > 0) {
      throw new BadRequestException(
        'Tính năng đang được gán cho user, không thể xóa',
      );
    }
    if (feature._count.nodeAssignments > 0) {
      throw new BadRequestException(
        'Tính năng đang được gán cho node tổ chức, không thể xóa',
      );
    }
    await this.prisma.featureDefinition.delete({ where: { code } });
    await this.accessChangeService.publishForAllUsers(
      'feature-definition-deleted',
    );
    return { deleted: true, code };
  }

  async adminListRules(admin: any, featureCode?: string) {
    this.assertSuperAdmin(admin);
    const normalizedFeatureCode = featureCode
      ? this.normalizeCode(featureCode, 'Mã tính năng không hợp lệ')
      : undefined;
    return this.prisma.featureAccessRule.findMany({
      where: normalizedFeatureCode
        ? { featureCode: normalizedFeatureCode }
        : undefined,
      orderBy: { updatedAt: 'desc' },
      include: {
        feature: true,
        department: true,
        jobRole: true,
        region: true,
        area: true,
        organizationNode: true,
        store: true,
        user: {
          select: { id: true, email: true, firstName: true, lastName: true },
        },
      },
    });
  }

  async adminCreateRule(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    const data = await this.normalizeRuleInput(body);
    const created = await this.prisma.featureAccessRule.create({ data });
    await this.accessChangeService.publishForAllUsers('feature-rule-created');
    return created;
  }

  async adminCreateRules(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    const dataList = await this.normalizeRuleBatchInput(body);
    const created = await this.prisma.$transaction(
      dataList.map((data) => this.prisma.featureAccessRule.create({ data })),
    );
    await this.accessChangeService.publishForAllUsers('feature-rule-created');
    return created;
  }

  async adminUpdateRule(admin: any, id: string, body: any) {
    this.assertSuperAdmin(admin);
    const current = await this.prisma.featureAccessRule.findUnique({
      where: { id },
    });
    if (!current) throw new NotFoundException('Không tìm thấy rule');
    const data = await this.normalizeRuleInput(
      { ...current, ...body },
      current,
    );
    const updated = await this.prisma.featureAccessRule.update({
      where: { id },
      data,
    });
    await this.accessChangeService.publishForAllUsers('feature-rule-updated');
    return updated;
  }

  async adminDeleteRule(admin: any, id: string) {
    this.assertSuperAdmin(admin);
    await this.prisma.featureAccessRule.delete({ where: { id } });
    await this.accessChangeService.publishForAllUsers('feature-rule-deleted');
    return { deleted: true, id };
  }

  async adminListNodeAssignments(admin: any, featureCode?: string) {
    this.assertSuperAdmin(admin);
    await this.seedDefaultFeatures();
    const normalizedFeatureCode = featureCode
      ? this.normalizeCode(featureCode, 'Mã tính năng không hợp lệ')
      : undefined;
    const rows = await this.prisma.organizationNodeFeatureAssignment.findMany({
      where: normalizedFeatureCode
        ? { featureCode: normalizedFeatureCode }
        : undefined,
      orderBy: [
        { scopeRootNodeId: 'asc' },
        { nodeType: 'asc' },
        { nodeKey: 'asc' },
        { featureCode: 'asc' },
      ],
      include: {
        feature: true,
        scopeRootNode: true,
        assignedBy: {
          select: {
            id: true,
            email: true,
            firstName: true,
            lastName: true,
          },
        },
      },
    });

    const result = [];
    for (const row of rows) {
      result.push(await this.toNodeFeatureAssignmentDto(row));
    }
    return result;
  }

  async adminCreateNodeAssignments(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    await this.seedDefaultFeatures();
    const nodeIds = this.normalizeRequiredTextList(
      body.organizationNodeIds ?? body.organizationNodeId,
      80,
      'Chọn ít nhất một node tổ chức',
    );
    const featureCodes = await this.normalizeFeatureTreeCodeList(
      body.featureTreeCodes ?? body.featureCodes ?? [],
    );
    const replaceExisting = body.replaceExisting === true;
    const enabled = body.enabled !== false;
    if (!replaceExisting && featureCodes.length === 0) {
      throw new BadRequestException('Chọn ít nhất một tính năng');
    }
    if (featureCodes.length > 0) await this.ensureFeaturesExist(featureCodes);
    const note = this.optionalText(body.note, 240);

    const targetMap = new Map<
      string,
      {
        scopeRootNodeId: string;
        nodeType: string;
        nodeKey: string;
        organizationNodeIds: string[];
      }
    >();
    for (const nodeId of nodeIds) {
      const target = await this.resolveNodeFeatureTarget(nodeId);
      targetMap.set(
        `${target.scopeRootNodeId}:${target.nodeType}:${target.nodeKey}`,
        target,
      );
    }
    const targets = Array.from(targetMap.values());

    await this.prisma.$transaction(async (tx) => {
      for (const target of targets) {
        if (replaceExisting) {
          await tx.organizationNodeFeatureAssignment.deleteMany({
            where: {
              scopeRootNodeId: target.scopeRootNodeId,
              nodeType: target.nodeType,
              nodeKey: target.nodeKey,
            },
          });
        }
        for (const featureCode of featureCodes) {
          await tx.organizationNodeFeatureAssignment.upsert({
            where: {
              scopeRootNodeId_nodeType_nodeKey_featureCode: {
                scopeRootNodeId: target.scopeRootNodeId,
                nodeType: target.nodeType,
                nodeKey: target.nodeKey,
                featureCode,
              },
            },
            update: {
              enabled,
              assignedById: admin?.id ?? null,
              note,
              updatedAt: new Date(),
            },
            create: {
              scopeRootNodeId: target.scopeRootNodeId,
              nodeType: target.nodeType,
              nodeKey: target.nodeKey,
              featureCode,
              enabled,
              assignedById: admin?.id ?? null,
              note,
            },
          });
        }
      }
    });

    await this.accessChangeService.publishForOrganizationNodeIds(
      targets.flatMap((target) => target.organizationNodeIds),
      'feature-assignment-updated',
    );

    this.logger.log(
      `Node feature assignments saved: admin=${this.adminLogId(admin)} nodes=${nodeIds.length} groups=${targets.length} features=${featureCodes.length} replaceExisting=${replaceExisting}`,
    );
    return this.adminListNodeAssignments(admin);
  }

  async adminUpdateNodeAssignment(admin: any, id: string, body: any) {
    this.assertSuperAdmin(admin);
    const current =
      await this.prisma.organizationNodeFeatureAssignment.findUnique({
        where: { id },
      });
    if (!current) throw new NotFoundException('Không tìm thấy quyền node');
    const updated = await this.prisma.organizationNodeFeatureAssignment.update({
      where: { id },
      data: {
        enabled:
          body.enabled === undefined ? current.enabled : body.enabled === true,
        assignedById: admin?.id ?? current.assignedById,
        note:
          body.note === undefined
            ? current.note
            : this.optionalText(body.note, 240),
      },
      include: {
        feature: true,
        scopeRootNode: true,
        assignedBy: {
          select: {
            id: true,
            email: true,
            firstName: true,
            lastName: true,
          },
        },
      },
    });
    this.logger.log(
      `Node feature assignment updated: admin=${this.adminLogId(admin)} id=${id} feature=${updated.featureCode} enabled=${updated.enabled}`,
    );
    await this.accessChangeService.publishForOrganizationNodeIds(
      await this.organizationNodeIdsForFeatureGroup(
        current.scopeRootNodeId,
        current.nodeType,
        current.nodeKey,
      ),
      'feature-assignment-updated',
    );
    return this.toNodeFeatureAssignmentDto(updated);
  }

  async adminDeleteNodeAssignment(admin: any, id: string) {
    this.assertSuperAdmin(admin);
    const current =
      await this.prisma.organizationNodeFeatureAssignment.findUnique({
        where: { id },
      });
    if (!current) throw new NotFoundException('Không tìm thấy quyền node');
    await this.prisma.organizationNodeFeatureAssignment.delete({
      where: { id },
    });
    await this.accessChangeService.publishForOrganizationNodeIds(
      await this.organizationNodeIdsForFeatureGroup(
        current.scopeRootNodeId,
        current.nodeType,
        current.nodeKey,
      ),
      'feature-assignment-deleted',
    );
    this.logger.warn(
      `Node feature assignment deleted: admin=${this.adminLogId(admin)} id=${id} feature=${current.featureCode}`,
    );
    return { deleted: true, id };
  }

  private async toNodeFeatureAssignmentDto(row: any) {
    const organizationNodeIds = await this.organizationNodeIdsForFeatureGroup(
      row.scopeRootNodeId,
      row.nodeType,
      row.nodeKey,
    );
    const impactedUserCount =
      organizationNodeIds.length === 0
        ? 0
        : await this.prisma.user.count({
            where: {
              role: { not: SUPER_ADMIN_ROLE },
              organizationNodeId: { in: organizationNodeIds },
            },
          });
    return {
      id: row.id,
      scopeRootNodeId: row.scopeRootNodeId,
      scopeRootNodeName: row.scopeRootNode?.displayName ?? null,
      nodeType: row.nodeType,
      nodeKey: row.nodeKey,
      featureCode: row.featureCode,
      featureName: row.feature?.displayName ?? row.featureCode,
      enabled: row.enabled === true,
      assignedById: row.assignedById ?? null,
      assignedByEmail: row.assignedBy?.email ?? null,
      note: row.note ?? null,
      organizationNodeIds,
      impactedUserCount,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  private async resolveNodeFeatureTarget(nodeId: string) {
    const nodes = await this.prisma.organizationNode.findMany({
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
        isActive: true,
      },
    });
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const node = byId.get(nodeId);
    if (!node || !node.isActive) {
      throw new BadRequestException('Node tổ chức không tồn tại hoặc đã tắt');
    }
    const scopeRootNodeId = this.rootNodeIdForNode(nodes, nodeId);
    if (!scopeRootNodeId) {
      throw new BadRequestException(
        'Không xác định được root của node tổ chức',
      );
    }
    const nodeType = this.normalizeNodeType(node.type);
    const nodeKey = this.nodeFeatureKey(node);
    return {
      scopeRootNodeId,
      nodeType,
      nodeKey,
      organizationNodeIds: this.nodeIdsForFeatureGroupFromNodes(
        nodes,
        scopeRootNodeId,
        nodeType,
        nodeKey,
      ),
    };
  }

  private async organizationNodeIdsForFeatureGroup(
    scopeRootNodeId: string,
    nodeType: string,
    nodeKey: string,
  ) {
    const nodes = await this.prisma.organizationNode.findMany({
      where: { isActive: true },
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
        isActive: true,
      },
    });
    return this.nodeIdsForFeatureGroupFromNodes(
      nodes,
      scopeRootNodeId,
      this.normalizeNodeType(nodeType),
      this.normalizeNodeKey(nodeKey),
    );
  }

  private nodeIdsForFeatureGroupFromNodes(
    nodes: Array<{
      id: string;
      parentId: string | null;
      type: string;
      code: string;
      businessCode: string | null;
      isActive?: boolean | null;
    }>,
    scopeRootNodeId: string,
    nodeType: string,
    nodeKey: string,
  ) {
    const descendantIds = this.descendantIdsFromNodes(nodes, scopeRootNodeId);
    return nodes
      .filter(
        (node) =>
          node.isActive !== false &&
          descendantIds.has(node.id) &&
          this.normalizeNodeType(node.type) === nodeType &&
          this.nodeFeatureKey(node) === nodeKey,
      )
      .map((node) => node.id);
  }

  private descendantIdsFromNodes(
    nodes: Array<{ id: string; parentId: string | null }>,
    rootId: string,
  ) {
    const ids = new Set<string>([rootId]);
    let changed = true;
    while (changed) {
      changed = false;
      for (const node of nodes) {
        if (node.parentId && ids.has(node.parentId) && !ids.has(node.id)) {
          ids.add(node.id);
          changed = true;
        }
      }
    }
    return ids;
  }

  private rootNodeIdForNode(
    nodes: Array<{
      id: string;
      parentId: string | null;
      type: string;
      isActive?: boolean | null;
    }>,
    nodeId: string,
  ) {
    const byId = new Map(nodes.map((node) => [node.id, node]));
    let cursor = byId.get(nodeId) ?? null;
    let rootId: string | null = null;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      if (cursor.isActive === false) return null;
      rootId = cursor.id;
      if (
        !cursor.parentId ||
        this.normalizeNodeType(cursor.type) === 'LV0_DOMAIN'
      ) {
        return cursor.id;
      }
      cursor = byId.get(cursor.parentId) ?? null;
    }
    return rootId;
  }

  private nodeFeatureKey(node: {
    businessCode?: string | null;
    code?: string;
  }) {
    return this.normalizeNodeKey(node.businessCode || node.code);
  }

  private normalizeNodeKey(value: unknown) {
    const key = String(value || '')
      .trim()
      .toUpperCase();
    if (!key) throw new BadRequestException('Mã node tổ chức không hợp lệ');
    return key;
  }

  private normalizeNodeType(value: unknown) {
    const type = String(value || '')
      .trim()
      .toUpperCase();
    switch (type) {
      case 'ROOT_DOMAIN':
        return 'LV0_DOMAIN';
      case 'BLOCK':
        return 'LV1_BLOCK';
      case 'DEPARTMENT':
        return 'LV2_DEPARTMENT';
      case 'REGION':
        return 'LV2_REGION';
      case 'AREA':
        return 'LV3_AREA';
      case 'VIRTUAL_SCOPE':
        return 'LV3_UNIT';
      case 'SHOWROOM':
        return 'LV4_STORE';
      case 'JOB_ROLE':
        return 'LV5_POSITION';
      default:
        return type;
    }
  }

  private async canAccessFeatureWithContext(
    context: FeatureContext,
    featureCodeInput: string,
  ) {
    const featureCode = this.normalizeCode(
      featureCodeInput,
      'Mã tính năng không hợp lệ',
    );
    if (this.normalizeSystemRole(context.role) === SUPER_ADMIN_ROLE)
      return true;

    const feature = await this.prisma.featureDefinition.findUnique({
      where: { code: featureCode },
      select: { isActive: true },
    });
    if (!feature || !feature.isActive) return false;
    const targetGroups = this.requiredFeatureTargetGroups(context);
    if (targetGroups.length === 0) return false;
    const enabledAssignments = await this.enabledFeatureAssignmentKeys(
      targetGroups.flat(),
      [featureCode],
    );
    return targetGroups.some((targets) =>
      targets.every((target) =>
        enabledAssignments.has(this.featureTargetKey(target, featureCode)),
      ),
    );
  }

  private hasUsableFeatureContext(context: FeatureContext) {
    return (
      !!context.id &&
      context.organizationNodeActive === true &&
      !!context.organizationScopeRootId &&
      !!context.organizationNodeType &&
      !!context.organizationNodeKey
    );
  }

  private requiredFeatureNodeTargets(context: FeatureContext) {
    const fallbackTarget =
      context.organizationScopeRootId &&
      context.organizationNodeType &&
      context.organizationNodeKey
        ? [
            {
              scopeRootNodeId: context.organizationScopeRootId,
              nodeType: context.organizationNodeType,
              nodeKey: context.organizationNodeKey,
              organizationNodeId: context.organizationNodeId ?? null,
            },
          ]
        : [];
    const rawTargets =
      context.organizationNodeFeatureTargets &&
      context.organizationNodeFeatureTargets.length > 0
        ? context.organizationNodeFeatureTargets
        : fallbackTarget;
    const seen = new Set<string>();
    const result: FeatureNodeTarget[] = [];
    for (const target of rawTargets) {
      if (!target.scopeRootNodeId || !target.nodeType || !target.nodeKey) {
        continue;
      }
      const normalized = {
        scopeRootNodeId: target.scopeRootNodeId,
        nodeType: this.normalizeNodeType(target.nodeType),
        nodeKey: this.normalizeNodeKey(target.nodeKey),
        organizationNodeId: target.organizationNodeId ?? null,
      };
      const key = this.featureTargetKey(normalized, '');
      if (seen.has(key)) continue;
      seen.add(key);
      result.push(normalized);
    }
    return result;
  }

  private requiredFeatureTargetGroups(context: FeatureContext) {
    return [context, ...(context.alternateContexts ?? [])]
      .filter((candidate) => this.hasUsableFeatureContext(candidate))
      .map((candidate) => this.requiredFeatureNodeTargets(candidate))
      .filter((targets) => targets.length > 0);
  }

  private async enabledFeatureAssignmentKeys(
    targets: FeatureNodeTarget[],
    featureCodes: string[],
  ) {
    const normalizedFeatureCodes = Array.from(
      new Set(
        featureCodes.map((featureCode) =>
          this.normalizeCode(featureCode, 'Mã tính năng không hợp lệ'),
        ),
      ),
    );
    if (targets.length === 0 || normalizedFeatureCodes.length === 0) {
      return new Set<string>();
    }
    const rows = await this.prisma.organizationNodeFeatureAssignment.findMany({
      where: {
        enabled: true,
        featureCode: { in: normalizedFeatureCodes },
        OR: targets.map((target) => ({
          scopeRootNodeId: target.scopeRootNodeId,
          nodeType: target.nodeType,
          nodeKey: target.nodeKey,
        })),
      },
      select: {
        scopeRootNodeId: true,
        nodeType: true,
        nodeKey: true,
        featureCode: true,
      },
    });
    return new Set(
      rows.map((row) =>
        this.featureTargetKey(
          {
            scopeRootNodeId: row.scopeRootNodeId,
            nodeType: row.nodeType,
            nodeKey: row.nodeKey,
          },
          row.featureCode,
        ),
      ),
    );
  }

  private featureTargetKey(target: FeatureNodeTarget, featureCode: string) {
    return [
      target.scopeRootNodeId,
      this.normalizeNodeType(target.nodeType),
      this.normalizeNodeKey(target.nodeKey),
      featureCode,
    ].join('|');
  }

  private async normalizeRuleInput(input: any, current?: any) {
    const featureCode = this.normalizeCode(
      input.featureCode ?? current?.featureCode,
      'Mã tính năng không hợp lệ',
    );
    await this.ensureFeature(featureCode);
    const enabled =
      input.enabled === undefined
        ? current?.enabled === true
        : input.enabled === true;
    const workScopeType = this.normalizeOptionalCode(input.workScopeType);
    if (workScopeType && !VALID_WORK_SCOPES.has(workScopeType)) {
      throw new BadRequestException('Phạm vi tính năng không hợp lệ');
    }

    const data = {
      featureCode,
      enabled,
      emailDomain: this.normalizeOptionalDomain(input.emailDomain),
      systemRole: this.normalizeSystemRole(input.systemRole),
      departmentCode: this.normalizeOptionalCode(input.departmentCode),
      jobRoleCode: this.normalizeOptionalCode(input.jobRoleCode),
      workScopeType,
      regionCode: this.normalizeOptionalCode(input.regionCode),
      areaCode: this.normalizeOptionalCode(input.areaCode),
      organizationNodeId: this.optionalText(input.organizationNodeId, 80),
      storeCode: this.normalizeOptionalCode(input.storeCode),
      userId: this.optionalText(input.userId, 80),
      note: this.optionalText(input.note, 240),
    };

    await this.validateRuleReferences(data);
    return data;
  }

  private async normalizeRuleBatchInput(input: any) {
    const featureCode = this.normalizeCode(
      input.featureCode,
      'Mã tính năng không hợp lệ',
    );
    await this.ensureFeature(featureCode);
    const enabled = input.enabled === true;
    const note = this.optionalText(input.note, 240);
    const emailDomains = this.normalizeDomainOptions(
      input.emailDomains,
      input.emailDomain,
    );
    const systemRoles = this.normalizeCodeOptions(
      input.systemRoles,
      input.systemRole,
    ).map((role) => this.normalizeSystemRole(role));
    const departmentCodes = this.normalizeCodeOptions(
      input.departmentCodes,
      input.departmentCode,
    );
    const jobRoleCodes = this.normalizeCodeOptions(
      input.jobRoleCodes,
      input.jobRoleCode,
    );
    const workScopeTypes = this.normalizeCodeOptions(
      input.workScopeTypes,
      input.workScopeType,
    );
    for (const workScopeType of workScopeTypes) {
      if (workScopeType && !VALID_WORK_SCOPES.has(workScopeType)) {
        throw new BadRequestException('Phạm vi tính năng không hợp lệ');
      }
    }
    const locations = await this.normalizeLocationOptions(
      this.normalizeCodeOptions(input.regionCodes, input.regionCode),
      this.normalizeCodeOptions(input.areaCodes, input.areaCode),
    );
    const organizationNodeIds = this.normalizeTextOptions(
      input.organizationNodeIds,
      input.organizationNodeId,
      80,
    );
    const storeCodes = this.normalizeCodeOptions(
      input.storeCodes,
      input.storeCode,
    );
    const userIds = this.normalizeTextOptions(input.userIds, input.userId, 80);

    const dataList = this.expandRuleBatch({
      featureCode,
      enabled,
      note,
      emailDomains,
      systemRoles,
      departmentCodes,
      jobRoleCodes,
      workScopeTypes,
      locations,
      organizationNodeIds,
      storeCodes,
      userIds,
    });

    if (dataList.length > 500) {
      throw new BadRequestException('Tối đa 500 rules mỗi lần tạo');
    }

    for (const data of dataList) {
      await this.validateRuleReferences(data);
    }
    return dataList;
  }

  private normalizeCodeOptions(listValue: unknown, singleValue: unknown) {
    const values = Array.isArray(listValue) ? listValue : [];
    return this.normalizeOptions(values, singleValue, (value) =>
      this.normalizeOptionalCode(value),
    );
  }

  private normalizeTextOptions(
    listValue: unknown,
    singleValue: unknown,
    maxLength: number,
  ) {
    const values = Array.isArray(listValue) ? listValue : [];
    return this.normalizeOptions(values, singleValue, (value) =>
      this.optionalText(value, maxLength),
    );
  }

  private normalizeRequiredTextList(
    value: unknown,
    maxLength: number,
    message: string,
  ) {
    const values = Array.isArray(value) ? value : [value];
    const seen = new Set<string>();
    const result: string[] = [];
    for (const item of values) {
      const normalized = this.optionalText(item, maxLength);
      if (!normalized) continue;
      if (seen.has(normalized)) continue;
      seen.add(normalized);
      result.push(normalized);
    }
    if (result.length === 0) throw new BadRequestException(message);
    return result;
  }

  private normalizeDomainOptions(listValue: unknown, singleValue: unknown) {
    const values = Array.isArray(listValue) ? listValue : [];
    return this.normalizeOptions(values, singleValue, (value) =>
      this.normalizeOptionalDomain(value),
    );
  }

  private normalizeOptions(
    listValue: unknown[],
    singleValue: unknown,
    normalize: (value: unknown) => string | null,
  ) {
    const seen = new Set<string>();
    const result: Array<string | null> = [];
    const add = (value: unknown) => {
      const normalized = normalize(value);
      if (!normalized) return;
      const key = normalized.toUpperCase();
      if (seen.has(key)) return;
      seen.add(key);
      result.push(normalized);
    };
    listValue.forEach(add);
    add(singleValue);
    return result.length === 0 ? [null] : result;
  }

  private async normalizeLocationOptions(
    regionCodes: Array<string | null>,
    areaCodes: Array<string | null>,
  ) {
    const selectedRegions = regionCodes.filter((code): code is string =>
      Boolean(code),
    );
    const selectedAreas = areaCodes.filter((code): code is string =>
      Boolean(code),
    );

    if (selectedRegions.length === 0 && selectedAreas.length === 0) {
      return [{ regionCode: null, areaCode: null }];
    }
    if (selectedAreas.length === 0) {
      return selectedRegions.map((regionCode) => ({
        regionCode,
        areaCode: null,
      }));
    }
    if (selectedRegions.length === 0) {
      return selectedAreas.map((areaCode) => ({ regionCode: null, areaCode }));
    }

    const locations: Array<{ regionCode: string; areaCode: string }> = [];
    for (const areaCode of selectedAreas) {
      const area = await this.prisma.areaDefinition.findUnique({
        where: { code: areaCode },
      });
      if (!area) throw new BadRequestException('Vùng không tồn tại');
      if (selectedRegions.includes(area.regionCode)) {
        locations.push({ regionCode: area.regionCode, areaCode });
      }
    }
    if (locations.length === 0) {
      throw new BadRequestException('Vùng không thuộc Miền đã chọn');
    }
    return locations;
  }

  private expandRuleBatch(input: {
    featureCode: string;
    enabled: boolean;
    note: string | null;
    emailDomains: Array<string | null>;
    systemRoles: Array<string | null>;
    departmentCodes: Array<string | null>;
    jobRoleCodes: Array<string | null>;
    workScopeTypes: Array<string | null>;
    locations: Array<{ regionCode: string | null; areaCode: string | null }>;
    organizationNodeIds: Array<string | null>;
    storeCodes: Array<string | null>;
    userIds: Array<string | null>;
  }) {
    const dataList: any[] = [];
    for (const emailDomain of input.emailDomains) {
      for (const systemRole of input.systemRoles) {
        for (const departmentCode of input.departmentCodes) {
          for (const jobRoleCode of input.jobRoleCodes) {
            for (const workScopeType of input.workScopeTypes) {
              for (const location of input.locations) {
                for (const organizationNodeId of input.organizationNodeIds) {
                  for (const storeCode of input.storeCodes) {
                    for (const userId of input.userIds) {
                      dataList.push({
                        featureCode: input.featureCode,
                        enabled: input.enabled,
                        emailDomain,
                        systemRole,
                        departmentCode,
                        jobRoleCode,
                        workScopeType,
                        regionCode: location.regionCode,
                        areaCode: location.areaCode,
                        organizationNodeId,
                        storeCode,
                        userId,
                        note: input.note,
                      });
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    return dataList;
  }

  private async validateRuleReferences(data: {
    systemRole: string | null;
    departmentCode: string | null;
    jobRoleCode: string | null;
    regionCode: string | null;
    areaCode: string | null;
    organizationNodeId: string | null;
    storeCode: string | null;
    userId: string | null;
  }) {
    if (data.systemRole) {
      const role = await this.prisma.roleDefinition.findUnique({
        where: { code: data.systemRole },
      });
      if (!role)
        throw new BadRequestException('Vai trò hệ thống không tồn tại');
    }
    if (data.departmentCode) {
      const department = await this.prisma.departmentDefinition.findUnique({
        where: { code: data.departmentCode },
      });
      if (!department) throw new BadRequestException('Phòng ban không tồn tại');
    }
    if (data.jobRoleCode) {
      const jobRole = await this.prisma.jobRoleDefinition.findUnique({
        where: { code: data.jobRoleCode },
      });
      if (!jobRole) throw new BadRequestException('Chức danh không tồn tại');
    }
    if (data.regionCode) {
      const region = await this.prisma.regionDefinition.findUnique({
        where: { code: data.regionCode },
      });
      if (!region) throw new BadRequestException('Miền không tồn tại');
    }
    if (data.areaCode) {
      const area = await this.prisma.areaDefinition.findUnique({
        where: { code: data.areaCode },
      });
      if (!area) throw new BadRequestException('Vùng không tồn tại');
      if (data.regionCode && area.regionCode !== data.regionCode) {
        throw new BadRequestException('Vùng không thuộc Miền đã chọn');
      }
    }
    if (data.organizationNodeId) {
      const organizationNode = await this.prisma.organizationNode.findUnique({
        where: { id: data.organizationNodeId },
        select: { id: true, isActive: true },
      });
      if (!organizationNode || !organizationNode.isActive) {
        throw new BadRequestException('Node tổ chức không tồn tại hoặc đã tắt');
      }
    }
    if (data.storeCode) {
      const store = await this.prisma.store.findUnique({
        where: { storeId: data.storeCode },
      });
      if (!store) throw new BadRequestException('SR không tồn tại');
    }
    if (data.userId) {
      const user = await this.prisma.user.findUnique({
        where: { id: data.userId },
      });
      if (!user) throw new BadRequestException('User không tồn tại');
    }
  }

  private async ensureFeature(code: string) {
    const feature = await this.prisma.featureDefinition.findUnique({
      where: { code },
    });
    if (!feature) throw new BadRequestException('Tính năng không tồn tại');
  }

  private async ensureFeaturesExist(featureCodes: string[]) {
    const features = await this.prisma.featureDefinition.findMany({
      where: { code: { in: featureCodes } },
      select: { code: true },
    });
    const found = new Set(features.map((feature) => feature.code));
    const missing = featureCodes.filter(
      (featureCode) => !found.has(featureCode),
    );
    if (missing.length > 0) {
      throw new BadRequestException(
        'Tính năng không tồn tại: ' + missing.join(', '),
      );
    }
  }

  private async normalizeFeatureTreeCodeList(value: unknown) {
    const requestedCodes = Array.from(
      new Set(
        (Array.isArray(value) ? value : [])
          .map((item) => this.normalizeOptionalCode(item))
          .filter((code): code is string => Boolean(code)),
      ),
    );
    if (requestedCodes.length === 0) return [];

    const features = await this.prisma.featureDefinition.findMany({
      select: { code: true, parentCode: true },
    });
    const byCode = new Map(
      features.map((feature) => [feature.code, feature.parentCode ?? null]),
    );
    const missing = requestedCodes.filter((code) => !byCode.has(code));
    if (missing.length > 0) {
      throw new BadRequestException(
        'Tính năng không tồn tại: ' + missing.join(', '),
      );
    }

    const expanded = new Set<string>();
    for (const code of requestedCodes) {
      let cursor: string | null = code;
      for (let guard = 0; cursor && guard < 50; guard += 1) {
        expanded.add(cursor);
        cursor = byCode.get(cursor) ?? null;
      }
    }
    return Array.from(expanded).sort();
  }

  private async resolveContext(user: any): Promise<FeatureContext> {
    if (!user?.id) {
      return {
        id: user?.id ?? null,
        email: user?.email ?? null,
        emailDomain: this.emailDomainFromEmail(user?.email),
        role: this.normalizeSystemRole(user?.role),
        departmentCode: user?.departmentCode ?? null,
        jobRoleCode: user?.jobRoleCode ?? null,
        workScopeType: this.effectiveScope(user),
      };
    }

    const full = await this.prisma.user.findUnique({
      where: { id: user.id },
      include: {
        organizationNode: true,
        store: {
          include: {
            area: { include: { region: true } },
            organizationNode: true,
          },
        },
        region: true,
        area: { include: { region: true } },
        organizationAssignments: {
          where: { isActive: true },
          orderBy: [
            { isPrimary: Prisma.SortOrder.desc },
            { createdAt: Prisma.SortOrder.asc },
          ],
          include: {
            organizationNode: {
              include: {
                stores: { orderBy: { storeId: Prisma.SortOrder.asc } },
              },
            },
          },
        },
      },
    });
    const source = full ?? user;
    const scopeNodeId =
      source.organizationNodeId ?? source.store?.organizationNodeId;
    const organizationContext =
      await this.resolveOrganizationRuleContext(scopeNodeId);
    const area = this.areaForContextSource(source);
    const region = this.regionForContextSource(source);
    const baseContext: FeatureContext = {
      id: source.id ?? null,
      email: source.email ?? null,
      emailDomain: this.emailDomainFromEmail(source.email),
      role: this.normalizeSystemRole(source.role),
      departmentCode: source.departmentCode ?? null,
      jobRoleCode: source.jobRoleCode ?? null,
      workScopeType: this.effectiveScope(source),
      regionCode:
        organizationContext.regionCode ??
        region?.code ??
        source.regionCode ??
        null,
      areaCode:
        organizationContext.areaCode ?? area?.code ?? source.areaCode ?? null,
      organizationNodeId: organizationContext.organizationNodeId,
      organizationNodeIds: organizationContext.organizationNodeIds,
      organizationNodeActive: organizationContext.organizationNodeActive,
      organizationScopeRootId: organizationContext.scopeRootNodeId,
      organizationNodeType: organizationContext.nodeType,
      organizationNodeKey: organizationContext.nodeKey,
      organizationNodeFeatureTargets: organizationContext.nodeFeatureTargets,
      storeCode: organizationContext.storeCode ?? source.store?.storeId ?? null,
      storeName: source.store?.storeName ?? null,
    };
    baseContext.alternateContexts = await this.resolveAlternateFeatureContexts(
      source,
      baseContext.organizationNodeId,
    );
    return baseContext;
  }

  private async resolveAlternateFeatureContexts(
    source: any,
    primaryOrganizationNodeId?: string | null,
  ) {
    const assignments = Array.isArray(source?.organizationAssignments)
      ? source.organizationAssignments
      : [];
    const seen = new Set<string>(
      [primaryOrganizationNodeId].filter(Boolean) as string[],
    );
    const contexts: FeatureContext[] = [];
    for (const assignment of assignments) {
      const nodeId = String(assignment?.organizationNodeId || '').trim();
      if (!nodeId || seen.has(nodeId)) continue;
      seen.add(nodeId);
      const organizationContext =
        await this.resolveOrganizationRuleContext(nodeId);
      const assignmentStore = assignment?.organizationNode?.stores?.[0] ?? null;
      contexts.push({
        id: source.id ?? null,
        email: source.email ?? null,
        emailDomain: this.emailDomainFromEmail(source.email),
        role: this.normalizeSystemRole(source.role),
        departmentCode: source.departmentCode ?? null,
        jobRoleCode: source.jobRoleCode ?? null,
        workScopeType: this.effectiveScope(source),
        regionCode: organizationContext.regionCode ?? source.regionCode ?? null,
        areaCode: organizationContext.areaCode ?? source.areaCode ?? null,
        organizationNodeId: organizationContext.organizationNodeId,
        organizationNodeIds: organizationContext.organizationNodeIds,
        organizationNodeActive: organizationContext.organizationNodeActive,
        organizationScopeRootId: organizationContext.scopeRootNodeId,
        organizationNodeType: organizationContext.nodeType,
        organizationNodeKey: organizationContext.nodeKey,
        organizationNodeFeatureTargets: organizationContext.nodeFeatureTargets,
        storeCode:
          organizationContext.storeCode ??
          assignmentStore?.storeId ??
          source.storeCode ??
          null,
        storeName: assignmentStore?.storeName ?? null,
      });
    }
    return contexts;
  }

  private async resolveOrganizationRuleContext(nodeId?: string | null) {
    const empty = {
      organizationNodeId: nodeId ?? null,
      organizationNodeIds: [] as string[],
      organizationNodeActive: false,
      scopeRootNodeId: null as string | null,
      nodeType: null as string | null,
      nodeKey: null as string | null,
      nodeFeatureTargets: [] as FeatureNodeTarget[],
      regionCode: null as string | null,
      areaCode: null as string | null,
      storeCode: null as string | null,
    };
    if (!nodeId) return empty;
    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return empty;
    const nodes: Array<{
      id: string;
      parentId: string | null;
      type: string;
      code: string;
      businessCode: string | null;
      isActive: boolean;
    }> = await organizationNode.findMany({
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
        isActive: true,
      },
    });
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const ancestors: typeof nodes = [];
    let cursor = byId.get(nodeId) ?? null;
    const directNode = cursor;
    if (!directNode) return empty;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      ancestors.push(cursor);
      cursor = cursor.parentId ? (byId.get(cursor.parentId) ?? null) : null;
    }
    const businessCodeFor = (...types: string[]) => {
      const node = ancestors.find((item) => types.includes(item.type));
      if (!node) return null;
      return (
        node.businessCode || this.legacyCodeFromOrganizationCode(node.code)
      );
    };
    const scopeRootNodeId = this.rootNodeIdForNode(nodes, nodeId);
    return {
      organizationNodeId: nodeId,
      organizationNodeIds: ancestors.map((node) => node.id),
      organizationNodeActive: directNode.isActive === true,
      scopeRootNodeId,
      nodeType: this.normalizeNodeType(directNode.type),
      nodeKey: this.nodeFeatureKey(directNode),
      nodeFeatureTargets: scopeRootNodeId
        ? this.nodeFeatureTargetsForAccess(ancestors, scopeRootNodeId)
        : [],
      regionCode: businessCodeFor('LV2_REGION', 'REGION'),
      areaCode: businessCodeFor('LV3_AREA', 'AREA'),
      storeCode: businessCodeFor('LV4_STORE', 'SHOWROOM'),
    };
  }

  private nodeFeatureTargetsForAccess(
    ancestors: Array<{
      id: string;
      type: string;
      code: string;
      businessCode: string | null;
      isActive?: boolean | null;
    }>,
    scopeRootNodeId: string,
  ) {
    return ancestors
      .filter((node, index) => {
        const nodeType = this.normalizeNodeType(node.type);
        return index === 0 || nodeType !== 'LV0_DOMAIN';
      })
      .map((node) => ({
        scopeRootNodeId,
        nodeType: this.normalizeNodeType(node.type),
        nodeKey: this.nodeFeatureKey(node),
        organizationNodeId: node.id,
      }));
  }

  private legacyCodeFromOrganizationCode(code: string) {
    return String(code || '')
      .replace(/^(LV2_REGION|LV3_AREA|REGION|AREA)_(PHONGVU|ACARE)_/i, '')
      .replace(/^STORE_/i, '')
      .trim()
      .toUpperCase();
  }

  private areaForContextSource(source: any) {
    if (this.effectiveScope(source) === 'STORE') {
      return source?.store?.area ?? source?.area ?? null;
    }
    return source?.area ?? source?.store?.area ?? null;
  }

  private regionForContextSource(source: any) {
    if (this.effectiveScope(source) === 'STORE') {
      const storeArea = source?.store?.area ?? null;
      return (
        storeArea?.region ?? source?.region ?? source?.area?.region ?? null
      );
    }
    const area = this.areaForContextSource(source);
    return (
      source?.region ?? area?.region ?? source?.store?.area?.region ?? null
    );
  }

  private effectiveScope(user: any) {
    const scope = String(user?.workScopeType || '')
      .trim()
      .toUpperCase();
    if (VALID_WORK_SCOPES.has(scope)) return scope;
    const role = this.normalizeSystemRole(user?.role);
    if (role === SUPER_ADMIN_ROLE || role === ADMIN_ROLE) {
      return 'NATIONAL';
    }
    return 'STORE';
  }

  private normalizeSystemRole(role: unknown) {
    return normalizeSystemRoleCode(role);
  }

  private normalizeCode(value: unknown, message: string) {
    const code = String(value || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    if (!/^[A-Z][A-Z0-9_]{1,59}$/.test(code)) {
      throw new BadRequestException(message);
    }
    return code;
  }

  private normalizeOptionalCode(value: unknown) {
    if (value === undefined || value === null || String(value).trim() === '') {
      return null;
    }
    return this.normalizeCode(value, 'Mã lọc rule không hợp lệ');
  }

  private normalizeSortOrder(value: unknown) {
    const parsed = Number(value ?? 0);
    if (!Number.isFinite(parsed)) return 0;
    return Math.max(0, Math.min(10000, Math.trunc(parsed)));
  }

  private normalizeOptionalDomain(value: unknown) {
    if (value === undefined || value === null || String(value).trim() === '') {
      return null;
    }
    const domain = String(value).trim().replace(/^@+/, '').toLowerCase();
    if (domain.length > 120 || !this.isValidEmailDomain(domain)) {
      throw new BadRequestException('Domain email khong hop le');
    }
    return domain;
  }

  private emailDomainFromEmail(email: unknown) {
    const value = String(email || '')
      .trim()
      .toLowerCase();
    const atIndex = value.lastIndexOf('@');
    if (atIndex < 0) return null;
    const domain = value.slice(atIndex + 1);
    return this.isValidEmailDomain(domain) ? domain : null;
  }

  private requiredText(value: unknown, message: string, maxLength: number) {
    const text = String(value || '').trim();
    if (!text) throw new BadRequestException(message);
    return text.slice(0, maxLength);
  }

  private optionalText(value: unknown, maxLength: number) {
    if (value === undefined || value === null) return null;
    const text = String(value || '').trim();
    return text ? text.slice(0, maxLength) : null;
  }

  private isValidEmailDomain(domain: string) {
    return /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/.test(
      domain,
    );
  }

  private adminLogId(admin: any) {
    const userId = this.optionalText(admin?.id, 80);
    if (userId) return `userId:${userId}`;
    const email = String(admin?.email || '')
      .trim()
      .toLowerCase();
    return email ? `emailHash:${logFingerprint(email)}` : 'unknown';
  }

  private assertSuperAdmin(user: any) {
    if (!isSuperAdminRole(user?.role)) {
      throw new ForbiddenException('Bạn không có quyền quản lý tính năng');
    }
  }
}
