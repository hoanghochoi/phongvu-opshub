import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { UserCredentialAdminService } from './user-credential-admin.service';

describe('UserCredentialAdminService', () => {
  function createHarness() {
    const prisma = {
      user: {
        findUnique: jest.fn(),
      },
    };
    const passwordResetService = {
      setPasswordForUserId: jest.fn().mockResolvedValue({ ok: true }),
    };
    const callbacks = {
      assertAdmin: jest.fn().mockResolvedValue(undefined),
      userDtoInclude: jest.fn().mockReturnValue({ store: true }),
      normalizeRoleCode: jest.fn((role: string) =>
        role === 'ADMIN_PHONGVU' || role === 'MANAGER' ? 'ADMIN' : role,
      ),
      isDomainAdmin: jest.fn((admin: any) => admin.role === 'ADMIN_PHONGVU'),
      userWithinAdminScope: jest.fn().mockResolvedValue(true),
      userLogId: jest.fn().mockReturnValue('userId:admin-1'),
      logger: { log: jest.fn() },
    };
    const service = new UserCredentialAdminService(
      prisma as any,
      passwordResetService as any,
      callbacks as any,
    );
    return { prisma, passwordResetService, callbacks, service };
  }

  const target = {
    id: 'user-1',
    role: 'STAFF',
    email: 'staff@phongvu.vn',
  };

  it('resets a scoped user password and preserves the actor boundary', async () => {
    const { service, prisma, passwordResetService, callbacks } =
      createHarness();
    prisma.user.findUnique.mockResolvedValue(target);
    const admin = {
      id: 'admin-1',
      email: 'admin@phongvu.vn',
      role: 'ADMIN_PHONGVU',
    };

    await expect(
      service.adminSetUserPassword(admin, 'user-1', 'Password2!'),
    ).resolves.toEqual({ ok: true });

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { id: 'user-1' },
      include: { store: true },
    });
    expect(passwordResetService.setPasswordForUserId).toHaveBeenCalledWith(
      'user-1',
      'Password2!',
      { id: 'admin-1', email: 'admin@phongvu.vn' },
    );
    expect(callbacks.userWithinAdminScope).toHaveBeenCalledWith(admin, target);
    expect(callbacks.logger.log.mock.calls.flat().join(' ')).not.toContain(
      'Password2!',
    );
  });

  it('allows super admins to reset a super-admin target without scope lookup', async () => {
    const { service, prisma, callbacks } = createHarness();
    prisma.user.findUnique.mockResolvedValue({
      ...target,
      role: 'SUPER_ADMIN',
    });
    await expect(
      service.adminSetUserPassword(
        { id: 'root', email: 'root@phongvu.vn', role: 'SUPER_ADMIN' },
        'user-1',
        'Password2!',
      ),
    ).resolves.toEqual({ ok: true });
    expect(callbacks.userWithinAdminScope).not.toHaveBeenCalled();
  });

  it('rejects a non-domain admin before resetting a password', async () => {
    const { service, prisma, callbacks, passwordResetService } =
      createHarness();
    prisma.user.findUnique.mockResolvedValue(target);
    callbacks.isDomainAdmin.mockReturnValue(false);

    await expect(
      service.adminSetUserPassword(
        { id: 'manager', email: 'manager@phongvu.vn', role: 'MANAGER' },
        'user-1',
        'Password2!',
      ),
    ).rejects.toEqual(
      new ForbiddenException('Bạn không có quyền reset mật khẩu người dùng'),
    );
    expect(passwordResetService.setPasswordForUserId).not.toHaveBeenCalled();
  });

  it('rejects an out-of-scope target and a missing target with current errors', async () => {
    const outOfScope = createHarness();
    outOfScope.prisma.user.findUnique.mockResolvedValue(target);
    outOfScope.callbacks.userWithinAdminScope.mockResolvedValue(false);
    await expect(
      outOfScope.service.adminSetUserPassword(
        { id: 'admin-1', role: 'ADMIN_PHONGVU' },
        'user-1',
        'Password2!',
      ),
    ).rejects.toEqual(
      new ForbiddenException(
        'Bạn không có quyền reset mật khẩu người dùng ngoài phạm vi quản lý',
      ),
    );

    const missing = createHarness();
    missing.prisma.user.findUnique.mockResolvedValue(null);
    await expect(
      missing.service.adminSetUserPassword(
        { id: 'root', role: 'SUPER_ADMIN' },
        'missing',
        'Password2!',
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('protects a super-admin target from scoped admins', async () => {
    const { service, prisma, passwordResetService } = createHarness();
    prisma.user.findUnique.mockResolvedValue({
      ...target,
      role: 'SUPER_ADMIN',
    });
    await expect(
      service.adminSetUserPassword(
        { id: 'admin-1', role: 'ADMIN_PHONGVU' },
        'root',
        'Password2!',
      ),
    ).rejects.toEqual(
      new ForbiddenException(
        'Bạn không có quyền reset mật khẩu tài khoản quản trị toàn hệ thống',
      ),
    );
    expect(passwordResetService.setPasswordForUserId).not.toHaveBeenCalled();
  });
});
