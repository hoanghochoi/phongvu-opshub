import { BadRequestException, Logger } from '@nestjs/common';

export type UserLegacyCatalogRuntime = {
  isLegacyDepartmentNodeType: (type: string) => boolean;
  isLegacyPositionNodeType: (type: string) => boolean;
  isLegacyRegionNodeType: (type: string) => boolean;
  isLegacyAreaNodeType: (type: string) => boolean;
  normalizePersonnelCode: (input: unknown, message: string) => string | null;
  normalizeRequiredText: (
    value: string | undefined,
    message: string,
    maxLength: number,
  ) => string;
  normalizeCatalogAbbreviation: (value: unknown) => string;
  defaultDepartmentCodeForPosition: (
    businessCode: string | null | undefined,
  ) => string | null;
  logger: Pick<Logger, 'warn'>;
};

type OrganizationNode = {
  id: string;
  code: string;
  businessCode?: string | null;
  displayName?: string | null;
  name?: string | null;
  abbreviation?: string | null;
  description?: string | null;
  type: string;
  parentId?: string | null;
  isSystem?: boolean;
  isActive?: boolean;
};

/**
 * Keeps legacy department/position/region/area rows in sync while the
 * organization-node tree remains the current source of truth. The caller
 * supplies the Prisma client so every upsert stays inside its transaction.
 */
export class UserLegacyCatalogService {
  constructor(private readonly runtime: UserLegacyCatalogRuntime) {}

  async syncLegacyCatalogFromOrganizationNode(
    client: any,
    node: OrganizationNode,
  ) {
    const businessCode = this.runtime.normalizePersonnelCode(
      node.businessCode || this.legacyCodeFromOrganizationCode(node.code),
      'Mã nghiệp vụ không hợp lệ',
    );
    if (!businessCode) {
      throw new BadRequestException('Mã nghiệp vụ không hợp lệ');
    }

    const rawDisplayName = String(node.displayName || '').trim();
    const displayName = this.runtime.normalizeRequiredText(
      rawDisplayName || node.name || businessCode,
      'Tên đơn vị không được để trống',
      120,
    );
    if (!rawDisplayName) {
      this.runtime.logger.warn(
        `Legacy catalog sync used fallback displayName for organizationNode=${node.id} type=${node.type} code=${businessCode}`,
      );
    }

    const abbreviation = this.runtime.normalizeCatalogAbbreviation(
      node.abbreviation || businessCode,
    );
    if (this.runtime.isLegacyDepartmentNodeType(node.type)) {
      await client.departmentDefinition.upsert({
        where: { code: businessCode },
        update: {
          displayName,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isActive: node.isActive !== false,
        },
        create: {
          code: businessCode,
          displayName,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isSystem: node.isSystem === true,
          isActive: node.isActive !== false,
        },
      });
      return;
    }

    if (this.runtime.isLegacyPositionNodeType(node.type)) {
      const departmentCode = await this.departmentCodeForPositionNode(
        client,
        node,
      );
      await client.jobRoleDefinition.upsert({
        where: { code: businessCode },
        update: {
          displayName,
          description: node.description ?? null,
          departmentCode,
          isActive: node.isActive !== false,
        },
        create: {
          code: businessCode,
          displayName,
          description: node.description ?? null,
          departmentCode,
          organizationNodeId: null,
          isSystem: node.isSystem === true,
          isActive: node.isActive !== false,
        },
      });
      return;
    }

    if (this.runtime.isLegacyRegionNodeType(node.type)) {
      await client.regionDefinition.upsert({
        where: { code: businessCode },
        update: {
          displayName,
          abbreviation,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isActive: node.isActive !== false,
        },
        create: {
          code: businessCode,
          displayName,
          abbreviation,
          description: node.description ?? null,
          organizationNodeId: node.id,
          isSystem: node.isSystem === true,
          isActive: node.isActive !== false,
        },
      });
      return;
    }

    if (!this.runtime.isLegacyAreaNodeType(node.type)) return;
    const parent = node.parentId
      ? await client.organizationNode.findUnique({
          where: { id: node.parentId },
        })
      : null;
    if (!parent || !this.runtime.isLegacyRegionNodeType(parent.type)) {
      throw new BadRequestException('Vùng phải nằm dưới Miền');
    }

    await this.syncLegacyCatalogFromOrganizationNode(client, parent);
    const regionCode = this.runtime.normalizePersonnelCode(
      parent.businessCode || this.legacyCodeFromOrganizationCode(parent.code),
      'Mã Miền không hợp lệ',
    );
    if (!regionCode) {
      throw new BadRequestException('Mã Miền không hợp lệ');
    }

    await client.areaDefinition.upsert({
      where: { code: businessCode },
      update: {
        displayName,
        abbreviation,
        description: node.description ?? null,
        regionCode,
        organizationNodeId: node.id,
        isActive: node.isActive !== false,
      },
      create: {
        code: businessCode,
        displayName,
        abbreviation,
        description: node.description ?? null,
        regionCode,
        organizationNodeId: node.id,
        isSystem: node.isSystem === true,
        isActive: node.isActive !== false,
      },
    });
  }

  legacyPersonnelCodeFromOrganizationNode(
    node:
      | {
          businessCode?: string | null;
          code: string;
        }
      | null
      | undefined,
    message: string,
  ) {
    if (!node) return null;
    return this.runtime.normalizePersonnelCode(
      node.businessCode || this.legacyCodeFromOrganizationCode(node.code),
      message,
    );
  }

  legacyCodeFromOrganizationCode(code: string) {
    return String(code || '')
      .replace(/^(LV2_REGION|LV3_AREA|REGION|AREA)_(PHONGVU|ACARE)_/i, '')
      .replace(/^STORE_/i, '')
      .trim()
      .toUpperCase();
  }

  private async departmentCodeForPositionNode(
    client: any,
    node: OrganizationNode,
  ) {
    const ancestorDepartment = await this.nearestAncestorNodeOfType(
      client,
      node,
    );
    if (ancestorDepartment) {
      await this.syncLegacyCatalogFromOrganizationNode(
        client,
        ancestorDepartment,
      );
      return this.legacyPersonnelCodeFromOrganizationNode(
        ancestorDepartment,
        'Mã phòng ban không hợp lệ',
      );
    }
    return this.runtime.defaultDepartmentCodeForPosition(node.businessCode);
  }

  private async nearestAncestorNodeOfType(client: any, node: OrganizationNode) {
    const organizationNode = client.organizationNode;
    if (!organizationNode?.findUnique) return null;
    let parentId = node.parentId;
    for (let guard = 0; parentId && guard < 50; guard += 1) {
      const parent = await organizationNode.findUnique({
        where: { id: parentId },
      });
      if (!parent) return null;
      if (this.runtime.isLegacyDepartmentNodeType(parent.type)) {
        return parent;
      }
      parentId = parent.parentId;
    }
    return null;
  }
}
