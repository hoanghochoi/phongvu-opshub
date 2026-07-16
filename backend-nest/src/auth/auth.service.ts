import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { JwtService } from '@nestjs/jwt';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDto } from './auth.dto';
import { EmailVerificationService } from './email-verification.service';
import { PasswordResetService } from './password-reset.service';
import { PolicyService } from '../policy/policy.service';
import { assertPasswordPolicy } from './password-policy';
import {
  AuthDeviceContext,
  AuthSessionClaims,
  AuthSessionService,
} from './auth-session.service';
import {
  allowedEmailDomainMessage,
  getAllowedEmailDomains,
} from './email-domain-policy';
import {
  SYSTEM_ROLE_ADMIN,
  SYSTEM_ROLE_SUPER_ADMIN,
  normalizeSystemRoleCode,
} from '../common/system-role';
import {
  firstStoreForOrganizationNodeTree,
  organizationNodeStoreTreeInclude,
  storesForOrganizationNodeTree,
} from '../common/organization-store-scope';
import { getOrganizationTree } from '../common/organization-tree-cache';

const PASSWORD_SALT_ROUNDS = 12;
const INVALID_CREDENTIALS_MESSAGE = 'Email hoặc mật khẩu không đúng';
const STORE_SCOPE = 'STORE';
const AREA_SCOPE = 'AREA';
const REGION_SCOPE = 'REGION';
const NATIONAL_SCOPE = 'NATIONAL';
const DEFAULT_REGION_CODE = 'CHUA_GAN';
const SUPER_ADMIN_ROLE = SYSTEM_ROLE_SUPER_ADMIN;
const ADMIN_ROLE = SYSTEM_ROLE_ADMIN;
const WORK_SCOPE_TYPES = new Set([
  STORE_SCOPE,
  AREA_SCOPE,
  REGION_SCOPE,
  NATIONAL_SCOPE,
]);

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly dummyPasswordHash = bcrypt.hash(
    randomBytes(32).toString('hex'),
    PASSWORD_SALT_ROUNDS,
  );

  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
    private emailVerificationService: EmailVerificationService,
    private passwordResetService: PasswordResetService,
    private authSessionService: AuthSessionService,
    private policyService: PolicyService,
  ) {}

  async passwordLogin(
    emailInput: string,
    password: string,
    device: AuthDeviceContext,
  ) {
    const email = this.normalizeEmail(emailInput);
    await this.assertAllowedDomain(email);
    const normalizedDevice = this.authSessionService.normalizeDevice(device);
    const emailHash = this.emailLogId(email);
    this.logger.log(
      `Password login started: emailHash=${emailHash} platform=${normalizedDevice.platform}`,
    );

    const user = await this.prisma.user.findUnique({
      where: { email },
      include: this.userDtoInclude(),
    });

    if (!user?.password) {
      await bcrypt.compare(password, await this.dummyPasswordHash);
      this.logger.warn(
        `Password login failed: emailHash=${emailHash} platform=${normalizedDevice.platform} reason=invalid_credentials`,
      );
      throw new UnauthorizedException(INVALID_CREDENTIALS_MESSAGE);
    }

    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      this.logger.warn(
        `Password login failed: emailHash=${emailHash} platform=${normalizedDevice.platform} reason=invalid_credentials`,
      );
      throw new UnauthorizedException(INVALID_CREDENTIALS_MESSAGE);
    }

    if (user.status === 'no') {
      throw new ForbiddenException('Tài khoản đã bị khóa. Liên hệ Quản lý.');
    }

    const session = await this.authSessionService.replacePlatformSession(
      user,
      normalizedDevice,
    );
    this.logger.log(
      `Password login succeeded: userId=${user.id} emailHash=${emailHash} platform=${session.platform} sessionVersion=${session.sessionVersion}`,
    );

    return this.buildLoginResponse(user, session);
  }

  async register(input: RegisterDto) {
    const email = this.normalizeEmail(input.email);
    await this.assertAllowedDomain(email);

    const firstName = input.firstName.trim();
    const lastName = input.lastName?.trim() || null;
    if (!firstName) {
      throw new BadRequestException('Vui lòng nhập họ tên');
    }

    const existingUser = await this.prisma.user.findUnique({
      where: { email },
      include: this.userDtoInclude(),
    });

    if (existingUser?.password) {
      throw new BadRequestException(
        'Email này đã được đăng ký. Vui lòng đăng nhập.',
      );
    }

    await this.emailVerificationService.consumeRegistrationCode(
      email,
      input.verificationCode,
    );

    const password = await this.hashPassword(input.password);
    const user = existingUser
      ? await this.prisma.user.update({
          where: { id: existingUser.id },
          data: { firstName, lastName, password, status: 'yes' },
          include: this.userDtoInclude(),
        })
      : await this.prisma.user.create({
          data: { email, firstName, lastName, password, status: 'yes' },
          include: this.userDtoInclude(),
        });

    const session = await this.authSessionService.replacePlatformSession(
      user,
      input,
    );
    this.logger.log(
      `Registration login session issued: userId=${user.id} emailHash=${this.emailLogId(email)} platform=${session.platform} sessionVersion=${session.sessionVersion}`,
    );

    return this.buildLoginResponse(user, session);
  }

  async sendRegistrationVerificationCode(emailInput: string) {
    const email = this.normalizeEmail(emailInput);
    await this.assertAllowedDomain(email);

    const existingUser = await this.prisma.user.findUnique({
      where: { email },
      select: { password: true },
    });
    if (existingUser?.password) {
      this.logger.warn(
        `Registration verification request ignored: emailHash=${this.emailLogId(email)} reason=account_already_registered`,
      );
      return this.emailVerificationService.registrationCodeResponse();
    }

    return this.emailVerificationService.sendRegistrationCode(email);
  }

  async changePassword(
    userId: string,
    currentPassword: string,
    newPassword: string,
    session: AuthSessionClaims,
  ) {
    assertPasswordPolicy(newPassword);

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.userDtoInclude(),
    });
    if (!user) throw new UnauthorizedException('User not found');
    if (!user.password) {
      throw new BadRequestException('Tài khoản chưa có mật khẩu.');
    }

    const isPasswordValid = await bcrypt.compare(
      currentPassword,
      user.password,
    );
    if (!isPasswordValid) {
      throw new UnauthorizedException('Mật khẩu hiện tại không đúng');
    }

    const password = await this.hashPassword(newPassword);
    const updated = await this.prisma.user.update({
      where: { id: user.id },
      data: {
        password,
        tokenVersion: { increment: 1 },
      },
      include: this.userDtoInclude(),
    });

    return this.buildLoginResponse(updated, session);
  }

  async logout(user: { id: string; authSession: AuthSessionClaims }) {
    return this.authSessionService.revokeCurrentSession(
      user.id,
      user.authSession,
      'LOGOUT',
    );
  }

  async forgotPassword(emailInput: string) {
    const email = this.normalizeEmail(emailInput);
    await this.assertAllowedDomain(email);
    return this.passwordResetService.sendResetCodeForEmail(email);
  }

  async verifyForgotPasswordCode(emailInput: string, code: string) {
    const email = this.normalizeEmail(emailInput);
    await this.assertAllowedDomain(email);
    return this.passwordResetService.verifyResetCode(email, code);
  }

  async resetPassword(token: string, newPassword: string) {
    return this.passwordResetService.resetPassword(token, newPassword);
  }

  async getUserData(email: string) {
    const user = await this.prisma.user.findUnique({
      where: { email },
      include: this.userDtoInclude(),
    });

    if (!user) throw new UnauthorizedException('User not found');

    return this.projectUserData(user);
  }

  async projectUserData(user: any) {
    if (!user) throw new UnauthorizedException('User not found');

    const role = this.normalizeRoleForOutput(user.role);
    const organizationProfile = this.organizationProfileFor(user);
    const scopedUser = this.userWithOrganizationProfile(
      user,
      organizationProfile,
    );
    const organizationAccessCodes =
      await this.organizationAccessCodesFor(scopedUser);

    return {
      name: user.firstName,
      firstName: user.firstName,
      lastName: user.lastName,
      avatarUrl: user.avatarUrl,
      storeId: organizationProfile.storeId,
      storeName: organizationProfile.storeName,
      role,
      status: user.status,
      departmentCode: user.departmentCode ?? null,
      jobRoleCode: user.jobRoleCode ?? null,
      workScopeType: this.effectiveWorkScope(scopedUser),
      regionCode: this.regionForUser(scopedUser)?.code ?? null,
      regionName: this.regionForUser(scopedUser)?.displayName ?? null,
      regionAbbreviation: this.regionForUser(scopedUser)?.abbreviation ?? null,
      areaCode: this.areaForUser(scopedUser)?.code ?? null,
      areaName: this.areaForUser(scopedUser)?.displayName ?? null,
      areaAbbreviation: this.areaForUser(scopedUser)?.abbreviation ?? null,
      organizationNodeId: organizationProfile.organizationNodeId,
      organizationNodeName: organizationProfile.organizationNodeName,
      organizationAssignments: organizationProfile.organizationAssignments,
      organizationNodeIds: organizationProfile.organizationNodeIds,
      assignedStores: organizationProfile.assignedStores,
      organizationAccessCodes,
      personnelCode: this.personnelCodeFor(scopedUser),
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      assignmentPending: this.assignmentPending(scopedUser),
      mustSelectStore: this.mustSelectStore(scopedUser),
    };
  }

  private normalizeEmail(emailInput: string) {
    const email = emailInput.trim().toLowerCase();
    if (!email || !email.includes('@')) {
      throw new BadRequestException('Email không hợp lệ');
    }
    return email;
  }

  private emailLogId(email: string) {
    return createHash('sha256').update(email).digest('hex').slice(0, 12);
  }

  private async assertAllowedDomain(email: string) {
    const fallbackDomains = getAllowedEmailDomains();
    const allowedDomains =
      await this.policyService.getAllowedEmailDomains(fallbackDomains);
    if (allowedDomains.length === 0) {
      throw new ForbiddenException('Chưa cấu hình domain email Phong Vũ');
    }

    const emailDomain = email.split('@')[1]?.toLowerCase();
    if (!emailDomain || !allowedDomains.includes(emailDomain)) {
      throw new ForbiddenException(allowedEmailDomainMessage());
    }
  }

  private async hashPassword(password: string) {
    return bcrypt.hash(password, PASSWORD_SALT_ROUNDS);
  }

  private userDtoInclude() {
    return {
      store: { include: { area: { include: { region: true } } } },
      region: true,
      area: { include: { region: true } },
      organizationNode: true,
      organizationAssignments: {
        where: { isActive: true },
        orderBy: [
          { isPrimary: Prisma.SortOrder.desc },
          { createdAt: Prisma.SortOrder.asc },
        ],
        include: {
          organizationNode: {
            include: organizationNodeStoreTreeInclude(),
          },
        },
      },
    };
  }

  private async buildLoginResponse(
    user: {
      id: string;
      email: string;
      firstName: string;
      lastName?: string | null;
      avatarUrl?: string | null;
      role: string;
      status: string;
      departmentCode?: string | null;
      jobRoleCode?: string | null;
      workScopeType?: string | null;
      regionCode?: string | null;
      areaCode?: string | null;
      organizationNodeId?: string | null;
      organizationNode?: { displayName?: string | null } | null;
      profileCompletedAt?: Date | null;
      branchLockedAt?: Date | null;
      storeId?: string | null;
      tokenVersion?: number | null;
      accessVersion?: number | null;
      region?: any | null;
      area?: any | null;
      store?: {
        storeId?: string | null;
        storeName?: string | null;
        area?: any | null;
      } | null;
    },
    session: AuthSessionClaims,
  ) {
    const role = this.normalizeRoleForOutput(user.role);
    const organizationProfile = this.organizationProfileFor(user);
    const scopedUser = this.userWithOrganizationProfile(
      user,
      organizationProfile,
    );
    const organizationAccessCodes =
      await this.organizationAccessCodesFor(scopedUser);
    const jwtPayload = {
      email: user.email,
      sub: user.id,
      role,
      storeUuid: scopedUser.storeId ?? null,
      storeCode: scopedUser.store?.storeId ?? null,
      departmentCode: user.departmentCode ?? null,
      organizationNodeId: organizationProfile.organizationNodeId,
      organizationAccessCodes,
      tokenVersion: user.tokenVersion ?? 0,
      accessVersion: user.accessVersion ?? 0,
      sessionId: session.sessionId,
      platform: session.platform,
      sessionVersion: session.sessionVersion,
    };
    return {
      login: true,
      access_token: this.jwtService.sign(jwtPayload),
      email: user.email,
      name: user.firstName,
      firstName: user.firstName,
      lastName: user.lastName,
      avatarUrl: user.avatarUrl,
      storeId: organizationProfile.storeId,
      storeName: organizationProfile.storeName,
      role,
      status: user.status,
      departmentCode: user.departmentCode ?? null,
      jobRoleCode: user.jobRoleCode ?? null,
      workScopeType: this.effectiveWorkScope(scopedUser),
      regionCode: this.regionForUser(scopedUser)?.code ?? null,
      regionName: this.regionForUser(scopedUser)?.displayName ?? null,
      regionAbbreviation: this.regionForUser(scopedUser)?.abbreviation ?? null,
      areaCode: this.areaForUser(scopedUser)?.code ?? null,
      areaName: this.areaForUser(scopedUser)?.displayName ?? null,
      areaAbbreviation: this.areaForUser(scopedUser)?.abbreviation ?? null,
      organizationNodeId: organizationProfile.organizationNodeId,
      organizationNodeName: organizationProfile.organizationNodeName,
      organizationAssignments: organizationProfile.organizationAssignments,
      organizationNodeIds: organizationProfile.organizationNodeIds,
      assignedStores: organizationProfile.assignedStores,
      organizationAccessCodes,
      personnelCode: this.personnelCodeFor(scopedUser),
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      assignmentPending: this.assignmentPending(scopedUser),
      mustSelectStore: this.mustSelectStore(scopedUser),
    };
  }

  private organizationProfileFor(user: any) {
    const activeAssignments = Array.isArray(user?.organizationAssignments)
      ? user.organizationAssignments.filter(
          (assignment: any) => assignment?.isActive !== false,
        )
      : [];
    const primaryAssignment =
      activeAssignments.find((assignment: any) => assignment?.isPrimary) ??
      activeAssignments[0] ??
      null;
    const primaryAssignmentNode = primaryAssignment?.organizationNode ?? null;
    const primaryAssignmentStore =
      firstStoreForOrganizationNodeTree(primaryAssignmentNode) ??
      user?.store ??
      null;
    const effectiveOrganizationNode =
      primaryAssignmentNode ??
      user?.organizationNode ??
      user?.store?.organizationNode ??
      null;
    const effectiveOrganizationNodeId =
      primaryAssignment?.organizationNodeId ??
      user?.organizationNodeId ??
      effectiveOrganizationNode?.id ??
      user?.store?.organizationNodeId ??
      null;

    const assignedStoresByCode = new Map<string, any>();
    const pushStore = (store?: any | null) => {
      const code = String(store?.storeId || '')
        .trim()
        .toUpperCase();
      if (code && !assignedStoresByCode.has(code)) {
        assignedStoresByCode.set(code, store);
      }
    };
    for (const assignment of activeAssignments) {
      for (const store of storesForOrganizationNodeTree(
        assignment?.organizationNode,
      )) {
        pushStore(store);
      }
    }
    pushStore(primaryAssignmentStore);

    const assignedStores = Array.from(assignedStoresByCode.values()).map(
      (store) => ({
        id: store.id ?? null,
        storeId: store.storeId ?? null,
        storeName: store.storeName ?? null,
        organizationNodeId: store.organizationNodeId ?? null,
      }),
    );
    const organizationAssignments = activeAssignments.map((assignment: any) => {
      const node = assignment?.organizationNode ?? null;
      const store = firstStoreForOrganizationNodeTree(node);
      return {
        id: assignment.id,
        organizationNodeId: assignment.organizationNodeId,
        organizationNodeName: node?.displayName ?? null,
        organizationNodeType: node?.type ?? null,
        storeId: store?.storeId ?? null,
        storeName: store?.storeName ?? null,
        isPrimary: assignment.isPrimary === true,
      };
    });

    return {
      primaryStore: primaryAssignmentStore,
      organizationNode: effectiveOrganizationNode,
      storeId: primaryAssignmentStore?.storeId ?? null,
      storeName: primaryAssignmentStore?.storeName ?? null,
      organizationNodeId: effectiveOrganizationNodeId,
      organizationNodeName: effectiveOrganizationNode?.displayName ?? null,
      organizationAssignments,
      organizationNodeIds: organizationAssignments.map(
        (assignment: { organizationNodeId: string }) =>
          assignment.organizationNodeId,
      ),
      assignedStores,
    };
  }

  private userWithOrganizationProfile(
    user: any,
    profile: ReturnType<AuthService['organizationProfileFor']>,
  ) {
    const primaryStore = profile.primaryStore ?? user?.store ?? null;
    return {
      ...user,
      organizationNodeId: profile.organizationNodeId,
      organizationNode: profile.organizationNode ?? user?.organizationNode,
      storeId: primaryStore?.id ?? user?.storeId ?? null,
      store: primaryStore,
    };
  }

  private async organizationAccessCodesFor(user: {
    departmentCode?: string | null;
    organizationNodeId?: string | null;
  }) {
    const codes = new Set<string>();
    const addCode = (value: unknown) => {
      const code = this.normalizeAccessCode(value);
      if (code) codes.add(code);
    };
    addCode(user.departmentCode);

    const organizationNodeId = String(user.organizationNodeId || '').trim();
    if (!organizationNodeId) return Array.from(codes);

    const organizationNode = (this.prisma as any).organizationNode;
    if (!organizationNode?.findMany) return Array.from(codes);

    const nodes = await getOrganizationTree(this.prisma);
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const visited = new Set<string>();
    let cursor = byId.get(organizationNodeId);
    while (cursor && !visited.has(cursor.id)) {
      visited.add(cursor.id);
      addCode(cursor.code);
      addCode(cursor.businessCode);
      cursor = cursor.parentId ? byId.get(cursor.parentId) : undefined;
    }
    return Array.from(codes);
  }

  private mustSelectStore(user: {
    role: string;
    workScopeType?: string | null;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    return false;
  }

  private assignmentPending(user: {
    role: string;
    organizationNodeId?: string | null;
  }) {
    const role = this.normalizeRoleForOutput(user.role);
    if (role === SUPER_ADMIN_ROLE || role === ADMIN_ROLE) return false;
    return !user.organizationNodeId;
  }

  private effectiveWorkScope(user: {
    role: string;
    workScopeType?: string | null;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    const scope = String(user.workScopeType || '')
      .trim()
      .toUpperCase();
    if (WORK_SCOPE_TYPES.has(scope)) return scope;
    const role = this.normalizeRoleForOutput(user.role);
    if (role === SUPER_ADMIN_ROLE || role === ADMIN_ROLE) {
      return NATIONAL_SCOPE;
    }
    return STORE_SCOPE;
  }

  private normalizeRoleForOutput(role: string | null | undefined) {
    return normalizeSystemRoleCode(role) ?? '';
  }

  private normalizeAccessCode(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase();
  }

  private personnelCodeFor(user: {
    role: string;
    jobRoleCode?: string | null;
    workScopeType?: string | null;
    storeId?: string | null;
    region?: any | null;
    area?: any | null;
    store?: { storeId?: string | null; area?: any | null } | null;
  }) {
    const jobRoleCode = String(user.jobRoleCode || '')
      .trim()
      .toUpperCase();
    if (!jobRoleCode) return null;
    const scope = this.effectiveWorkScope(user);
    const area = this.areaForUser(user);
    const region = this.regionForUser(user);
    const areaAbbr = this.scopeAbbreviation(area?.abbreviation || area?.code);
    const regionAbbr = this.scopeAbbreviation(
      region?.abbreviation || region?.code,
    );
    if (scope === STORE_SCOPE) {
      const storeCode = this.scopeAbbreviation(user.store?.storeId || 'STORE');
      return `${jobRoleCode}_${storeCode}_${areaAbbr}_${regionAbbr}`;
    }
    if (scope === AREA_SCOPE) {
      return `${jobRoleCode}_${areaAbbr}_${areaAbbr}_${regionAbbr}`;
    }
    if (scope === REGION_SCOPE) {
      return `${jobRoleCode}_${regionAbbr}_${regionAbbr}_${regionAbbr}`;
    }
    return `${jobRoleCode}_NATIONAL_NATIONAL_NATIONAL`;
  }

  private areaForUser(user: any) {
    if (this.effectiveWorkScope(user) === STORE_SCOPE) {
      return user?.store?.area ?? user?.area ?? null;
    }
    return user?.area ?? user?.store?.area ?? null;
  }

  private regionForUser(user: any) {
    if (this.effectiveWorkScope(user) === STORE_SCOPE) {
      const storeArea = user?.store?.area ?? null;
      return storeArea?.region ?? user?.region ?? user?.area?.region ?? null;
    }
    const area = this.areaForUser(user);
    return user?.region ?? area?.region ?? user?.store?.area?.region ?? null;
  }

  private scopeAbbreviation(value?: string | null) {
    const code = String(value || DEFAULT_REGION_CODE)
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '_');
    return code || DEFAULT_REGION_CODE;
  }
}
