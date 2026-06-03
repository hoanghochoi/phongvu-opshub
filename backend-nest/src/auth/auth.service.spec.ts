import * as bcrypt from 'bcrypt';
import {
  BadRequestException,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  let service: AuthService;
  let prisma: {
    user: {
      findUnique: jest.Mock;
      create: jest.Mock;
      update: jest.Mock;
    };
  };
  let jwtService: { sign: jest.Mock };
  let emailVerificationService: {
    consumeRegistrationCode: jest.Mock;
    sendRegistrationCode: jest.Mock;
  };
  let passwordResetService: {
    sendResetCodeForEmail: jest.Mock;
    verifyResetCode: jest.Mock;
    resetPassword: jest.Mock;
  };
  let authSessionService: {
    normalizeDevice: jest.Mock;
    replacePlatformSession: jest.Mock;
    revokeCurrentSession: jest.Mock;
  };
  const loginDevice = {
    platform: 'windows',
    deviceId: 'device-123456',
  };
  const authSession = {
    sessionId: 'session-1',
    platform: 'windows' as const,
    sessionVersion: 1,
  };

  beforeEach(() => {
    prisma = {
      user: {
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
    };
    jwtService = { sign: jest.fn().mockReturnValue('signed-jwt') };
    emailVerificationService = {
      consumeRegistrationCode: jest.fn().mockResolvedValue(undefined),
      sendRegistrationCode: jest.fn().mockResolvedValue({
        ok: true,
        expiresInMinutes: 10,
      }),
    };
    passwordResetService = {
      sendResetCodeForEmail: jest.fn().mockResolvedValue({
        ok: true,
        expiresInMinutes: 10,
      }),
      verifyResetCode: jest.fn().mockResolvedValue({
        ok: true,
        resetToken: 'reset-token',
        expiresInMinutes: 10,
      }),
      resetPassword: jest.fn().mockResolvedValue({ ok: true }),
    };
    authSessionService = {
      normalizeDevice: jest.fn((device) => device),
      replacePlatformSession: jest.fn().mockResolvedValue(authSession),
      revokeCurrentSession: jest.fn().mockResolvedValue({ ok: true }),
    };
    service = new AuthService(
      prisma as any,
      jwtService as any,
      emailVerificationService as any,
      passwordResetService as any,
      authSessionService as any,
    );
  });

  it('registers a new password account for an allowed Phong Vu email domain', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockImplementation(async ({ data }) => ({
      id: 'user-1',
      email: data.email,
      firstName: data.firstName,
      lastName: data.lastName,
      password: data.password,
      role: 'STAFF',
      status: 'yes',
      storeId: null,
      store: null,
    }));

    await expect(
      service.register({
        email: ' Staff@PhongVu-Shop.vn ',
        firstName: 'An',
        lastName: 'Nguyen',
        password: 'Password1!',
        verificationCode: '123456',
        ...loginDevice,
      }),
    ).resolves.toMatchObject({
      login: true,
      access_token: 'signed-jwt',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      lastName: 'Nguyen',
      role: 'STAFF',
    });

    expect(prisma.user.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          email: 'staff@phongvu-shop.vn',
          firstName: 'An',
          lastName: 'Nguyen',
          status: 'yes',
        }),
      }),
    );
    const savedPassword = prisma.user.create.mock.calls[0][0].data.password;
    await expect(bcrypt.compare('Password1!', savedPassword)).resolves.toBe(
      true,
    );
    expect(
      emailVerificationService.consumeRegistrationCode,
    ).toHaveBeenCalledWith('staff@phongvu-shop.vn', '123456');
  });

  it('sets a password for an imported user through registration', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'Old',
      password: '',
      role: 'STAFF',
      status: 'yes',
      storeId: null,
      store: null,
    });
    prisma.user.update.mockImplementation(async ({ data }) => ({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: data.firstName,
      lastName: data.lastName,
      password: data.password,
      role: 'STAFF',
      status: 'yes',
      storeId: null,
      store: null,
    }));

    await expect(
      service.register({
        email: 'staff@phongvu-shop.vn',
        firstName: 'An',
        password: 'Password1!',
        verificationCode: '123456',
        ...loginDevice,
      }),
    ).resolves.toMatchObject({
      login: true,
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
    });
    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'user-1' },
        data: expect.objectContaining({ password: expect.any(String) }),
      }),
    );
  });

  it('rejects registration for an email that already has a password', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      password: await bcrypt.hash('Password1!', 4),
      role: 'STAFF',
      status: 'yes',
      storeId: null,
      store: null,
    });

    await expect(
      service.register({
        email: 'staff@phongvu-shop.vn',
        firstName: 'An',
        password: 'Password1!',
        verificationCode: '123456',
        ...loginDevice,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('sends a registration verification code for a new account', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.sendRegistrationVerificationCode(' Staff@PhongVu-Shop.vn '),
    ).resolves.toEqual({
      ok: true,
      expiresInMinutes: 10,
    });
    expect(emailVerificationService.sendRegistrationCode).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
    );
  });

  it('rejects login when the account is not registered yet', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.passwordLogin('staff@phongvu-shop.vn', 'Password1!', loginDevice),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('issues a JWT for an existing user with a valid password', async () => {
    const password = await bcrypt.hash('Password1!', 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      password,
      role: 'ADMIN',
      status: 'yes',
      storeId: 'store-1',
      store: { storeId: 'CP01', storeName: 'Chi nhanh 1' },
    });

    await expect(
      service.passwordLogin('staff@phongvu-shop.vn', 'Password1!', loginDevice),
    ).resolves.toMatchObject({
      login: true,
      access_token: 'signed-jwt',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      storeId: 'CP01',
      role: 'ADMIN',
    });
    expect(jwtService.sign).toHaveBeenCalledWith({
      email: 'staff@phongvu-shop.vn',
      sub: 'user-1',
      role: 'ADMIN',
      storeUuid: 'store-1',
      storeCode: 'CP01',
      tokenVersion: 0,
      sessionId: 'session-1',
      platform: 'windows',
      sessionVersion: 1,
    });
    expect(authSessionService.replacePlatformSession).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'user-1' }),
      loginDevice,
    );
  });

  it('rejects users outside the allowed Phong Vu email domains', async () => {
    await expect(
      service.passwordLogin('staff@example.com', 'Password1!', loginDevice),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
  });

  it('rejects invalid passwords for existing users', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      password: await bcrypt.hash('Password1!', 4),
      role: 'STAFF',
      status: 'yes',
      storeId: null,
      store: null,
    });

    await expect(
      service.passwordLogin(
        'staff@phongvu-shop.vn',
        'WrongPassword1!',
        loginDevice,
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('changes password and issues a JWT with the next token version', async () => {
    const password = await bcrypt.hash('Password1!', 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      password,
      role: 'STAFF',
      status: 'yes',
      tokenVersion: 2,
      storeId: null,
      store: null,
    });
    prisma.user.update.mockImplementation(async ({ data }) => ({
      id: 'user-1',
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      password: data.password,
      role: 'STAFF',
      status: 'yes',
      tokenVersion: 3,
      storeId: null,
      store: null,
    }));

    await expect(
      service.changePassword('user-1', 'Password1!', 'Password2!', authSession),
    ).resolves.toMatchObject({
      login: true,
      access_token: 'signed-jwt',
      email: 'staff@phongvu-shop.vn',
    });
    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'user-1' },
        data: expect.objectContaining({
          password: expect.any(String),
          tokenVersion: { increment: 1 },
        }),
      }),
    );
    expect(jwtService.sign).toHaveBeenLastCalledWith(
      expect.objectContaining({
        tokenVersion: 3,
        sessionId: 'session-1',
        platform: 'windows',
        sessionVersion: 1,
      }),
    );
  });

  it('revokes the current platform session on logout', async () => {
    await expect(
      service.logout({ id: 'user-1', authSession }),
    ).resolves.toEqual({ ok: true });
    expect(authSessionService.revokeCurrentSession).toHaveBeenCalledWith(
      'user-1',
      authSession,
      'LOGOUT',
    );
  });

  it('delegates forgot password after normalizing and validating the email domain', async () => {
    await expect(
      service.forgotPassword(' Staff@PhongVu-Shop.vn '),
    ).resolves.toEqual({ ok: true, expiresInMinutes: 10 });
    expect(passwordResetService.sendResetCodeForEmail).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
    );
  });

  it('delegates forgot password code verification after normalizing the email', async () => {
    await expect(
      service.verifyForgotPasswordCode(' Staff@PhongVu-Shop.vn ', '123456'),
    ).resolves.toEqual({
      ok: true,
      resetToken: 'reset-token',
      expiresInMinutes: 10,
    });
    expect(passwordResetService.verifyResetCode).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
      '123456',
    );
  });

  it('delegates reset password token consumption', async () => {
    await expect(
      service.resetPassword('reset-token', 'Password2!'),
    ).resolves.toEqual({ ok: true });
    expect(passwordResetService.resetPassword).toHaveBeenCalledWith(
      'reset-token',
      'Password2!',
    );
  });

  it('returns app user profile data by email', async () => {
    prisma.user.findUnique.mockResolvedValue({
      storeId: 'store-1',
      firstName: 'An',
      role: 'ADMIN',
      store: { storeId: 'CP01', storeName: 'Chi nhanh 1' },
    });

    await expect(
      service.getUserData('staff@phongvu-shop.vn'),
    ).resolves.toMatchObject({
      name: 'An',
      firstName: 'An',
      storeId: 'CP01',
      storeName: 'Chi nhanh 1',
      role: 'ADMIN',
      mustSelectStore: false,
    });
  });

  it('does not force SUPER_ADMIN without store to select a branch', async () => {
    prisma.user.findUnique.mockResolvedValue({
      storeId: null,
      firstName: 'Admin',
      role: 'SUPER_ADMIN',
      status: 'yes',
      store: null,
    });

    await expect(
      service.getUserData('admin@phongvu-shop.vn'),
    ).resolves.toMatchObject({
      role: 'SUPER_ADMIN',
      storeId: null,
      mustSelectStore: false,
    });
  });

  it('uses work scope when deciding branch selection and personnel code', async () => {
    prisma.user.findUnique.mockResolvedValue({
      storeId: null,
      firstName: 'Sale',
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'SALES',
      jobRoleCode: 'SALE_ONLINE',
      workScopeType: 'ONLINE',
      store: null,
    });

    await expect(
      service.getUserData('online@phongvu-shop.vn'),
    ).resolves.toMatchObject({
      jobRoleCode: 'SALE_ONLINE',
      workScopeType: 'ONLINE',
      personnelCode: 'SALE_ONLINE',
      mustSelectStore: false,
    });
  });

  it('throws when user profile is missing', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.getUserData('missing@phongvu-shop.vn'),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
