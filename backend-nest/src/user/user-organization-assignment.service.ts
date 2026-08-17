import {
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const STORE_SCOPE = 'STORE';
const AREA_SCOPE = 'AREA';
const REGION_SCOPE = 'REGION';
const NATIONAL_SCOPE = 'NATIONAL';

const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';

const DEFAULT_REGION_CODE = 'CHUA_GAN';
const ORG_TYPE_LV2_DEPARTMENT = 'LV2_DEPARTMENT';
const ORG_TYPE_LV2_REGION = 'LV2_REGION';
const ORG_TYPE_LV3_AREA = 'LV3_AREA';
const ORG_TYPE_LV4_STORE = 'LV4_STORE';
const ORG_TYPE_LV5_POSITION = 'LV5_POSITION';

export type OrganizationScopeContext = {
  organizationNodeId: string;
  nodeType: string;
  departmentCode: string | null;
  jobRoleCode: string | null;
  regionCode: string | null;
  areaCode: string | null;
  storeCode: string | null;
  storeNodeId: string | null;
};

export type UserOrganizationAssignmentRuntime = {
  isScopedAdmin: (admin: any) => boolean;
  storeWithinAdminScope: (admin: any, store: any) => Promise<boolean>;
  adminOrgRootId: (admin: any) => string | null;
  organizationDescendantIds: (rootId: string) => Promise<string[]>;
  userLogId: (user: any) => string;
  normalizeOrganizationNodeType: (value: unknown) => string;
  normalizeStoreCode: (value: string) => string;
  legacyCodeFromOrganizationCode: (code: string) => string;
  legacyPersonnelCodeFromOrganizationNode: (
    node: any,
    message: string,
  ) => string | null;
  defaultDepartmentCodeForJobRole: (
    jobRoleCode: string | null,
  ) => string | null;
  isLegacyPositionNodeType: (type: string) => boolean;
  syncLegacyCatalogFromOrganizationNode: (
    client: any,
    node: any,
  ) => Promise<void>;
  defaultStoreCashNodeIdForStore: (store: any) => Promise<string | null>;
  resolveDepartmentCode: (
    input: unknown,
    current?: string | null,
  ) => Promise<string | null>;
  resolveJobRoleCode: (
    input: unknown,
    current?: string | null,
  ) => Promise<string | null>;
  normalizePersonnelCode: (input: unknown, message: string) => string | null;
  resolveWorkScopeType: (
    input: unknown,
    current: string | null | undefined,
    role: string,
  ) => string;
  defaultWorkScopeForRole: (role: string) => string;
  logger: Pick<Logger, 'log' | 'warn'>;
};

/**
 * Owns organization-tree based user assignment resolution while UserService
 * remains the stable public facade. All policy and catalog helpers are passed
 * explicitly so this collaborator cannot reach into UserService state.
 */
export class UserOrganizationAssignmentService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly runtime: UserOrganizationAssignmentRuntime,
  ) {}

  async resolveUserAssignmentStoreUuid(
    admin: any,
    body: any,
    options: { current?: any; workScopeType: string },
  ) {
    if (options.workScopeType !== STORE_SCOPE) return null;
    if (body.organizationNodeId === undefined) {
      if (options.current && body.workScopeType === undefined) {
        return options.current.storeId ?? null;
      }
      throw new BadRequestException('Vui lòng chọn showroom trên cây tổ chức');
    }

    const scopeLocation = await this.resolveScopeLocationFromOrganizationNode(
      admin,
      body.organizationNodeId,
      STORE_SCOPE,
    );
    const store = await this.prisma.store.findFirst({
      where: { organizationNodeId: scopeLocation.storeNodeId },
      include: { area: { include: { region: true } } },
    });
    if (!store) {
      throw new BadRequestException('Showroom chưa được gắn SR');
    }
    if (
      this.runtime.isScopedAdmin(admin) &&
      !(await this.runtime.storeWithinAdminScope(admin, store))
    ) {
      throw new ForbiddenException(
        'Bạn chỉ được gán người dùng trong phạm vi quản lý',
      );
    }
    return store.id;
  }

  async resolveUserOrganizationAssignmentNodeIds(
    admin: any,
    body: any,
    current: any | null,
  ) {
    const nodeIds = this.normalizedOrganizationNodeIdInput(body, current);
    if (nodeIds.length === 0) return [];

    const contexts: OrganizationScopeContext[] = [];
    for (const nodeId of nodeIds) {
      const context = await this.organizationScopeContext(nodeId);
      await this.assertOrganizationNodeAssignableByAdmin(
        admin,
        context.organizationNodeId,
      );
      contexts.push(context);
    }

    if (contexts.length > 1) {
      const invalid = contexts.find((context) => !context.storeNodeId);
      if (invalid) {
        throw new BadRequestException(
          'Khi gán nhiều SR, mỗi lựa chọn phải là showroom hoặc vị trí trong showroom',
        );
      }
    }

    return nodeIds;
  }

  normalizedOrganizationNodeIdInput(body: any, current: any | null) {
    if (body.organizationNodeIds !== undefined) {
      return this.normalizeOrganizationNodeIds(body.organizationNodeIds);
    }
    if (body.organizationNodeId !== undefined) {
      return this.normalizeOrganizationNodeIds([body.organizationNodeId]);
    }
    const currentAssignments = Array.isArray(current?.organizationAssignments)
      ? current.organizationAssignments
      : [];
    const activeAssignmentIds = currentAssignments
      .filter((assignment: any) => assignment?.isActive !== false)
      .map((assignment: any) => assignment.organizationNodeId)
      .filter(Boolean);
    if (activeAssignmentIds.length > 0) {
      return this.normalizeOrganizationNodeIds(activeAssignmentIds);
    }
    return this.normalizeOrganizationNodeIds([
      current?.organizationNodeId ?? current?.store?.organizationNodeId,
    ]);
  }

  normalizeOrganizationNodeIds(value: unknown) {
    const rawItems = Array.isArray(value)
      ? value
      : String(value ?? '')
          .split(/[;,]/)
          .map((item) => item.trim());
    const seen = new Set<string>();
    const result: string[] = [];
    for (const item of rawItems) {
      const nodeId = String(item ?? '').trim();
      if (!nodeId || seen.has(nodeId)) continue;
      if (nodeId.length > 80) {
        throw new BadRequestException('Đơn vị tổ chức không hợp lệ');
      }
      seen.add(nodeId);
      result.push(nodeId);
    }
    return result;
  }

  async syncUserOrganizationAssignments(
    client: Prisma.TransactionClient,
    userId: string,
    organizationNodeIds: string[],
    admin: any,
  ) {
    const assignmentModel = (client as any).userOrganizationAssignment;
    if (!assignmentModel?.upsert) return;
    const selected = new Set(organizationNodeIds);
    await assignmentModel.updateMany({
      where: {
        userId,
        ...(organizationNodeIds.length > 0
          ? { organizationNodeId: { notIn: organizationNodeIds } }
          : {}),
      },
      data: { isActive: false, isPrimary: false },
    });
    for (const [index, organizationNodeId] of organizationNodeIds.entries()) {
      await assignmentModel.upsert({
        where: {
          userId_organizationNodeId: { userId, organizationNodeId },
        },
        create: {
          userId,
          organizationNodeId,
          isPrimary: index === 0,
          isActive: true,
          assignedById: admin?.id ?? null,
          note: 'Admin user assignment',
        },
        update: {
          isPrimary: index === 0,
          isActive: true,
          assignedById: admin?.id ?? null,
        },
      });
    }
    if (selected.size > 0) {
      this.runtime.logger.log(
        `User organization assignments synced: userId=${userId} count=${selected.size}`,
      );
    }
  }

  async resolvePersonnelAssignment(
    admin: any,
    body: any,
    options: {
      current?: any;
      role: string;
      storeUuid?: string | null;
      workScopeType: string;
    },
  ) {
    const treePersonnel =
      body.organizationNodeId !== undefined
        ? await this.resolvePersonnelCodesFromOrganizationNode(
            body.organizationNodeId,
          )
        : null;
    const departmentCode = treePersonnel
      ? treePersonnel.departmentCode
      : await this.runtime.resolveDepartmentCode(
          body.departmentCode,
          options.current?.departmentCode ?? null,
        );
    const jobRoleCode = treePersonnel
      ? treePersonnel.jobRoleCode
      : await this.runtime.resolveJobRoleCode(
          body.jobRoleCode,
          options.current?.jobRoleCode ?? null,
        );
    const scopeLocation = await this.resolveScopeLocation(admin, body, {
      current: options.current,
      storeUuid: options.storeUuid,
      role: options.role,
      workScopeType: options.workScopeType,
    });

    return {
      departmentCode,
      jobRoleCode,
      workScopeType: options.workScopeType,
      ...scopeLocation,
    };
  }

  async resolveScopeLocation(
    admin: any,
    body: any,
    options: {
      current?: any;
      role: string;
      storeUuid?: string | null;
      workScopeType: string;
    },
  ) {
    if (options.workScopeType === NATIONAL_SCOPE) {
      if (body.organizationNodeId === undefined) {
        if (options.current && body.workScopeType === undefined) {
          return {
            regionCode: null,
            areaCode: null,
            organizationNodeId: options.current.organizationNodeId ?? null,
          };
        }
        if (options.role === SUPER_ADMIN_ROLE) {
          return { regionCode: null, areaCode: null, organizationNodeId: null };
        }
        throw new BadRequestException('Vui lòng chọn domain gốc');
      }

      const nodeId = String(body.organizationNodeId || '').trim();
      if (!nodeId) {
        if (options.role === SUPER_ADMIN_ROLE) {
          return { regionCode: null, areaCode: null, organizationNodeId: null };
        }
        throw new BadRequestException('Vui lòng chọn domain gốc');
      }

      return this.resolveScopeLocationFromOrganizationNode(
        admin,
        nodeId,
        NATIONAL_SCOPE,
      );
    }

    if (options.workScopeType === STORE_SCOPE) {
      if (body.organizationNodeId !== undefined) {
        const scopeLocation =
          await this.resolveScopeLocationFromOrganizationNode(
            admin,
            body.organizationNodeId,
            STORE_SCOPE,
          );
        const store = options.storeUuid
          ? await this.prisma.store.findUnique({
              where: { id: options.storeUuid },
              include: { area: { include: { region: true } } },
            })
          : null;
        return {
          ...scopeLocation,
          areaCode:
            scopeLocation.areaCode ?? store?.areaCode ?? DEFAULT_REGION_CODE,
          regionCode:
            scopeLocation.regionCode ??
            store?.area?.regionCode ??
            DEFAULT_REGION_CODE,
        };
      }
      const store = options.storeUuid
        ? await this.prisma.store.findUnique({
            where: { id: options.storeUuid },
            include: {
              area: { include: { region: true } },
              organizationNode: true,
            },
          })
        : null;
      const areaCode = store?.areaCode ?? DEFAULT_REGION_CODE;
      const regionCode = store?.area?.regionCode ?? DEFAULT_REGION_CODE;
      const organizationNodeId =
        (await this.runtime.defaultStoreCashNodeIdForStore(store)) ??
        store?.organizationNodeId ??
        null;
      return {
        regionCode,
        areaCode,
        organizationNodeId,
        storeNodeId: store?.organizationNodeId ?? null,
      };
    }

    if (body.organizationNodeId === undefined) {
      if (options.current && body.workScopeType === undefined) {
        return {
          regionCode: options.current.regionCode ?? null,
          areaCode: options.current.areaCode ?? null,
          organizationNodeId: options.current.organizationNodeId ?? null,
        };
      }
      throw new BadRequestException('Vui lòng chọn đơn vị tổ chức');
    }

    return this.resolveScopeLocationFromOrganizationNode(
      admin,
      body.organizationNodeId,
      options.workScopeType,
    );
  }

  async resolveScopeLocationFromOrganizationNode(
    admin: any,
    nodeIdInput: unknown,
    workScopeType: string,
  ) {
    const nodeId = String(nodeIdInput || '').trim();
    if (!nodeId) throw new BadRequestException('Vui lòng chọn đơn vị tổ chức');
    const context = await this.organizationScopeContext(nodeId);
    if (workScopeType === STORE_SCOPE && !context.storeNodeId) {
      throw new BadRequestException('Vui lòng chọn showroom');
    }
    await this.assertOrganizationNodeAssignableByAdmin(
      admin,
      context.organizationNodeId,
    );
    if (
      workScopeType === NATIONAL_SCOPE &&
      !context.regionCode &&
      !context.areaCode
    ) {
      return {
        regionCode: null,
        areaCode: null,
        organizationNodeId: context.organizationNodeId,
        storeNodeId: context.storeNodeId,
      };
    }
    return {
      regionCode: context.regionCode,
      areaCode: context.areaCode,
      organizationNodeId: context.organizationNodeId,
      storeNodeId: context.storeNodeId,
    };
  }

  async resolvePersonnelCodesFromOrganizationNode(nodeIdInput: unknown) {
    const nodeId = String(nodeIdInput || '').trim();
    if (!nodeId) return { departmentCode: null, jobRoleCode: null };
    const context = await this.organizationScopeContext(nodeId);
    const departmentCode = context.departmentCode
      ? await this.runtime.resolveDepartmentCode(context.departmentCode, null)
      : null;
    let jobRoleCode: string | null = null;
    if (context.jobRoleCode) {
      const normalizedJobRoleCode = this.runtime.normalizePersonnelCode(
        context.jobRoleCode,
        'Mã chức danh không hợp lệ',
      );
      const jobRole = normalizedJobRoleCode
        ? await this.prisma.jobRoleDefinition.findUnique({
            where: { code: normalizedJobRoleCode },
          })
        : null;
      if (jobRole?.isActive) {
        jobRoleCode = jobRole.code;
      } else {
        const selectedNode = await this.prisma.organizationNode.findUnique({
          where: { id: context.organizationNodeId },
        });
        if (
          !selectedNode ||
          !this.runtime.isLegacyPositionNodeType(selectedNode.type) ||
          selectedNode.isActive === false
        ) {
          throw new BadRequestException('Chức danh không tồn tại hoặc đã tắt');
        }
        await this.runtime.syncLegacyCatalogFromOrganizationNode(
          this.prisma,
          selectedNode,
        );
        jobRoleCode = normalizedJobRoleCode;
        this.runtime.logger.log(
          `Organization position catalog repaired for user assignment: nodeId=${selectedNode.id} jobRole=${jobRoleCode}`,
        );
      }
    }
    return { departmentCode, jobRoleCode };
  }

  async assertOrganizationNodeAssignableByAdmin(admin: any, nodeId: string) {
    const rootId = this.runtime.adminOrgRootId(admin);
    if (!rootId) return;
    const organizationNodeIds =
      await this.runtime.organizationDescendantIds(rootId);
    if (organizationNodeIds.includes(nodeId)) return;
    this.runtime.logger.warn(
      'Admin user scope assignment blocked by domain: admin=' +
        this.runtime.userLogId(admin) +
        ' role=' +
        admin?.role +
        ' nodeId=' +
        nodeId +
        ' allowedRootId=' +
        rootId,
    );
    throw new ForbiddenException(
      'Bạn chỉ được gán người dùng trong phạm vi quản lý',
    );
  }

  async organizationScopeContext(
    nodeId: string,
  ): Promise<OrganizationScopeContext> {
    const nodes: Array<{
      id: string;
      parentId: string | null;
      type: string;
      code: string;
      businessCode: string | null;
      isActive: boolean;
    }> = await this.prisma.organizationNode.findMany({
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
      throw new BadRequestException('Đơn vị tổ chức không tồn tại hoặc đã tắt');
    }
    const ancestors: typeof nodes = [];
    let cursor: (typeof nodes)[number] | null = node;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      ancestors.push(cursor);
      cursor = cursor.parentId ? (byId.get(cursor.parentId) ?? null) : null;
    }
    const businessCodeFor = (type: string) => {
      const item = ancestors.find(
        (ancestor) =>
          this.runtime.normalizeOrganizationNodeType(ancestor.type) === type,
      );
      if (!item) return null;
      if (type === ORG_TYPE_LV4_STORE) {
        return this.runtime.normalizeStoreCode(
          item.businessCode ??
            this.runtime.legacyCodeFromOrganizationCode(item.code),
        );
      }
      return this.runtime.legacyPersonnelCodeFromOrganizationNode(
        item,
        'Mã nghiệp vụ không hợp lệ',
      );
    };
    const storeNode = ancestors.find(
      (ancestor) =>
        this.runtime.normalizeOrganizationNodeType(ancestor.type) ===
        ORG_TYPE_LV4_STORE,
    );
    const jobRoleCode = businessCodeFor(ORG_TYPE_LV5_POSITION);
    return {
      organizationNodeId: node.id,
      nodeType: this.runtime.normalizeOrganizationNodeType(node.type),
      departmentCode:
        businessCodeFor(ORG_TYPE_LV2_DEPARTMENT) ??
        this.runtime.defaultDepartmentCodeForJobRole(jobRoleCode),
      jobRoleCode,
      regionCode: businessCodeFor(ORG_TYPE_LV2_REGION),
      areaCode: businessCodeFor(ORG_TYPE_LV3_AREA),
      storeCode: businessCodeFor(ORG_TYPE_LV4_STORE),
      storeNodeId: storeNode?.id ?? null,
    };
  }

  async resolveWorkScopeTypeForAssignment(
    body: any,
    current: any | null,
    role: string,
  ) {
    if (body.workScopeType !== undefined) {
      return this.runtime.resolveWorkScopeType(
        body.workScopeType,
        current?.workScopeType,
        role,
      );
    }
    if (body.organizationNodeId !== undefined) {
      const nodeId = String(body.organizationNodeId || '').trim();
      if (!nodeId) return this.runtime.defaultWorkScopeForRole(role);
      const context = await this.organizationScopeContext(nodeId);
      return this.workScopeTypeFromOrganizationContext(context);
    }
    return this.runtime.resolveWorkScopeType(
      undefined,
      current?.workScopeType,
      role,
    );
  }

  private workScopeTypeFromOrganizationContext(context: {
    nodeType: string;
    regionCode?: string | null;
    areaCode?: string | null;
    storeNodeId?: string | null;
  }) {
    if (context.storeNodeId || context.nodeType === ORG_TYPE_LV4_STORE) {
      return STORE_SCOPE;
    }
    if (context.nodeType === ORG_TYPE_LV5_POSITION && context.storeNodeId) {
      return STORE_SCOPE;
    }
    if (context.nodeType === ORG_TYPE_LV3_AREA || context.areaCode) {
      return AREA_SCOPE;
    }
    if (
      context.nodeType === ORG_TYPE_LV2_REGION ||
      context.nodeType === ORG_TYPE_LV2_DEPARTMENT ||
      context.regionCode
    ) {
      return REGION_SCOPE;
    }
    return NATIONAL_SCOPE;
  }
}
