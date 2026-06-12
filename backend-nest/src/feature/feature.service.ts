import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { PolicyService } from '../policy/policy.service';
import { DEFAULT_FEATURE_DEFINITIONS } from './feature.constants';
import {
  SYSTEM_ROLE_ADMIN,
  SYSTEM_ROLE_SUPER_ADMIN,
  normalizeSystemRoleCode,
  isSuperAdminRole,
} from '../common/system-role';

const SUPER_ADMIN_ROLE = SYSTEM_ROLE_SUPER_ADMIN;
const ADMIN_ROLE = SYSTEM_ROLE_ADMIN;
const VALID_WORK_SCOPES = new Set(['NATIONAL', 'REGION', 'AREA', 'STORE']);
const USER_FEATURE_BACKFILL_SETTING_KEY =
  'USER_FEATURE_ALLOWLIST_BACKFILLED_AT';

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
  storeName?: string | null;
};

@Injectable()
export class FeatureService implements OnModuleInit {
  private readonly logger = new Logger(FeatureService.name);

  constructor(
    private prisma: PrismaService,
    private policyService: PolicyService,
  ) {}

  async onModuleInit() {
    await this.seedDefaultFeatures();
    await this.backfillUserFeatureAssignmentsOnce();
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
    await this.seedDefaultFeatures();
    const features = await this.prisma.featureDefinition.findMany({
      where: { isActive: true },
      orderBy: { code: 'asc' },
    });
    const context = await this.resolveContext(user);
    const entries = await Promise.all(
      features.map(async (feature) => [
        feature.code,
        await this.canAccessFeatureWithContext(context, feature.code),
      ]),
    );
    return Object.fromEntries(entries);
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
      include: { _count: { select: { rules: true } } },
    });
  }

  async adminListFeatureTree(admin: any) {
    this.assertSuperAdmin(admin);
    await this.seedDefaultFeatures();
    return this.prisma.featureDefinition.findMany({
      where: { visibleInUserPicker: true },
      orderBy: [{ sortOrder: 'asc' }, { code: 'asc' }],
      include: { _count: { select: { rules: true, userAssignments: true } } },
    });
  }

  async adminCreateFeature(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeCode(body.code, 'Mã tính năng không hợp lệ');
    const existing = await this.prisma.featureDefinition.findUnique({
      where: { code },
    });
    if (existing) throw new BadRequestException('Tính năng đã tồn tại');
    return this.prisma.featureDefinition.create({
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

    return this.prisma.featureDefinition.update({
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
  }

  async adminDeleteFeature(admin: any, codeInput: string) {
    this.assertSuperAdmin(admin);
    const code = this.normalizeCode(codeInput, 'Mã tính năng không hợp lệ');
    const feature = await this.prisma.featureDefinition.findUnique({
      where: { code },
      include: { _count: { select: { rules: true, userAssignments: true } } },
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
    await this.prisma.featureDefinition.delete({ where: { code } });
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
    return this.prisma.featureAccessRule.create({ data });
  }

  async adminCreateRules(admin: any, body: any) {
    this.assertSuperAdmin(admin);
    const dataList = await this.normalizeRuleBatchInput(body);
    return this.prisma.$transaction(
      dataList.map((data) => this.prisma.featureAccessRule.create({ data })),
    );
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
    return this.prisma.featureAccessRule.update({ where: { id }, data });
  }

  async adminDeleteRule(admin: any, id: string) {
    this.assertSuperAdmin(admin);
    await this.prisma.featureAccessRule.delete({ where: { id } });
    return { deleted: true, id };
  }

  private async canAccessFeatureWithContext(
    context: FeatureContext,
    featureCodeInput: string,
  ) {
    const featureCode = this.normalizeCode(
      featureCodeInput,
      'Mã tính năng không hợp lệ',
    );
    if (this.normalizeSystemRole(context.role) === SUPER_ADMIN_ROLE) return true;

    const feature = await this.prisma.featureDefinition.findUnique({
      where: { code: featureCode },
      select: { isActive: true },
    });
    if (!feature || !feature.isActive) return false;
    if (!context.id) return false;

    const assignment = await this.prisma.userFeatureAssignment.findUnique({
      where: {
        userId_featureCode: {
          userId: context.id,
          featureCode,
        },
      },
      select: { enabled: true },
    });
    return assignment?.enabled === true;
  }

  private async legacyCanAccessFeatureWithContext(
    context: FeatureContext,
    featureCodeInput: string,
  ) {
    const featureCode = this.normalizeCode(
      featureCodeInput,
      'Mã tính năng không hợp lệ',
    );
    if (this.normalizeSystemRole(context.role) === SUPER_ADMIN_ROLE) return true;

    const feature = await this.prisma.featureDefinition.findUnique({
      where: { code: featureCode },
      select: { isActive: true },
    });
    if (feature && !feature.isActive) return false;

    const rules = await this.prisma.featureAccessRule.findMany({
      where: { featureCode },
    });
    const matches = rules
      .filter((rule) => this.ruleMatches(rule, context))
      .map((rule) => ({ rule, score: this.ruleScore(rule) }))
      .sort((a, b) => b.score - a.score);

    const policyAllowed = await this.policyService.canAccessPolicyWithContext(
      context,
      featureCode,
    );
    if (matches.length === 0) return policyAllowed;

    const topScore = matches[0].score;
    const topRules = matches.filter((match) => match.score === topScore);
    if (topRules.some((match) => !match.rule.enabled)) return false;
    return policyAllowed && topRules.some((match) => match.rule.enabled);
  }

  private async backfillUserFeatureAssignmentsOnce() {
    try {
      const marker = await this.prisma.adminSetting.findUnique({
        where: { key: USER_FEATURE_BACKFILL_SETTING_KEY },
      });
      if (marker) return;

      await this.policyService.seedDefaultPolicies();
      const features = await this.prisma.featureDefinition.findMany({
        where: { isActive: true, visibleInUserPicker: true },
        orderBy: [{ sortOrder: 'asc' }, { code: 'asc' }],
      });
      const users = await this.prisma.user.findMany({
        where: { role: { not: SUPER_ADMIN_ROLE } },
        select: { id: true },
      });

      const rows: Array<{
        userId: string;
        featureCode: string;
        enabled: boolean;
        note: string;
      }> = [];
      for (const user of users) {
        const context = await this.resolveContext(user);
        for (const feature of features) {
          if (
            await this.legacyCanAccessFeatureWithContext(context, feature.code)
          ) {
            rows.push({
              userId: user.id,
              featureCode: feature.code,
              enabled: true,
              note: 'Backfilled from legacy feature and policy rules',
            });
          }
        }
      }

      if (rows.length > 0) {
        await this.prisma.userFeatureAssignment.createMany({
          data: rows,
          skipDuplicates: true,
        });
      }

      await this.prisma.adminSetting.create({
        data: {
          key: USER_FEATURE_BACKFILL_SETTING_KEY,
          displayName: 'User feature allowlist backfill',
          description:
            'Marker that legacy feature access was copied to user allowlists',
          category: 'MIGRATION',
          value: { completedAt: new Date().toISOString(), rows: rows.length },
          isSystem: true,
          isSensitive: false,
        },
      });
      this.logger.log(
        `User feature allowlist backfill completed: users=${users.length} rows=${rows.length}`,
      );
    } catch (error) {
      this.logger.error('User feature allowlist backfill failed', error as any);
      throw error;
    }
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
      'MÃ£ tÃ­nh nÄƒng khÃ´ng há»£p lá»‡',
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
        throw new BadRequestException(
          'Pháº¡m vi tÃ­nh nÄƒng khÃ´ng há»£p lá»‡',
        );
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
      throw new BadRequestException('Tá»‘i Ä‘a 500 rules má»—i láº§n táº¡o');
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
      if (!area) throw new BadRequestException('VÃ¹ng khÃ´ng tá»“n táº¡i');
      if (selectedRegions.includes(area.regionCode)) {
        locations.push({ regionCode: area.regionCode, areaCode });
      }
    }
    if (locations.length === 0) {
      throw new BadRequestException('VÃ¹ng khÃ´ng thuá»™c Miá»n Ä‘Ã£ chá»n');
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
      },
    });
    const source = full ?? user;
    const scopeNodeId =
      this.effectiveScope(source) === 'STORE'
        ? (source.store?.organizationNodeId ?? source.organizationNodeId)
        : (source.organizationNodeId ?? source.store?.organizationNodeId);
    const organizationContext = await this.resolveOrganizationRuleContext(
      scopeNodeId,
    );
    const area = this.areaForContextSource(source);
    const region = this.regionForContextSource(source);
    return {
      id: source.id ?? null,
      email: source.email ?? null,
      emailDomain: this.emailDomainFromEmail(source.email),
      role: this.normalizeSystemRole(source.role),
      departmentCode: source.departmentCode ?? null,
      jobRoleCode: source.jobRoleCode ?? null,
      workScopeType: this.effectiveScope(source),
      regionCode:
        organizationContext.regionCode ?? region?.code ?? source.regionCode ?? null,
      areaCode:
        organizationContext.areaCode ?? area?.code ?? source.areaCode ?? null,
      organizationNodeId: organizationContext.organizationNodeId,
      organizationNodeIds: organizationContext.organizationNodeIds,
      storeCode: organizationContext.storeCode ?? source.store?.storeId ?? null,
      storeName: source.store?.storeName ?? null,
    };
  }

  private async resolveOrganizationRuleContext(nodeId?: string | null) {
    const empty = {
      organizationNodeId: nodeId ?? null,
      organizationNodeIds: [] as string[],
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
    }> = await organizationNode.findMany({
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
      },
    });
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const ancestors: typeof nodes = [];
    let cursor = byId.get(nodeId) ?? null;
    for (let guard = 0; cursor && guard < 50; guard += 1) {
      ancestors.push(cursor);
      cursor = cursor.parentId ? (byId.get(cursor.parentId) ?? null) : null;
    }
    const businessCodeFor = (...types: string[]) => {
      const node = ancestors.find((item) => types.includes(item.type));
      if (!node) return null;
      return node.businessCode || this.legacyCodeFromOrganizationCode(node.code);
    };
    return {
      organizationNodeId: nodeId,
      organizationNodeIds: ancestors.map((node) => node.id),
      regionCode: businessCodeFor('LV2_REGION', 'REGION'),
      areaCode: businessCodeFor('LV3_AREA', 'AREA'),
      storeCode: businessCodeFor('LV4_STORE', 'SHOWROOM'),
    };
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
    if (
      role === SUPER_ADMIN_ROLE ||
      role === ADMIN_ROLE
    ) {
      return 'NATIONAL';
    }
    return 'STORE';
  }

  private normalizeSystemRole(role: unknown) {
    return normalizeSystemRoleCode(role);
  }

  private ruleMatches(rule: any, context: FeatureContext) {
    return (
      this.matches(rule.emailDomain, context.emailDomain) &&
      this.matches(rule.userId, context.id) &&
      this.matches(rule.storeCode, context.storeCode) &&
      this.organizationNodeMatches(rule.organizationNodeId, context) &&
      this.matches(rule.areaCode, context.areaCode) &&
      this.matches(rule.regionCode, context.regionCode) &&
      this.matches(rule.workScopeType, context.workScopeType) &&
      this.matches(rule.jobRoleCode, context.jobRoleCode) &&
      this.matches(rule.departmentCode, context.departmentCode) &&
      this.matches(
        this.normalizeSystemRole(rule.systemRole),
        this.normalizeSystemRole(context.role),
      )
    );
  }

  private organizationNodeMatches(
    ruleValue?: string | null,
    context?: FeatureContext,
  ) {
    if (!ruleValue) return true;
    const ids = context?.organizationNodeIds ?? [];
    return ids.includes(ruleValue);
  }

  private matches(ruleValue?: string | null, contextValue?: string | null) {
    if (!ruleValue) return true;
    return (
      String(ruleValue).toUpperCase() ===
      String(contextValue || '').toUpperCase()
    );
  }

  private ruleScore(rule: any) {
    return (
      (rule.emailDomain ? 256 : 0) +
      (rule.userId ? 128 : 0) +
      (rule.organizationNodeId ? 96 : 0) +
      (rule.storeCode ? 64 : 0) +
      (rule.areaCode ? 32 : 0) +
      (rule.regionCode ? 16 : 0) +
      (rule.workScopeType ? 8 : 0) +
      (rule.jobRoleCode ? 4 : 0) +
      (rule.departmentCode ? 2 : 0) +
      (rule.systemRole ? 1 : 0)
    );
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

  private assertSuperAdmin(user: any) {
    if (!isSuperAdminRole(user?.role)) {
      throw new ForbiddenException('Chỉ SUPER_ADMIN được quản lý tính năng');
    }
  }
}
