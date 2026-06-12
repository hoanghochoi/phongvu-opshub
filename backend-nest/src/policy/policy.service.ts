import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { Prisma } from '@prisma/client';
import {
  ADMIN_POLICY_CODES,
  ADMIN_SETTING_KEYS,
  DEFAULT_ADMIN_POLICY_DEFINITIONS,
  DEFAULT_ADMIN_POLICY_RULES,
  DEFAULT_ADMIN_SETTINGS,
} from './policy.constants';
import {
  SYSTEM_ROLE_ADMIN,
  SYSTEM_ROLE_SUPER_ADMIN,
  normalizeSystemRoleCode,
  isSuperAdminRole,
} from '../common/system-role';

const SUPER_ADMIN_ROLE = SYSTEM_ROLE_SUPER_ADMIN;
const ADMIN_ROLE = SYSTEM_ROLE_ADMIN;
const VALID_WORK_SCOPES = new Set(['NATIONAL', 'REGION', 'AREA', 'STORE']);

export type PolicyContext = {
  id?: string | null;
  email?: string | null;
  emailDomain?: string | null;
  role?: string | null;
  departmentCode?: string | null;
  jobRoleCode?: string | null;
  workScopeType?: string | null;
  regionCode?: string | null;
  areaCode?: string | null;
  organizationNodeId?: string | null;
  organizationNodeIds?: string[];
  storeCode?: string | null;
  storeName?: string | null;
  organizationScopeNames?: string[];
};

type NormalizedRuleInput = {
  policyCode: string;
  allowed: boolean;
  emailDomain: string | null;
  systemRole: string | null;
  departmentCode: string | null;
  jobRoleCode: string | null;
  workScopeType: string | null;
  regionCode: string | null;
  areaCode: string | null;
  organizationNodeId: string | null;
  storeCode: string | null;
  userId: string | null;
  scopeContains: string | null;
  note: string | null;
};

@Injectable()
export class PolicyService implements OnModuleInit {
  private readonly logger = new Logger(PolicyService.name);

  constructor(private prisma: PrismaService) {}

  async onModuleInit() {
    await this.seedDefaultPolicies();
  }

  async seedDefaultPolicies() {
    await Promise.all(
      DEFAULT_ADMIN_POLICY_DEFINITIONS.map((policy) =>
        this.prisma.adminPolicyDefinition.upsert({
          where: { code: policy.code },
          update: {
            displayName: policy.displayName,
            description: policy.description ?? null,
            category: policy.category ?? 'GENERAL',
            defaultAllowed: policy.defaultAllowed === true,
            isSystem: true,
            isActive: true,
          },
          create: {
            code: policy.code,
            displayName: policy.displayName,
            description: policy.description ?? null,
            category: policy.category ?? 'GENERAL',
            defaultAllowed: policy.defaultAllowed === true,
            isSystem: true,
            isActive: true,
          },
        }),
      ),
    );

    await Promise.all(
      DEFAULT_ADMIN_SETTINGS.map((setting) =>
        this.prisma.adminSetting.upsert({
          where: { key: setting.key },
          update: {
            displayName: setting.displayName,
            description: setting.description ?? null,
            category: setting.category ?? 'GENERAL',
            isSystem: true,
            isSensitive: false,
          },
          create: {
            key: setting.key,
            displayName: setting.displayName,
            description: setting.description ?? null,
            category: setting.category ?? 'GENERAL',
            value: setting.value,
            isSystem: true,
            isSensitive: false,
          },
        }),
      ),
    );

    for (const rule of DEFAULT_ADMIN_POLICY_RULES as any[]) {
      const existing = await this.prisma.adminPolicyRule.findFirst({
        where: this.defaultRuleWhere(rule),
      });
      if (existing) continue;
      await this.prisma.adminPolicyRule.create({
        data: {
          policyCode: rule.policyCode,
          allowed: rule.allowed === true,
          emailDomain: rule.emailDomain ?? null,
          systemRole: this.normalizeSystemRole(rule.systemRole),
          departmentCode: rule.departmentCode ?? null,
          jobRoleCode: rule.jobRoleCode ?? null,
          workScopeType: rule.workScopeType ?? null,
          regionCode: rule.regionCode ?? null,
          areaCode: rule.areaCode ?? null,
          organizationNodeId: rule.organizationNodeId ?? null,
          storeCode: rule.storeCode ?? null,
          userId: rule.userId ?? null,
          scopeContains: rule.scopeContains ?? null,
          note: rule.note ?? 'Seeded default policy rule',
          isSystem: true,
        },
      });
    }
  }

