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
import { AccessChangeService } from '../auth/access-change.service';
import { getOrganizationTree } from '../common/organization-tree-cache';
import {
  SYSTEM_ROLE_ADMIN,
  SYSTEM_ROLE_SUPER_ADMIN,
  normalizeSystemRoleCode,
  isSuperAdminRole,
} from '../common/system-role';

const SUPER_ADMIN_ROLE = SYSTEM_ROLE_SUPER_ADMIN;
const ADMIN_ROLE = SYSTEM_ROLE_ADMIN;
const VALID_WORK_SCOPES = new Set(['NATIONAL', 'REGION', 'AREA', 'STORE']);
const LEGACY_POLICY_RULE_SELECTOR_FIELDS = [
  'departmentCode',
  'departmentCodes',
  'jobRoleCode',
  'jobRoleCodes',
  'workScopeType',
  'workScopeTypes',
  'regionCode',
  'regionCodes',
  'areaCode',
  'areaCodes',
  'storeCode',
  'storeCodes',
  'userId',
  'userIds',
  'scopeContains',
  'scopeContainsValues',
] as const;

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
  alternateContexts?: PolicyContext[];
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

  constructor(
    private prisma: PrismaService,
    private readonly accessChangeService: AccessChangeService,
  ) {}

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
            isActive: (policy as any).isActive !== false,
          },
          create: {
            code: policy.code,
            displayName: policy.displayName,
            description: policy.description ?? null,
            category: policy.category ?? 'GENERAL',
            defaultAllowed: policy.defaultAllowed === true,
            isSystem: true,
            isActive: (policy as any).isActive !== false,
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
    const startedAt = Date.now();
    const policies = await this.prisma.adminPolicyDefinition.findMany({
      where: { isActive: true },
      orderBy: { code: 'asc' },
    });
    const context = await this.resolveContext(user);
    const policyCodes = policies.map((policy) => policy.code);
    const rules = policyCodes.length
      ? await this.prisma.adminPolicyRule.findMany({
          where: { policyCode: { in: policyCodes } },
        })
      : [];
    const rulesByPolicy = new Map<string, any[]>();
    for (const rule of rules) {
      const list = rulesByPolicy.get(rule.policyCode) ?? [];
      list.push(rule);
      rulesByPolicy.set(rule.policyCode, list);
    }
    const evaluationStartedAt = Date.now();
    const entries = policies.map((policy) => [
      policy.code,
      this.evaluatePolicy(
        context,
        policy,
        rulesByPolicy.get(policy.code) ?? [],
      ),
    ]);
    this.logger.log(
      `Policy access batch resolved: userId=${String(user?.id || 'unknown')} policies=${policies.length} rules=${rules.length} policyQueries=${1 + (policyCodes.length > 0 ? 1 : 0)} evaluationMs=${Date.now() - evaluationStartedAt} durationMs=${Date.now() - startedAt}`,
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
    if (this.normalizeSystemRole(context.role) === SUPER_ADMIN_ROLE)
      return true;

    const policy = await this.prisma.adminPolicyDefinition.findUnique({
      where: { code: policyCode },
      select: { defaultAllowed: true, isActive: true },
    });
    if (!policy || !policy.isActive) return false;

    const rules = await this.prisma.adminPolicyRule.findMany({
      where: { policyCode },
    });
    return this.evaluatePolicy(context, policy, rules);
  }

  private evaluatePolicy(
    context: PolicyContext,
    policy: { defaultAllowed: boolean; isActive: boolean },
    rules: any[],
  ) {
    if (!policy.isActive) return false;
    const contexts = [context, ...(context.alternateContexts ?? [])];
    const matches = rules
      .filter((rule) =>
        contexts.some((candidate) => this.ruleMatches(rule, candidate)),
      )
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
    const created = await this.prisma.adminPolicyDefinition.create({
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
    await this.accessChangeService.publishForAllUsers(
      'policy-definition-created',
    );
    return created;
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
    const updated = await this.prisma.adminPolicyDefinition.update({
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
    const accessContractChanged =
      updated.code !== current.code ||
      updated.defaultAllowed !== current.defaultAllowed ||
      updated.isActive !== current.isActive;
    if (accessContractChanged) {
      await this.accessChangeService.publishForAllUsers(
        'policy-definition-updated',
      );
    }
    return updated;
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
    await this.accessChangeService.publishForAllUsers(
      'policy-definition-deleted',
    );
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
    this.assertNoLegacyRuleSelectors(body);
    const data = await this.normalizeRuleInput(body);
    const created = await this.prisma.adminPolicyRule.create({ data });
    await this.accessChangeService.publishForOrganizationNodeIds(
      [data.organizationNodeId],
      'policy-rule-created',
    );
    return created;
  }

  async adminCreateRules(admin: any, body: any) {
    await this.assertCanManagePolicies(admin);
    this.assertNoLegacyRuleSelectors(body);
    const dataList = await this.normalizeRuleBatchInput(body);
    const created = await this.prisma.$transaction(
      dataList.map((data) => this.prisma.adminPolicyRule.create({ data })),
    );
    await this.accessChangeService.publishForOrganizationNodeIds(
      dataList.map((data) => data.organizationNodeId),
      'policy-rule-created',
    );
    return created;
  }

  async adminUpdateRule(admin: any, id: string, body: any) {
    await this.assertCanManagePolicies(admin);
    const current = await this.prisma.adminPolicyRule.findUnique({
      where: { id },
    });
    if (!current) throw new NotFoundException('Khong tim thay policy rule');
    this.assertNoLegacyRuleSelectors(body);
    const data = await this.normalizeRuleInput(
      { ...current, ...body },
      current,
    );
    const updated = await this.prisma.adminPolicyRule.update({
      where: { id },
      data,
    });
    await this.accessChangeService.publishForOrganizationNodeIds(
      [current.organizationNodeId, data.organizationNodeId],
      'policy-rule-updated',
    );
    return updated;
  }

  async adminDeleteRule(admin: any, id: string) {
    await this.assertCanManagePolicies(admin);
    const current = await this.prisma.adminPolicyRule.findUnique({
      where: { id },
    });
    if (!current) throw new NotFoundException('Khong tim thay policy rule');
    await this.prisma.adminPolicyRule.delete({ where: { id } });
    await this.accessChangeService.publishForOrganizationNodeIds(
      [current.organizationNodeId],
      'policy-rule-deleted',
    );
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

  private assertNoLegacyRuleSelectors(input: any) {
    for (const field of LEGACY_POLICY_RULE_SELECTOR_FIELDS) {
      if (this.hasMeaningfulValue(input?.[field])) {
        throw new BadRequestException(
          'Policy rule chi ho tro OrganizationNode; khong dung selector legacy',
        );
      }
    }
  }

  private hasMeaningfulValue(value: unknown): boolean {
    if (Array.isArray(value)) {
      return value.some((item) => this.hasMeaningfulValue(item));
    }
    return value !== undefined && value !== null && String(value).trim() !== '';
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
    const organizationNodeId = this.optionalText(
      input.organizationNodeId ?? current?.organizationNodeId,
      80,
    );
    if (!organizationNodeId) {
      throw new BadRequestException('Policy rule phai chon node to chuc');
    }

    const data: NormalizedRuleInput = {
      policyCode,
      allowed,
      emailDomain: this.normalizeOptionalDomain(input.emailDomain),
      systemRole: this.normalizeSystemRole(input.systemRole),
      departmentCode: null,
      jobRoleCode: null,
      workScopeType: null,
      regionCode: null,
      areaCode: null,
      organizationNodeId,
      storeCode: null,
      userId: null,
      scopeContains: null,
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
    const organizationNodeIds = this.normalizeTextOptions(
      input.organizationNodeIds,
      input.organizationNodeId,
      80,
    ).filter((id): id is string => Boolean(id));
    if (organizationNodeIds.length === 0) {
      throw new BadRequestException('Policy rule phai chon node to chuc');
    }

    const dataList = this.expandRuleBatch({
      policyCode,
      allowed,
      note,
      emailDomains,
      systemRoles,
      organizationNodeIds,
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

  private expandRuleBatch(input: {
    policyCode: string;
    allowed: boolean;
    note: string | null;
    emailDomains: Array<string | null>;
    systemRoles: Array<string | null>;
    organizationNodeIds: string[];
  }) {
    const dataList: NormalizedRuleInput[] = [];
    for (const emailDomain of input.emailDomains) {
      for (const systemRole of input.systemRoles) {
        for (const organizationNodeId of input.organizationNodeIds) {
          dataList.push({
            policyCode: input.policyCode,
            allowed: input.allowed,
            emailDomain,
            systemRole,
            departmentCode: null,
            jobRoleCode: null,
            workScopeType: null,
            regionCode: null,
            areaCode: null,
            organizationNodeId,
            storeCode: null,
            userId: null,
            scopeContains: null,
            note: input.note,
          });
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

    const full =
      user?.__authScopeSnapshot ??
      (await this.prisma.user.findUnique({
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
      }));
    const source = full ?? user;
    const scopeNodeId =
      this.effectiveScope(source) === 'STORE'
        ? (source.organizationNodeId ?? source.store?.organizationNodeId)
        : (source.organizationNodeId ?? source.store?.organizationNodeId);
    const organizationContext =
      await this.resolveOrganizationRuleContext(scopeNodeId);
    const area = this.areaForContextSource(source);
    const region = this.regionForContextSource(source);
    const baseContext: PolicyContext = {
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
      storeCode:
        organizationContext.storeCode ??
        source.store?.storeId ??
        source.storeCode ??
        null,
      storeName: source.store?.storeName ?? source.storeName ?? null,
      organizationScopeNames: organizationContext.scopeNames,
    };
    baseContext.alternateContexts = await this.resolveAlternatePolicyContexts(
      source,
      baseContext.organizationNodeId,
    );
    return baseContext;
  }

  private async resolveAlternatePolicyContexts(
    source: any,
    primaryOrganizationNodeId?: string | null,
  ) {
    const assignments = Array.isArray(source?.organizationAssignments)
      ? source.organizationAssignments
      : [];
    const seen = new Set<string>(
      [primaryOrganizationNodeId].filter(Boolean) as string[],
    );
    const contexts: PolicyContext[] = [];
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
        storeCode:
          organizationContext.storeCode ??
          assignmentStore?.storeId ??
          source.storeCode ??
          null,
        storeName: assignmentStore?.storeName ?? null,
        organizationScopeNames: organizationContext.scopeNames,
      });
    }
    return contexts;
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
    const nodes = await getOrganizationTree(this.prisma);
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
      return (
        node.businessCode || this.legacyCodeFromOrganizationCode(node.code)
      );
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
    if ([SUPER_ADMIN_ROLE, ADMIN_ROLE].includes(role || '')) {
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
