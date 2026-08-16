import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PasswordResetService } from '../auth/password-reset.service';
import { PrismaService } from '../prisma/prisma.service';

export type UserCredentialAdminRuntime = {
  assertAdmin: (admin: any) => Promise<void>;
  userDtoInclude: () => Prisma.UserInclude;
  normalizeRoleCode: (role: string) => string;
  isDomainAdmin: (admin: any) => boolean;
  userWithinAdminScope: (admin: any, user: any) => Promise<boolean>;
  userLogId: (user: any) => string;
  logger: {
    log: (message: string) => void;
  };
};

/**
 * Owns protected admin password-reset orchestration while UserService remains
 * the stable public facade and retains policy/scope helper ownership.
 */
export class UserCredentialAdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly passwordResetService: PasswordResetService,
    private readonly runtime: UserCredentialAdminRuntime,
  ) {}

  async adminSetUserPassword(admin: any, userId: string, newPassword: string) {
    await this.runtime.assertAdmin(admin);
    const target = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.runtime.userDtoInclude(),
    });
    if (!target) throw new NotFoundException('Không tìm thấy người dùng');

    if (
      this.runtime.normalizeRoleCode(target.role) === 'SUPER_ADMIN' &&
      this.runtime.normalizeRoleCode(admin.role) !== 'SUPER_ADMIN'
    ) {
      throw new ForbiddenException(
        'Bạn không có quyền reset mật khẩu tài khoản quản trị toàn hệ thống',
      );
    }
    if (this.runtime.normalizeRoleCode(admin.role) !== 'SUPER_ADMIN') {
      if (!this.runtime.isDomainAdmin(admin)) {
        throw new ForbiddenException(
          'Bạn không có quyền reset mật khẩu người dùng',
        );
      }
      if (!(await this.runtime.userWithinAdminScope(admin, target))) {
        throw new ForbiddenException(
          'Bạn không có quyền reset mật khẩu người dùng ngoài phạm vi quản lý',
        );
      }
    }

    this.runtime.logger.log(
      'Admin password reset started: admin=' +
        this.runtime.userLogId(admin) +
        ' role=' +
        admin.role +
        ' targetUserId=' +
        userId +
        ' targetRole=' +
        target.role,
    );
    const result = await this.passwordResetService.setPasswordForUserId(
      userId,
      newPassword,
      { id: admin.id, email: admin.email },
    );
    this.runtime.logger.log(
      'Admin password reset completed: admin=' +
        this.runtime.userLogId(admin) +
        ' role=' +
        admin.role +
        ' targetUserId=' +
        userId,
    );
    return result;
  }
}
