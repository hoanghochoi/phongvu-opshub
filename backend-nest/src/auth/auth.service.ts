import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { JwtService } from '@nestjs/jwt';
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
import { BREAK_GLASS_SUPER_ADMIN_EMAIL } from './break-glass-admin.constants';

const PASSWORD_SALT_ROUNDS = 12;
const STORE_SCOPE = 'STORE';
const AREA_SCOPE = 'AREA';
const REGION_SCOPE = 'REGION';
const NATIONAL_SCOPE = 'NATIONAL';
const DEFAULT_REGION_CODE = 'CHUA_GAN';
const SUPER_ADMIN_ROLE = 'SUPER_ADMIN';
const LEGACY_ADMIN_ROLE = 'ADMIN';
const ADMIN_PHONGVU_ROLE = 'ADMIN_PHONGVU';
const ADMIN_ACARE_ROLE = 'ADMIN_ACARE';
const WORK_SCOPE_TYPES = new Set([
  STORE_SCOPE,
  AREA_SCOPE,
  REGION_SCOPE,
  NATIONAL_SCOPE,
]);

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

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
    this.logger.log(
      `Password login started: email=${email} platform=${normalizedDevice.platform}`,
    );

    const user = await this.prisma.user.findUnique({
      where: { email },
      include: this.userDtoInclude(),
    });

    if (!user) {
      throw new UnauthorizedException(
        'Tài khoản chưa tồn tại. Vui lòng tạo tài khoản trước.',
      );
    }

    if (!user.password) {
      throw new UnauthorizedException(
        'Tài khoản chưa có mật khẩu. Vui lòng tạo tài khoản trước.',
      );
    }

    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      this.logger.warn(
        `Password login failed: email=${email} platform=${normalizedDevice.platform} reason=invalid_password`,
      );
      throw new UnauthorizedException('Email hoặc mật khẩu không đúng');
    }

    if (user.status === 'no') {
      throw new ForbiddenException('Tài khoản đã bị khóa. Liên hệ Quản lý.');
    }

    const session = await this.authSessionService.replacePlatformSession(
      user,
      normalizedDevice,
    );
    this.logger.log(
      `Password login succeeded: userId=${user.id} email=${email} platform=${session.platform} sessionVersion=${session.sessionVersion}`,
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
      `Registration login session issued: userId=${user.id} email=${email} platform=${session.platform} sessionVersion=${session.sessionVersion}`,
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
      throw new BadRequestException(
        'Email này đã được đăng ký. Vui lòng đăng nhập.',
      );
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

    const role = this.normalizeRoleForOutput(user.role);

    return {
      name: user.firstName,
      firstName: user.firstName,
      lastName: user.lastName,
      avatarUrl: user.avatarUrl,
      storeId: user.store?.storeId ?? null,
      storeName: user.store?.storeName ?? null,
      role,
      status: user.status,
      departmentCode: user.departmentCode ?? null,
      jobRoleCode: user.jobRoleCode ?? null,
      workScopeType: this.effectiveWorkScope(user),
      regionCode: this.regionForUser(user)?.code ?? null,
      regionName: this.regionForUser(user)?.displayName ?? null,
      regionAbbreviation: this.regionForUser(user)?.abbreviation ?? null,
      areaCode: this.areaForUser(user)?.code ?? null,
      areaName: this.areaForUser(user)?.displayName ?? null,
      areaAbbreviation: this.areaForUser(user)?.abbreviation ?? null,
      personnelCode: this.personnelCodeFor(user),
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      mustSelectStore: this.mustSelectStore(user),
    };
  }

  private normalizeEmail(emailInput: string) {
    const email = emailInput.trim().toLowerCase();
    if (!email || !email.includes('@')) {
      throw new BadRequestException('Email không hợp lệ');
    }
    return email;
  }

  private async assertAllowedDomain(email: string) {
    if (email === BREAK_GLASS_SUPER_ADMIN_EMAIL) return;

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
    };
  }

  private buildLoginResponse(
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
      profileCompletedAt?: Date | null;
      branchLockedAt?: Date | null;
      storeId?: string | null;
      tokenVersion?: number | null;
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
    const jwtPayload = {
      email: user.email,
      sub: user.id,
      role,
      storeUuid: user.storeId ?? null,
      storeCode: user.store?.storeId ?? null,
      tokenVersion: user.tokenVersion ?? 0,
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
      storeId: user.store?.storeId ?? null,
      storeName: user.store?.storeName ?? null,
      role,
      status: user.status,
      departmentCode: user.departmentCode ?? null,
      jobRoleCode: user.jobRoleCode ?? null,
      workScopeType: this.effectiveWorkScope(user),
      regionCode: this.regionForUser(user)?.code ?? null,
      regionName: this.regionForUser(user)?.displayName ?? null,
      regionAbbreviation: this.regionForUser(user)?.abbreviation ?? null,
      areaCode: this.areaForUser(user)?.code ?? null,
      areaName: this.areaForUser(user)?.displayName ?? null,
      areaAbbreviation: this.areaForUser(user)?.abbreviation ?? null,
      personnelCode: this.personnelCodeFor(user),
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      mustSelectStore: this.mustSelectStore(user),
    };
  }

  private mustSelectStore(user: {
    role: string;
    workScopeType?: string | null;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    const hasStore = Boolean(user.storeId || user.store?.storeId);
    return this.effectiveWorkScope(user) === STORE_SCOPE && !hasStore;
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
    if (
      role === SUPER_ADMIN_ROLE ||
      role === ADMIN_PHONGVU_ROLE ||
      role === ADMIN_ACARE_ROLE
    ) {
      return NATIONAL_SCOPE;
    }
    return STORE_SCOPE;
  }

  private normalizeRoleForOutput(role: string | null | undefined) {
    const code = String(role || '')
      .trim()
      .toUpperCase();
    if (code === LEGACY_ADMIN_ROLE) return ADMIN_PHONGVU_ROLE;
    return role ?? '';
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