  async resolvePolicyAccessMap(user: any) {
    await this.seedDefaultPolicies();
    const policies = await this.prisma.adminPolicyDefinition.findMany({
      where: { isActive: true },
      orderBy: { code: 'asc' },
    });
    const context = await this.resolveContext(user);
    const entries = await Promise.all(
      policies.map(async (policy) => [
        policy.code,
        await this.canAccessPolicyWithContext(context, policy.code),
      ]),
    );
    return Object.fromEntries(entries);
  }

  async canAccessPolicy(user: any, policyCode: string) {
    const context = await this.resolveContext(user);
    return this.canAccessPolicyWithContext(context, policyCode);
  }

  async canAccessPolicyWithContext(
    context: PolicyContext,
    policyCodeInput: string,
  ) {
    const policyCode = this.normalizeCode(
      policyCodeInput,
      'Ma policy khong hop le',
    );
    if (this.normalizeSystemRole(context.role) === SUPER_ADMIN_ROLE) return true;

    const policy = await this.prisma.adminPolicyDefinition.findUnique({
      where: { code: policyCode },
      select: { defaultAllowed: true, isActive: true },
    });
    if (!policy || !policy.isActive) return false;

    const rules = await this.prisma.adminPolicyRule.findMany({
      where: { policyCode },
    });
    const matches = rules
      .filter((rule) => this.ruleMatches(rule, context))
      .map((rule) => ({ rule, score: this.ruleScore(rule) }))
      .sort((a, b) => b.score - a.score);

    if (matches.length === 0) return policy.defaultAllowed;

    const topScore = matches[0].score;
    const topRules = matches.filter((match) => match.score === topScore);
    if (topRules.some((match) => !match.rule.allowed)) return false;
    return topRules.some((match) => match.rule.allowed);
  }

  async adminListPolicies(admin: any) {
    await this.assertCanManagePolicies(admin);
    await this.seedDefaultPolicies();
    return this.prisma.adminPolicyDefinition.findMany({
      orderBy: [{ isSystem: 'desc' }, { category: 'asc' }, { code: 'asc' }],
      include: { _count: { select: { rules: true } } },
    });
  }

  async adminCreatePolicy(admin: any, body: any) {
    await this.assertCanManagePolicies(admin);
    const code = this.normalizeCode(body.code, 'Ma policy khong hop le');
    const existing = await this.prisma.adminPolicyDefinition.findUnique({
      where: { code },
    });
    if (existing) throw new BadRequestException('Policy da ton tai');
    return this.prisma.adminPolicyDefinition.create({
      data: {
        code,
        displayName: this.requiredText(
          body.displayName,
          'Ten policy khong duoc de trong',
          120,
        ),
        description: this.optionalText(body.description, 240),
        category: this.normalizeOptionalCode(body.category) ?? 'GENERAL',
        defaultAllowed: body.defaultAllowed === true,
        isSystem: false,
        isActive: body.isActive !== false,
      },
    });
  }

  async adminUpdatePolicy(admin: any, codeInput: string, body: any) {
    await this.assertCanManagePolicies(admin);
    const code = this.normalizeCode(codeInput, 'Ma policy khong hop le');
    const current = await this.prisma.adminPolicyDefinition.findUnique({
      where: { code },
    });
    if (!current) throw new NotFoundException('Khong tim thay policy');
    const nextCode = body.code
      ? this.normalizeCode(body.code, 'Ma policy khong hop le')
      : current.code;
    if (current.isSystem && nextCode !== current.code) {
      throw new BadRequestException('Khong duoc doi ma policy he thong');
    }
    return this.prisma.adminPolicyDefinition.update({
      where: { code: current.code },
      data: {
        code: nextCode,
        displayName:
          body.displayName === undefined
            ? current.displayName
            : this.requiredText(
                body.displayName,
                'Ten policy khong duoc de trong',
                120,
              ),
        description:
          body.description === undefined
            ? current.description
            : this.optionalText(body.description, 240),
        category:
          body.category === undefined
            ? current.category
            : (this.normalizeOptionalCode(body.category) ?? 'GENERAL'),
        defaultAllowed:
          body.defaultAllowed === undefined
            ? current.defaultAllowed
            : body.defaultAllowed === true,
        isActive:
          body.isActive === undefined
            ? current.isActive
            : body.isActive === true,
      },
    });
  }

