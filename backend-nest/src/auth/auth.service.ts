import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDto } from './auth.dto';
import { EmailVerificationService } from './email-verification.service';
import {
  allowedEmailDomainMessage,
  getAllowedEmailDomains,
  isAllowedEmailDomain,
} from './email-domain-policy';

const PASSWORD_SALT_ROUNDS = 12;

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
    private emailVerificationService: EmailVerificationService,
  ) {}

  async passwordLogin(emailInput: string, password: string) {
    const email = this.normalizeEmail(emailInput);
    this.assertAllowedDomain(email);

    const user = await this.prisma.user.findUnique({
      where: { email },
      include: { store: true },
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
      throw new UnauthorizedException('Email hoac mat khau khong dung');
    }

    if (user.status === 'no') {
      throw new ForbiddenException('Tai khoan da bi khoa. Lien he Quan ly.');
    }

    return this.buildLoginResponse(user);
  }

  async register(input: RegisterDto) {
    const email = this.normalizeEmail(input.email);
    this.assertAllowedDomain(email);

    const firstName = input.firstName.trim();
    const lastName = input.lastName?.trim() || null;
    if (!firstName) {
      throw new BadRequestException('Vui long nhap ho ten');
    }

    const existingUser = await this.prisma.user.findUnique({
      where: { email },
      include: { store: true },
    });

    if (existingUser?.password) {
      throw new BadRequestException(
        'Email nay da duoc dang ky. Vui long dang nhap.',
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
          include: { store: true },
        })
      : await this.prisma.user.create({
          data: { email, firstName, lastName, password, status: 'yes' },
          include: { store: true },
        });

    return this.buildLoginResponse(user);
  }

  async sendRegistrationVerificationCode(emailInput: string) {
    const email = this.normalizeEmail(emailInput);
    this.assertAllowedDomain(email);

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

  async getUserData(email: string) {
    const user = await this.prisma.user.findUnique({
      where: { email },
      include: { store: true },
    });

    if (!user) throw new UnauthorizedException('User not found');

    return {
      name: user.firstName,
      firstName: user.firstName,
      lastName: user.lastName,
      avatarUrl: user.avatarUrl,
      storeId: user.store?.storeId ?? null,
      storeName: user.store?.storeName ?? null,
      role: user.role,
      status: user.status,
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      mustSelectStore: this.mustSelectStore(user),
    };
  }

  private normalizeEmail(emailInput: string) {
    const email = emailInput.trim().toLowerCase();
    if (!email || !email.includes('@')) {
      throw new BadRequestException('Email khong hop le');
    }
    return email;
  }

  private assertAllowedDomain(email: string) {
    if (getAllowedEmailDomains().length === 0) {
      throw new ForbiddenException('Chua cau hinh domain email Phong Vu');
    }

    if (!isAllowedEmailDomain(email)) {
      throw new ForbiddenException(allowedEmailDomainMessage());
    }
  }

  private async hashPassword(password: string) {
    return bcrypt.hash(password, PASSWORD_SALT_ROUNDS);
  }

  private buildLoginResponse(user: {
    id: string;
    email: string;
    firstName: string;
    lastName?: string | null;
    avatarUrl?: string | null;
    role: string;
    status: string;
    profileCompletedAt?: Date | null;
    branchLockedAt?: Date | null;
    storeId?: string | null;
    store?: { storeId?: string | null; storeName?: string | null } | null;
  }) {
    const jwtPayload = { email: user.email, sub: user.id, role: user.role };
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
      role: user.role,
      status: user.status,
      profileCompletedAt: user.profileCompletedAt,
      branchLockedAt: user.branchLockedAt,
      mustSelectStore: this.mustSelectStore(user),
    };
  }

  private mustSelectStore(user: {
    role: string;
    storeId?: string | null;
    store?: { storeId?: string | null } | null;
  }) {
    const hasStore = Boolean(user.storeId || user.store?.storeId);
    return user.role !== 'SUPER_ADMIN' && user.role !== 'ADMIN' && !hasStore;
  }
}
