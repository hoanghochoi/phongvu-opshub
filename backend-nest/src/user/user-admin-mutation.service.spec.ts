import { BadRequestException, NotFoundException } from '@nestjs/common';
import {
  UserAdminMutationService,
  type PreparedAdminUserMutation,
  type UserAdminMutationRuntime,
} from './user-admin-mutation.service';

describe('UserAdminMutationService', () => {
  function createHarness() {
    const user = {
      create: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
    };
    const tx = { user };
    const prisma = {
      user,
      $transaction: jest.fn(async (callback) => callback(tx)),
    };
    const accessChangeService = {
      publishForUserIds: jest.fn().mockResolvedValue(undefined),
    };
    const runtime: UserAdminMutationRuntime = {
      assertAdmin: jest.fn().mockResolvedValue(undefined),
      assertSuperAdminCanCreateUsers: jest.fn().mockResolvedValue(undefined),
      assertSuperAdminCanDeleteUsers: jest.fn().mockResolvedValue(undefined),
      assertAdminCanUpdateUser: jest.fn().mockResolvedValue(undefined),
      prepareAdminUserMutation: jest.fn(),
      syncUserOrganizationAssignments: jest.fn().mockResolvedValue(undefined),
      userDtoInclude: jest.fn().mockReturnValue({ organizationNode: true }),
      toUserDto: jest.fn((user) => ({ id: user.id, email: user.email })),
      sendWelcomeEmail: jest
        .fn()
        .mockResolvedValue({ sent: true, error: null }),
      userAccessFingerprint: jest.fn(
        (user) => user.accessFingerprint ?? 'same',
      ),
      userDeleteBlockers: jest.fn().mockResolvedValue([]),
      userLogId: jest.fn((admin) => `user:${admin.id}`),
      personnelCodeFor: jest.fn().mockReturnValue(null),
      normalizeRoleCode: jest.fn((role) => role),
      emailHash: jest.fn((email) => `hash:${email}`),
      logger: {
        log: jest.fn(),
        warn: jest.fn(),
      },
    };
    const service = new UserAdminMutationService(
      prisma as any,
      accessChangeService as any,
      runtime,
    );
    return { prisma, tx, accessChangeService, runtime, service };
  }

  function preparedMutation(): PreparedAdminUserMutation {
    return {
      email: 'new@phongvu.vn',
      role: 'USER',
      workScopeType: 'STORE',
      personnel: { organizationNodeId: 'node-1' },
      organizationNodeIds: ['node-1'],
      createData: {
        email: 'new@phongvu.vn',
        firstName: 'Nguyễn',
        lastName: 'Văn A',
      },
      updateData: { firstName: 'Nguyễn', lastName: 'Văn A' },
    };
  }

  it('authorizes before persistence and keeps create/welcome orchestration intact', async () => {
    const { service, runtime, prisma, tx } = createHarness();
    const admin = { id: 'admin-1', role: 'SUPER_ADMIN' };
    const prepared = preparedMutation();
    const created = {
      id: 'user-1',
      email: prepared.email,
      role: prepared.role,
    };
    const saved = { ...created, firstName: 'Nguyễn', lastName: 'Văn A' };
    (runtime.prepareAdminUserMutation as jest.Mock).mockResolvedValue(prepared);
    prisma.user.create.mockResolvedValue(created);
    prisma.user.findUnique.mockResolvedValue(saved);
    let committed = false;
    prisma.$transaction.mockImplementation(async (callback) => {
      const result = await callback(tx);
      committed = true;
      return result;
    });
    (runtime.sendWelcomeEmail as jest.Mock).mockImplementation(async () => {
      expect(committed).toBe(true);
      return {
        sent: false,
        error: 'Mail service unavailable',
      };
    });

    const result = await service.adminCreateUser(admin, {
      email: prepared.email,
    });

    expect(runtime.assertAdmin).toHaveBeenCalledWith(admin);
    expect(runtime.assertSuperAdminCanCreateUsers).toHaveBeenCalledWith(admin);
    expect(runtime.prepareAdminUserMutation).toHaveBeenCalledWith(
      admin,
      { email: prepared.email },
      null,
    );
    expect(prisma.user.create).toHaveBeenCalledWith({
      data: prepared.createData,
      include: { organizationNode: true },
    });
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenCalledWith(
      tx,
      'user-1',
      ['node-1'],
      admin,
    );
    expect(runtime.sendWelcomeEmail).toHaveBeenCalledWith(saved, {
      source: 'admin-create',
      admin,
    });
    expect(result).toEqual({
      id: 'user-1',
      email: prepared.email,
      welcomeEmailSent: false,
      welcomeEmailError: 'Mail service unavailable',
    });
    expect(
      (runtime.assertAdmin as jest.Mock).mock.invocationCallOrder[0],
    ).toBeLessThan(prisma.user.create.mock.invocationCallOrder[0]);
  });

  it('keeps create and assignment synchronization in one rollback boundary', async () => {
    const { service, runtime, prisma, tx, accessChangeService } =
      createHarness();
    const failure = new Error('assignment write failed');
    const prepared = preparedMutation();
    const created = {
      id: 'user-1',
      email: prepared.email,
      role: prepared.role,
    };
    (runtime.prepareAdminUserMutation as jest.Mock).mockResolvedValue(prepared);
    prisma.user.create.mockResolvedValue(created);
    (runtime.syncUserOrganizationAssignments as jest.Mock).mockRejectedValue(
      failure,
    );

    await expect(
      service.adminCreateUser(
        { id: 'admin-1', role: 'SUPER_ADMIN' },
        { email: prepared.email },
      ),
    ).rejects.toBe(failure);

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenCalledWith(
      tx,
      'user-1',
      ['node-1'],
      { id: 'admin-1', role: 'SUPER_ADMIN' },
    );
    expect(runtime.sendWelcomeEmail).not.toHaveBeenCalled();
    expect(accessChangeService.publishForUserIds).not.toHaveBeenCalled();
  });

  it('stops create before mutation when admin authorization fails', async () => {
    const { service, runtime, prisma } = createHarness();
    const authorizationError = new Error('forbidden');
    (runtime.assertAdmin as jest.Mock).mockRejectedValueOnce(
      authorizationError,
    );

    await expect(
      service.adminCreateUser({ id: 'admin-1' }, { email: 'new@phongvu.vn' }),
    ).rejects.toBe(authorizationError);

    expect(runtime.assertSuperAdminCanCreateUsers).not.toHaveBeenCalled();
    expect(runtime.prepareAdminUserMutation).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('rejects a missing update target before preparation or persistence', async () => {
    const { service, runtime, prisma } = createHarness();
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.adminUpdateUser(
        { id: 'admin-1', role: 'ADMIN' },
        'missing-user',
        { firstName: 'A' },
      ),
    ).rejects.toEqual(new NotFoundException('Không tìm thấy người dùng'));

    expect(runtime.assertAdmin).toHaveBeenCalled();
    expect(runtime.assertAdminCanUpdateUser).not.toHaveBeenCalled();
    expect(runtime.prepareAdminUserMutation).not.toHaveBeenCalled();
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('updates the prepared data and publishes access invalidation only after a fingerprint change', async () => {
    const { service, runtime, prisma, tx, accessChangeService } =
      createHarness();
    const admin = { id: 'admin-1', role: 'ADMIN' };
    const current = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      accessFingerprint: 'before',
    };
    const updated = { ...current, accessFingerprint: 'after' };
    const saved = { ...updated, firstName: 'B' };
    const prepared = preparedMutation();
    prepared.updateData = { firstName: 'B' };
    (runtime.prepareAdminUserMutation as jest.Mock).mockResolvedValue(prepared);
    prisma.user.findUnique
      .mockResolvedValueOnce(current)
      .mockResolvedValueOnce(saved);
    prisma.user.update.mockResolvedValue(updated);
    let committed = false;
    prisma.$transaction.mockImplementation(async (callback) => {
      const result = await callback(tx);
      committed = true;
      return result;
    });
    accessChangeService.publishForUserIds.mockImplementation(async () => {
      expect(committed).toBe(true);
    });

    await expect(
      service.adminUpdateUser(admin, 'user-1', { firstName: 'B' }),
    ).resolves.toEqual({ id: 'user-1', email: 'staff@phongvu.vn' });

    expect(runtime.assertAdminCanUpdateUser).toHaveBeenCalledWith(
      admin,
      'user-1',
      current,
    );
    expect(runtime.prepareAdminUserMutation).toHaveBeenCalledWith(
      admin,
      { firstName: 'B' },
      current,
    );
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'user-1' },
      data: prepared.updateData,
      include: { organizationNode: true },
    });
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenCalledWith(
      tx,
      'user-1',
      ['node-1'],
      admin,
    );
    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      ['user-1'],
      'user-access-updated',
    );
    expect(
      accessChangeService.publishForUserIds.mock.invocationCallOrder[0],
    ).toBeGreaterThan(prisma.user.findUnique.mock.invocationCallOrder[1]);
  });

  it('rolls back update assignment failures without publishing access changes', async () => {
    const { service, runtime, prisma, tx, accessChangeService } =
      createHarness();
    const failure = new Error('assignment write failed');
    const current = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      accessFingerprint: 'before',
    };
    const prepared = preparedMutation();
    prepared.updateData = { firstName: 'B' };
    prisma.user.findUnique.mockResolvedValueOnce(current);
    prisma.user.update.mockResolvedValue({
      ...current,
      accessFingerprint: 'after',
    });
    (runtime.prepareAdminUserMutation as jest.Mock).mockResolvedValue(prepared);
    (runtime.syncUserOrganizationAssignments as jest.Mock).mockRejectedValue(
      failure,
    );

    await expect(
      service.adminUpdateUser({ id: 'admin-1', role: 'ADMIN' }, 'user-1', {
        firstName: 'B',
      }),
    ).rejects.toBe(failure);

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenCalledWith(
      tx,
      'user-1',
      ['node-1'],
      { id: 'admin-1', role: 'ADMIN' },
    );
    expect(accessChangeService.publishForUserIds).not.toHaveBeenCalled();
  });

  it('does not publish access invalidation when update keeps the same fingerprint', async () => {
    const { service, runtime, prisma, accessChangeService } = createHarness();
    const current = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      accessFingerprint: 'same',
    };
    const prepared = preparedMutation();
    prisma.user.findUnique
      .mockResolvedValueOnce(current)
      .mockResolvedValueOnce({ ...current, firstName: 'B' });
    prisma.user.update.mockResolvedValue({ ...current, firstName: 'B' });
    (runtime.prepareAdminUserMutation as jest.Mock).mockResolvedValue(prepared);

    await service.adminUpdateUser({ id: 'admin-1', role: 'ADMIN' }, 'user-1', {
      firstName: 'B',
    });

    expect(accessChangeService.publishForUserIds).not.toHaveBeenCalled();
  });

  it.each([
    [
      'rejects self-delete',
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      'admin-1',
      null,
      'Không thể tự xóa tài khoản đang đăng nhập',
    ],
    [
      'rejects an active account',
      { id: 'admin-1', role: 'SUPER_ADMIN' },
      'user-1',
      { id: 'user-1', email: 'staff@phongvu.vn', role: 'USER', status: 'yes' },
      'Chỉ xóa được tài khoản đã khóa',
    ],
    [
      'protects a super-admin target',
      { id: 'admin-1', role: 'ADMIN' },
      'root',
      {
        id: 'root',
        email: 'root@phongvu.vn',
        role: 'SUPER_ADMIN',
        status: 'no',
      },
      'Không thể xóa tài khoản quản trị toàn hệ thống',
    ],
  ])(
    '%s with the current Vietnamese error',
    async (_name, admin, userId, current, message) => {
      const { service, prisma, runtime } = createHarness();
      if (current) prisma.user.findUnique.mockResolvedValue(current);

      await expect(
        service.adminDeleteUser(admin, userId as string),
      ).rejects.toEqual(new BadRequestException(message));

      if (_name === 'rejects self-delete') {
        expect(prisma.user.findUnique).not.toHaveBeenCalled();
      }
      expect(runtime.userDeleteBlockers).not.toHaveBeenCalled();
      expect(prisma.$transaction).not.toHaveBeenCalled();
    },
  );

  it('rejects a delete when historical blockers are present and does not transact', async () => {
    const { service, prisma, runtime } = createHarness();
    const current = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      role: 'USER',
      status: 'no',
    };
    prisma.user.findUnique.mockResolvedValue(current);
    (runtime.userDeleteBlockers as jest.Mock).mockResolvedValue([
      'orders',
      'statements',
    ]);

    await expect(
      service.adminDeleteUser({ id: 'admin-1', role: 'SUPER_ADMIN' }, 'user-1'),
    ).rejects.toEqual(
      new BadRequestException(
        'Tài khoản đang có dữ liệu lịch sử, không thể xóa hoàn toàn: orders, statements',
      ),
    );

    expect(runtime.logger.warn).toHaveBeenCalledWith(
      'Admin user delete blocked: admin=user:admin-1 targetUserId=user-1 blockers=orders,statements',
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('deletes dependent records in one transaction and publishes access change after commit', async () => {
    const { service, prisma, accessChangeService, runtime } = createHarness();
    const current = {
      id: 'user-1',
      email: 'staff@phongvu.vn',
      role: 'USER',
      status: 'no',
    };
    prisma.user.findUnique.mockResolvedValue(current);
    const tx = {
      userPlatformSession: { deleteMany: jest.fn() },
      passwordResetToken: { deleteMany: jest.fn() },
      emailVerificationCode: { deleteMany: jest.fn() },
      adminPolicyRule: { deleteMany: jest.fn() },
      featureAccessRule: { deleteMany: jest.fn() },
      userFeatureAssignment: { deleteMany: jest.fn() },
      user: { delete: jest.fn() },
    };
    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      service.adminDeleteUser({ id: 'admin-1', role: 'SUPER_ADMIN' }, 'user-1'),
    ).resolves.toEqual({
      deleted: true,
      id: 'user-1',
      email: 'staff@phongvu.vn',
    });

    expect(tx.userPlatformSession.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
    });
    expect(tx.passwordResetToken.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
    });
    expect(tx.emailVerificationCode.deleteMany).toHaveBeenCalledWith({
      where: { email: 'staff@phongvu.vn' },
    });
    expect(tx.adminPolicyRule.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
    });
    expect(tx.featureAccessRule.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
    });
    expect(tx.userFeatureAssignment.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
    });
    expect(tx.user.delete).toHaveBeenCalledWith({ where: { id: 'user-1' } });
    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      ['user-1'],
      'user-access-deleted',
    );
    expect(
      accessChangeService.publishForUserIds.mock.invocationCallOrder[0],
    ).toBeGreaterThan(prisma.$transaction.mock.invocationCallOrder[0]);
    expect(runtime.logger.warn).toHaveBeenCalledWith(
      'Admin user deleted: admin=user:admin-1 targetUserId=user-1',
    );
  });
});