  async adminDeletePolicy(admin: any, codeInput: string) {
    await this.assertCanManagePolicies(admin);
    const code = this.normalizeCode(codeInput, 'Ma policy khong hop le');
    const policy = await this.prisma.adminPolicyDefinition.findUnique({
      where: { code },
      include: { _count: { select: { rules: true } } },
    });
    if (!policy) throw new NotFoundException('Khong tim thay policy');
    if (policy.isSystem) {
      throw new BadRequestException('Khong duoc xoa policy he thong');
    }
    if (policy._count.rules > 0) {
      throw new BadRequestException('Policy dang co rule, khong the xoa');
    }
    await this.prisma.adminPolicyDefinition.delete({ where: { code } });
    return { deleted: true, code };
  }

  async adminListRules(admin: any, policyCodeInput?: string) {
    await this.assertCanManagePolicies(admin);
    const policyCode = policyCodeInput
      ? this.normalizeCode(policyCodeInput, 'Ma policy khong hop le')
      : undefined;
    return this.prisma.adminPolicyRule.findMany({
      where: policyCode ? { policyCode } : undefined,
      orderBy: { updatedAt: 'desc' },
      include: { policy: true, organizationNode: true },
    });
  }

  async adminCreateRule(admin: any, body: any) {
    await this.assertCanManagePolicies(admin);
    const data = await this.normalizeRuleInput(body);
    return this.prisma.adminPolicyRule.create({ data });
  }

  async adminCreateRules(admin: any, body: any) {
    await this.assertCanManagePolicies(admin);
    const dataList = await this.normalizeRuleBatchInput(body);
    return this.prisma.$transaction(
      dataList.map((data) => this.prisma.adminPolicyRule.create({ data })),
    );
  }

  async adminUpdateRule(admin: any, id: string, body: any) {
    await this.assertCanManagePolicies(admin);
    const current = await this.prisma.adminPolicyRule.findUnique({
      where: { id },
    });
    if (!current) throw new NotFoundException('Khong tim thay policy rule');
    const data = await this.normalizeRuleInput(
      { ...current, ...body },
      current,
    );
    return this.prisma.adminPolicyRule.update({ where: { id }, data });
  }

  async adminDeleteRule(admin: any, id: string) {
    await this.assertCanManagePolicies(admin);
    await this.prisma.adminPolicyRule.delete({ where: { id } });
    return { deleted: true, id };
  }

  async adminListSettings(admin: any) {
    await this.assertCanManagePolicies(admin);
    await this.seedDefaultPolicies();
    return this.prisma.adminSetting.findMany({
      orderBy: [{ isSystem: 'desc' }, { category: 'asc' }, { key: 'asc' }],
    });
  }

  async adminCreateSetting(admin: any, body: any) {
    await this.assertCanManagePolicies(admin);
    const key = this.normalizeCode(body.key, 'Ma cau hinh khong hop le');
    const existing = await this.prisma.adminSetting.findUnique({
      where: { key },
    });
    if (existing) throw new BadRequestException('Cau hinh da ton tai');
    return this.prisma.adminSetting.create({
      data: {
        key,
        displayName: this.requiredText(
          body.displayName,
          'Ten cau hinh khong duoc de trong',
          120,
        ),
        description: this.optionalText(body.description, 240),
        category: this.normalizeOptionalCode(body.category) ?? 'GENERAL',
        value: this.normalizeSettingValue(key, body.value),
        isSystem: false,
        isSensitive: false,
      },
    });
  }

