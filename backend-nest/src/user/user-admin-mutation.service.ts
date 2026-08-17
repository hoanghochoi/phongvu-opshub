import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AccessChangeService } from '../auth/access-change.service';
import { PrismaService } from '../prisma/prisma.service';
import type { PreparedAdminUserMutation } from './user-admin-mutation-preparation.service';

export type { PreparedAdminUserMutation } from './user-admin-mutation-preparation.service';

export type UserAdminMutationRuntime = {
  assertAdmin: (admin: any) => Promise<void>;
  assertSuperAdminCanCreateUsers: (admin: any) => Promise<void>;
  assertSuperAdminCanDeleteUsers: (admin: any) => Promise<void>;
  assertAdminCanUpdateUser: (
    admin: any,
    userId: string,
    current: any,
  ) => Promise<void>;
  prepareAdminUserMutation: (
    admin: any,
    body: any,
    current: any | null,
  ) => Promise<PreparedAdminUserMutation>;
  syncUserOrganizationAssignments: (
    client: Prisma.TransactionClient,
    userId: string,
    organizationNodeIds: string[],
    admin: any,
  ) => Promise<void>;
  userDtoInclude: () => Prisma.UserInclude;
  toUserDto: (user: any) => any;
  sendWelcomeEmail: (
    user: any,
    context: { source: string; admin: any; rowNumber?: number },
  ) => Promise<{ sent: boolean; error: string | null }>;
  userAccessFingerprint: (user: any) => string;
  userDeleteBlockers: (userId: string) => Promise<string[]>;
  userLogId: (admin: any) => string;
  personnelCodeFor: (user: any) => string | null | undefined;
  normalizeRoleCode: (role: string, preserve?: boolean) => string;
  emailHash: (email: string) => string;
  logger: {
    log: (message: string) => void;
    warn: (message: string) => void;
  };
};

/**
 * Owns the admin create/update/delete mutation orchestration while UserService
 * remains the stable public facade and retains the policy/data helpers.
 */
export class UserAdminMutationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly accessChangeService: AccessChangeService,
    private readonly runtime: UserAdminMutationRuntime,
  ) {}

  async adminCreateUser(admin: any, body: any) {
    await this.runtime.assertAdmin(admin);
    await this.runtime.assertSuperAdminCanCreateUsers(admin);
    const prepared = await this.runtime.prepareAdminUserMutation(
      admin,
      body,
      null,
    );

    const { user, saved } = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: prepared.createData as any,
        include: this.runtime.userDtoInclude(),
      });
      await this.runtime.syncUserOrganizationAssignments(
        tx,
        user.id,
        prepared.organizationNodeIds,
        admin,
      );
      const saved = await tx.user.findUnique({
        where: { id: user.id },
        include: this.runtime.userDtoInclude(),
      });
      return { user, saved };
    });
    this.runtime.logger.log(
      `Admin user created: emailHash=${this.runtime.emailHash(prepared.email)} role=${prepared.role} scope=${prepared.workScopeType} personnelCode=${this.runtime.personnelCodeFor(user) ?? 'none'}`,
    );
    const welcomeEmail = await this.runtime.sendWelcomeEmail(saved ?? user, {
      source: 'admin-create',
      admin,
    });
    return {
      ...this.runtime.toUserDto(saved ?? user),
      welcomeEmailSent: welcomeEmail.sent,
      welcomeEmailError: welcomeEmail.error,
    };
  }

  async adminUpdateUser(admin: any, userId: string, body: any) {
    await this.runtime.assertAdmin(admin);
    const current = await this.prisma.user.findUnique({
      where: { id: userId },
      include: this.runtime.userDtoInclude(),
    });
    if (!current) throw new NotFoundException('Không tìm thấy người dùng');

    await this.runtime.assertAdminCanUpdateUser(admin, userId, current);
    const prepared = await this.runtime.prepareAdminUserMutation(
      admin,
      body,
      current,
    );

    const { updated, saved } = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.user.update({
        where: { id: userId },
        data: prepared.updateData as any,
        include: this.runtime.userDtoInclude(),
      });
      await this.runtime.syncUserOrganizationAssignments(
        tx,
        userId,
        prepared.organizationNodeIds,
        admin,
      );
      const saved = await tx.user.findUnique({
        where: { id: userId },
        include: this.runtime.userDtoInclude(),
      });
      return { updated, saved };
    });
    this.runtime.logger.log(
      `Admin user updated: id=${userId} role=${prepared.role} scope=${prepared.workScopeType} personnelCode=${this.runtime.personnelCodeFor(updated) ?? 'none'}`,
    );
    if (
      this.runtime.userAccessFingerprint(current) !==
      this.runtime.userAccessFingerprint(saved ?? updated)
    ) {
      await this.accessChangeService.publishForUserIds(
        [userId],
        'user-access-updated',
      );
    }
    return this.runtime.toUserDto(saved ?? updated);
  }

  async adminDeleteUser(admin: any, userId: string) {
    await this.runtime.assertAdmin(admin);
    await this.runtime.assertSuperAdminCanDeleteUsers(admin);
    const id = String(userId || '').trim();
    if (!id) throw new BadRequestException('Người dùng không hợp lệ');
    if (admin?.id && admin.id === id) {
      throw new BadRequestException(
        'Không thể tự xóa tài khoản đang đăng nhập',
      );
    }

    const current = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        role: true,
        status: true,
      },
    });
    if (!current) throw new NotFoundException('Không tìm thấy người dùng');
    if (this.runtime.normalizeRoleCode(current.role, true) === 'SUPER_ADMIN') {
      throw new BadRequestException(
        'Không thể xóa tài khoản quản trị toàn hệ thống',
      );
    }
    if (String(current.status || '').toLowerCase() !== 'no') {
      throw new BadRequestException('Chỉ xóa được tài khoản đã khóa');
    }

    const blockers = await this.runtime.userDeleteBlockers(current.id);
    if (blockers.length > 0) {
      this.runtime.logger.warn(
        `Admin user delete blocked: admin=${this.runtime.userLogId(admin)} targetUserId=${current.id} blockers=${blockers.join(',')}`,
      );
      throw new BadRequestException(
        'Tài khoản đang có dữ liệu lịch sử, không thể xóa hoàn toàn: ' +
          blockers.join(', '),
      );
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.userPlatformSession.deleteMany({
        where: { userId: current.id },
      });
      await tx.passwordResetToken.deleteMany({ where: { userId: current.id } });
      await tx.emailVerificationCode.deleteMany({
        where: { email: current.email },
      });
      await tx.adminPolicyRule.deleteMany({ where: { userId: current.id } });
      await tx.featureAccessRule.deleteMany({ where: { userId: current.id } });
      await tx.userFeatureAssignment.deleteMany({
        where: { userId: current.id },
      });
      await tx.user.delete({ where: { id: current.id } });
    });

    this.runtime.logger.warn(
      `Admin user deleted: admin=${this.runtime.userLogId(admin)} targetUserId=${current.id}`,
    );
    await this.accessChangeService.publishForUserIds(
      [current.id],
      'user-access-deleted',
    );
    return { deleted: true, id: current.id, email: current.email };
  }
}
