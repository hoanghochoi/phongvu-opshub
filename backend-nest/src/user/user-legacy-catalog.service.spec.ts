import { BadRequestException } from '@nestjs/common';
import { UserLegacyCatalogService } from './user-legacy-catalog.service';

describe('UserLegacyCatalogService', () => {
  const normalizeType = (value: unknown) => {
    const aliases: Record<string, string> = {
      DEPARTMENT: 'LV2_DEPARTMENT',
      POSITION: 'LV5_POSITION',
      JOB_ROLE: 'LV5_POSITION',
      REGION: 'LV2_REGION',
      AREA: 'LV3_AREA',
    };
    const type = String(value || '')
      .trim()
      .toUpperCase();
    return aliases[type] ?? type;
  };

  const runtime = {
    isLegacyDepartmentNodeType: (type: string) =>
      normalizeType(type) === 'LV2_DEPARTMENT',
    isLegacyPositionNodeType: (type: string) =>
      normalizeType(type) === 'LV5_POSITION',
    isLegacyRegionNodeType: (type: string) =>
      normalizeType(type) === 'LV2_REGION',
    isLegacyAreaNodeType: (type: string) => normalizeType(type) === 'LV3_AREA',
    normalizePersonnelCode: (input: unknown, message: string) => {
      const code = String(input || '')
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9_]/g, '_');
      if (!code) return null;
      if (!/^[A-Z][A-Z0-9_]{1,39}$/.test(code)) {
        throw new BadRequestException(message);
      }
      return code;
    },
    normalizeRequiredText: (
      value: string | undefined,
      message: string,
      maxLength: number,
    ) => {
      const text = String(value || '').trim();
      if (!text) throw new BadRequestException(message);
      return text.slice(0, maxLength);
    },
    normalizeCatalogAbbreviation: (value: unknown) => {
      const abbreviation = String(value || '')
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9_]/g, '_');
      if (!/^[A-Z0-9][A-Z0-9_]{0,39}$/.test(abbreviation)) {
        throw new BadRequestException('Viết tắt không hợp lệ');
      }
      return abbreviation;
    },
    defaultDepartmentCodeForPosition: (businessCode: string | null) =>
      businessCode === 'CASH' ? 'SALES' : null,
    logger: { warn: jest.fn() },
  };

  function createClient(nodes: any[] = []) {
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const client = {
      departmentDefinition: { upsert: jest.fn() },
      jobRoleDefinition: { upsert: jest.fn() },
      regionDefinition: { upsert: jest.fn() },
      areaDefinition: { upsert: jest.fn() },
      organizationNode: {
        findUnique: jest.fn(
          async ({ where }: any) => byId.get(where.id) ?? null,
        ),
      },
    };
    return { client, byId };
  }

  it('syncs department rows and records fallback display names', async () => {
    const service = new UserLegacyCatalogService(runtime);
    const { client } = createClient();

    await service.syncLegacyCatalogFromOrganizationNode(client, {
      id: 'department-1',
      code: 'LV2_DEPARTMENT_FIN_ACC',
      businessCode: 'FIN_ACC',
      type: 'DEPARTMENT',
      isSystem: true,
      isActive: true,
    });

    expect(client.departmentDefinition.upsert).toHaveBeenCalledWith({
      where: { code: 'FIN_ACC' },
      update: expect.objectContaining({
        displayName: 'FIN_ACC',
        organizationNodeId: 'department-1',
      }),
      create: expect.objectContaining({
        code: 'FIN_ACC',
        displayName: 'FIN_ACC',
        isSystem: true,
      }),
    });
    expect(runtime.logger.warn).toHaveBeenCalledWith(
      expect.stringContaining('fallback displayName'),
    );
  });

  it('recursively syncs a region before its area and preserves the region code', async () => {
    const service = new UserLegacyCatalogService(runtime);
    const region = {
      id: 'region-1',
      code: 'REGION_PHONGVU_HCM',
      businessCode: 'HCM',
      displayName: 'Hồ Chí Minh',
      type: 'REGION',
      isActive: true,
    };
    const area = {
      id: 'area-1',
      code: 'AREA_PHONGVU_Q1',
      businessCode: 'Q1',
      displayName: 'Quận 1',
      type: 'AREA',
      parentId: region.id,
      isActive: true,
    };
    const { client } = createClient([region]);

    await service.syncLegacyCatalogFromOrganizationNode(client, area);

    expect(client.regionDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ where: { code: 'HCM' } }),
    );
    expect(client.areaDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'Q1' },
        create: expect.objectContaining({ regionCode: 'HCM' }),
        update: expect.objectContaining({ regionCode: 'HCM' }),
      }),
    );
    expect(
      client.regionDefinition.upsert.mock.invocationCallOrder[0],
    ).toBeLessThan(client.areaDefinition.upsert.mock.invocationCallOrder[0]);
  });

  it('rejects an area whose parent is missing or not a region', async () => {
    const service = new UserLegacyCatalogService(runtime);
    const { client } = createClient([
      {
        id: 'department-1',
        code: 'LV2_DEPARTMENT_SALES',
        businessCode: 'SALES',
        type: 'DEPARTMENT',
      },
    ]);

    await expect(
      service.syncLegacyCatalogFromOrganizationNode(client, {
        id: 'area-1',
        code: 'AREA_PHONGVU_Q1',
        businessCode: 'Q1',
        displayName: 'Quận 1',
        type: 'AREA',
        parentId: 'department-1',
      }),
    ).rejects.toThrow('Vùng phải nằm dưới Miền');
  });

  it('syncs a department ancestor before a position and keeps conversion helpers stable', async () => {
    const service = new UserLegacyCatalogService(runtime);
    const department = {
      id: 'department-1',
      code: 'LV2_DEPARTMENT_SALES',
      businessCode: 'SALES',
      displayName: 'Kinh doanh',
      type: 'DEPARTMENT',
    };
    const position = {
      id: 'position-1',
      code: 'STORE_CP01_POS_CASH',
      businessCode: 'CASH',
      displayName: 'Thu ngân',
      type: 'POSITION',
      parentId: department.id,
    };
    const { client } = createClient([department]);

    await service.syncLegacyCatalogFromOrganizationNode(client, position);

    expect(client.departmentDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ where: { code: 'SALES' } }),
    );
    expect(client.jobRoleDefinition.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { code: 'CASH' },
        create: expect.objectContaining({ departmentCode: 'SALES' }),
        update: expect.objectContaining({ departmentCode: 'SALES' }),
      }),
    );
    expect(service.legacyCodeFromOrganizationCode('AREA_PHONGVU_HCM')).toBe(
      'HCM',
    );
    expect(
      service.legacyPersonnelCodeFromOrganizationNode(
        { code: 'REGION_PHONGVU_HCM', businessCode: null },
        'Mã Miền không hợp lệ',
      ),
    ).toBe('HCM');
  });
});