  async adminUpdateSetting(admin: any, keyInput: string, body: any) {
    await this.assertCanManagePolicies(admin);
    const key = this.normalizeCode(keyInput, 'Ma cau hinh khong hop le');
    const current = await this.prisma.adminSetting.findUnique({
      where: { key },
    });
    if (!current) throw new NotFoundException('Khong tim thay cau hinh');
    return this.prisma.adminSetting.update({
      where: { key },
      data: {
        displayName:
          body.displayName === undefined
            ? current.displayName
            : this.requiredText(
                body.displayName,
                'Ten cau hinh khong duoc de trong',
                120,
              ),
        description:
          body.description === undefined
            ? current.description
            : this.optionalText(body.description, 240),
        category:
          body.category === undefined
            ? current.category
            : (this.normalizeOptionalCode(body.category) ?? 'GENERAL'),
        ...(body.value === undefined
          ? {}
          : { value: this.normalizeSettingValue(key, body.value) }),
      },
    });
  }

  async getSettingValue<T>(key: string, fallback: T): Promise<T> {
    try {
      const setting = await this.prisma.adminSetting.findUnique({
        where: { key },
      });
      if (!setting) return fallback;
      return setting.value as T;
    } catch (error) {
      this.logger.warn(`Policy setting lookup failed: key=${key}`);
      return fallback;
    }
  }

  async getAllowedEmailDomains(fallback: string[]) {
    const organizationDomains = await this.getOrganizationAllowedEmailDomains();
    if (organizationDomains.length > 0) return organizationDomains;

    const value = await this.getSettingValue<unknown>(
      ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS,
      fallback,
    );
    if (!Array.isArray(value)) return fallback;
    const domains = value
      .map((item) => this.normalizeOptionalDomain(item))
      .filter((domain): domain is string => Boolean(domain));
    return domains.length > 0 ? Array.from(new Set(domains)) : fallback;
  }

  private async getOrganizationAllowedEmailDomains() {
    try {
      const organizationNode = (this.prisma as any).organizationNode;
      if (!organizationNode?.findMany) return [];
      const nodes = await organizationNode.findMany({
        where: {
          type: { in: ['LV0_DOMAIN', 'ROOT_DOMAIN'] },
          isActive: true,
          loginAllowed: true,
          emailDomain: { not: null },
        },
        select: { emailDomain: true },
        orderBy: [{ sortOrder: 'asc' }, { displayName: 'asc' }],
      });
      return Array.from(
        new Set(
          nodes
            .map((node: { emailDomain?: string | null }) =>
              this.normalizeOptionalDomain(node.emailDomain),
            )
            .filter((domain: string | null): domain is string =>
              Boolean(domain),
            ),
        ),
      );
    } catch (error) {
      this.logger.warn(
        'Organization email-domain lookup failed; using policy setting fallback',
      );
      return [];
    }
  }

  private defaultRuleWhere(rule: any) {
    return {
      policyCode: rule.policyCode,
      allowed: rule.allowed === true,
      emailDomain: rule.emailDomain ?? null,
      systemRole: this.normalizeSystemRole(rule.systemRole),
      departmentCode: rule.departmentCode ?? null,
      jobRoleCode: rule.jobRoleCode ?? null,
      workScopeType: rule.workScopeType ?? null,
      regionCode: rule.regionCode ?? null,
      areaCode: rule.areaCode ?? null,
      organizationNodeId: rule.organizationNodeId ?? null,
      storeCode: rule.storeCode ?? null,
      userId: rule.userId ?? null,
      scopeContains: rule.scopeContains ?? null,
      isSystem: true,
    };
  }

  private async assertCanManagePolicies(admin: any) {
    if (isSuperAdminRole(admin?.role)) return;
    if (await this.canAccessPolicy(admin, ADMIN_POLICY_CODES.ADMIN_POLICIES))
      return;
    throw new ForbiddenException('Khong co quyen quan ly policy');
  }

  private async normalizeRuleInput(
    input: any,
    current?: any,
  ): Promise<NormalizedRuleInput> {
    const policyCode = this.normalizeCode(
      input.policyCode ?? current?.policyCode,
      'Ma policy khong hop le',
    );
    await this.ensurePolicy(policyCode);
    const allowed =
      input.allowed === undefined
        ? current?.allowed === true
        : input.allowed === true;
    const workScopeType = this.normalizeOptionalCode(input.workScopeType);
    if (workScopeType && !VALID_WORK_SCOPES.has(workScopeType)) {
      throw new BadRequestException('Pham vi policy khong hop le');
    }

    const data: NormalizedRuleInput = {
      policyCode,
      allowed,
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
      scopeContains: this.optionalText(input.scopeContains, 120),
      note: this.optionalText(input.note, 240),
    };
    await this.validateRuleReferences(data);
    return data;
  }

  private async normalizeRuleBatchInput(input: any) {
    const policyCode = this.normalizeCode(
      input.policyCode,
      'Ma policy khong hop le',
    );
    await this.ensurePolicy(policyCode);
    const allowed = input.allowed === true;
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
        throw new BadRequestException('Pham vi policy khong hop le');
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
    const scopeContainsValues = this.normalizeTextOptions(
      input.scopeContainsValues,
      input.scopeContains,
      120,
    );

    const dataList = this.expandRuleBatch({
      policyCode,
      allowed,
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
      scopeContainsValues,
    });
    if (dataList.length > 500) {
      throw new BadRequestException('Toi da 500 rules moi lan tao');
    }
    for (const data of dataList) await this.validateRuleReferences(data);
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
      if (!area) throw new BadRequestException('Vung khong ton tai');
      if (selectedRegions.includes(area.regionCode)) {
        locations.push({ regionCode: area.regionCode, areaCode });
      }
    }
    if (locations.length === 0) {
      throw new BadRequestException('Vung khong thuoc Mien da chon');
    }
    return locations;
  }

  private expandRuleBatch(input: {
    policyCode: string;
    allowed: boolean;
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
    scopeContainsValues: Array<string | null>;
  }) {
    const dataList: NormalizedRuleInput[] = [];
    for (const emailDomain of input.emailDomains) {
      for (const systemRole of input.systemRoles) {
        for (const departmentCode of input.departmentCodes) {
          for (const jobRoleCode of input.jobRoleCodes) {
            for (const workScopeType of input.workScopeTypes) {
              for (const location of input.locations) {
                for (const organizationNodeId of input.organizationNodeIds) {
                  for (const storeCode of input.storeCodes) {
                    for (const userId of input.userIds) {
                      for (const scopeContains of input.scopeContainsValues) {
                        dataList.push({
                          policyCode: input.policyCode,
                          allowed: input.allowed,
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
                          scopeContains,
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
      if (!role) throw new BadRequestException('Role khong ton tai');
    }
    if (data.departmentCode) {
      const department = await this.prisma.departmentDefinition.findUnique({
        where: { code: data.departmentCode },
      });
      if (!department) throw new BadRequestException('Phong ban khong ton tai');
    }
    if (data.jobRoleCode) {
      const jobRole = await this.prisma.jobRoleDefinition.findUnique({
        where: { code: data.jobRoleCode },
      });
      if (!jobRole) throw new BadRequestException('Chuc danh khong ton tai');
    }
    if (data.regionCode) {
      const region = await this.prisma.regionDefinition.findUnique({
        where: { code: data.regionCode },
      });
      if (!region) throw new BadRequestException('Mien khong ton tai');
    }
    if (data.areaCode) {
      const area = await this.prisma.areaDefinition.findUnique({
        where: { code: data.areaCode },
      });
      if (!area) throw new BadRequestException('Vung khong ton tai');
      if (data.regionCode && area.regionCode !== data.regionCode) {
        throw new BadRequestException('Vung khong thuoc Mien da chon');
      }
    }
    if (data.organizationNodeId) {
      const organizationNode = await this.prisma.organizationNode.findUnique({
        where: { id: data.organizationNodeId },
        select: { id: true, isActive: true },
      });
      if (!organizationNode || !organizationNode.isActive) {
        throw new BadRequestException('Node to chuc khong ton tai hoac da tat');
      }
    }
    if (data.storeCode) {
      const store = await this.prisma.store.findUnique({
        where: { storeId: data.storeCode },
      });
      if (!store) throw new BadRequestException('SR khong ton tai');
    }
    if (data.userId) {
      const user = await this.prisma.user.findUnique({
        where: { id: data.userId },
      });
      if (!user) throw new BadRequestException('User khong ton tai');
    }
  }

  private async ensurePolicy(code: string) {
    const policy = await this.prisma.adminPolicyDefinition.findUnique({
      where: { code },
    });
    if (!policy) throw new BadRequestException('Policy khong ton tai');
  }

  private async resolveContext(user: any): Promise<PolicyContext> {
    if (!user?.id) {
      return {
        id: user?.id ?? null,
        email: user?.email ?? null,
        emailDomain: this.emailDomainFromEmail(user?.email),
        role: this.normalizeSystemRole(user?.role),
        departmentCode: user?.departmentCode ?? null,
        jobRoleCode: user?.jobRoleCode ?? null,
        workScopeType: this.effectiveScope(user),
        regionCode: user?.regionCode ?? null,
        areaCode: user?.areaCode ?? null,
        storeCode: user?.storeCode ?? null,
        storeName: user?.storeName ?? null,
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
      storeCode:
        organizationContext.storeCode ?? source.store?.storeId ?? source.storeCode ?? null,
      storeName: source.store?.storeName ?? source.storeName ?? null,
      organizationScopeNames: organizationContext.scopeNames,
    };
  }

  private async resolveOrganizationRuleContext(nodeId?: string | null) {
    const empty = {
      organizationNodeId: nodeId ?? null,
      organizationNodeIds: [] as string[],
      regionCode: null as string | null,
      areaCode: null as string | null,
      storeCode: null as string | null,
      scopeNames: [] as string[],
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
      displayName: string;
      abbreviation: string | null;
    }> = await organizationNode.findMany({
      select: {
        id: true,
        parentId: true,
        type: true,
        code: true,
        businessCode: true,
        displayName: true,
        abbreviation: true,
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
      scopeNames: ancestors.flatMap((node) =>
        [node.businessCode, node.displayName, node.abbreviation].filter(
          (value): value is string => Boolean(value),
        ),
      ),
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
      [SUPER_ADMIN_ROLE, ADMIN_ROLE].includes(role || '')
    ) {
      return 'NATIONAL';
    }
    return 'STORE';
  }

  private normalizeSystemRole(role: unknown) {
    return normalizeSystemRoleCode(role);
  }

  private ruleMatches(rule: any, context: PolicyContext) {
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
      ) &&
      this.scopeContainsMatches(rule.scopeContains, context)
    );
  }

  private organizationNodeMatches(
    ruleValue?: string | null,
    context?: PolicyContext,
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

  private scopeContainsMatches(
    ruleValue: string | null | undefined,
    context: PolicyContext,
  ) {
    if (!ruleValue) return true;
    const needle = String(ruleValue).trim().toUpperCase();
    return [
      context.storeCode,
      context.storeName,
      context.regionCode,
      context.areaCode,
      ...(context.organizationScopeNames ?? []),
    ]
      .filter(Boolean)
      .some((value) => String(value).toUpperCase().includes(needle));
  }

  private ruleScore(rule: any) {
    return (
      (rule.emailDomain ? 512 : 0) +
      (rule.userId ? 256 : 0) +
      (rule.organizationNodeId ? 192 : 0) +
      (rule.storeCode ? 128 : 0) +
      (rule.areaCode ? 64 : 0) +
      (rule.regionCode ? 32 : 0) +
      (rule.workScopeType ? 16 : 0) +
      (rule.jobRoleCode ? 8 : 0) +
      (rule.departmentCode ? 4 : 0) +
      (rule.systemRole ? 2 : 0) +
      (rule.scopeContains ? 1 : 0)
    );
  }

  private normalizeSettingValue(
    key: string,
    value: unknown,
  ): Prisma.InputJsonValue {
    if (key === ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS) {
      const values = Array.isArray(value) ? value : [];
      const domains = values
        .map((item) => this.normalizeOptionalDomain(item))
        .filter((domain): domain is string => Boolean(domain));
      if (domains.length === 0) {
        throw new BadRequestException('Danh sach domain khong duoc de trong');
      }
      return Array.from(new Set(domains));
    }
    if (value === null || value === undefined || typeof value !== 'object') {
      throw new BadRequestException(
        'Gia tri cau hinh phai la object hoac array',
      );
    }
    return value as Prisma.InputJsonValue;
  }

  private normalizeCode(value: unknown, message: string) {
    const code = String(value || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    if (!/^[A-Z][A-Z0-9_]{1,79}$/.test(code)) {
      throw new BadRequestException(message);
    }
    return code;
  }

  private normalizeOptionalCode(value: unknown) {
    if (value === undefined || value === null || String(value).trim() === '')
      return null;
    return this.normalizeCode(value, 'Ma loc rule khong hop le');
  }

  private normalizeOptionalDomain(value: unknown) {
    if (value === undefined || value === null || String(value).trim() === '')
      return null;
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
}
