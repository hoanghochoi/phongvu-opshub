import { AuthController } from './auth.controller';

describe('AuthController', () => {
  let controller: AuthController;
  let authService: {
    passwordLogin: jest.Mock;
    register: jest.Mock;
    sendRegistrationVerificationCode: jest.Mock;
    forgotPassword: jest.Mock;
    verifyForgotPasswordCode: jest.Mock;
    resetPassword: jest.Mock;
    changePassword: jest.Mock;
    logout: jest.Mock;
    getUserData: jest.Mock;
  };
  let realtimeTicketService: {
    issueTicket: jest.Mock;
  };

  const loginDevice = {
    platform: 'windows',
    deviceId: 'device-123456',
  };

  beforeEach(() => {
    authService = {
      passwordLogin: jest.fn(),
      register: jest.fn(),
      sendRegistrationVerificationCode: jest.fn(),
      forgotPassword: jest.fn(),
      verifyForgotPasswordCode: jest.fn(),
      resetPassword: jest.fn(),
      changePassword: jest.fn(),
      logout: jest.fn(),
      getUserData: jest.fn(),
    };
    realtimeTicketService = {
      issueTicket: jest.fn(),
    };
    controller = new AuthController(
      authService as any,
      realtimeTicketService as any,
    );
  });

  it('delegates password login with submitted credentials', async () => {
    authService.passwordLogin.mockResolvedValue({ access_token: 'jwt' });

    await expect(
      controller.login({
        email: 'staff@phongvu-shop.vn',
        password: 'Password1!',
        ...loginDevice,
      }),
    ).resolves.toEqual({
      access_token: 'jwt',
    });
    expect(authService.passwordLogin).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
      'Password1!',
      expect.objectContaining(loginDevice),
    );
  });

  it('delegates registration with submitted profile data', async () => {
    authService.register.mockResolvedValue({ access_token: 'jwt' });

    await expect(
      controller.register({
        email: 'staff@phongvu-shop.vn',
        firstName: 'An',
        lastName: 'Nguyen',
        password: 'Password1!',
        verificationCode: '123456',
        ...loginDevice,
      }),
    ).resolves.toEqual({
      access_token: 'jwt',
    });
    expect(authService.register).toHaveBeenCalledWith({
      email: 'staff@phongvu-shop.vn',
      firstName: 'An',
      lastName: 'Nguyen',
      password: 'Password1!',
      verificationCode: '123456',
      ...loginDevice,
    });
  });

  it('delegates registration verification code sending', async () => {
    authService.sendRegistrationVerificationCode.mockResolvedValue({
      ok: true,
    });

    await expect(
      controller.sendVerificationCode({ email: 'staff@phongvu-shop.vn' }),
    ).resolves.toEqual({ ok: true });
    expect(authService.sendRegistrationVerificationCode).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
    );
  });

  it('delegates forgot password requests', async () => {
    authService.forgotPassword.mockResolvedValue({ ok: true });

    await expect(
      controller.forgotPassword({ email: 'staff@phongvu-shop.vn' }),
    ).resolves.toEqual({ ok: true });
    expect(authService.forgotPassword).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
    );
  });

  it('delegates forgot password code verification', async () => {
    authService.verifyForgotPasswordCode.mockResolvedValue({
      ok: true,
      resetToken: 'reset-token',
      expiresInMinutes: 10,
    });

    await expect(
      controller.verifyForgotPasswordCode({
        email: 'staff@phongvu-shop.vn',
        code: '123456',
      }),
    ).resolves.toEqual({
      ok: true,
      resetToken: 'reset-token',
      expiresInMinutes: 10,
    });
    expect(authService.verifyForgotPasswordCode).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
      '123456',
    );
  });

  it('delegates reset password submissions', async () => {
    authService.resetPassword.mockResolvedValue({ ok: true });

    await expect(
      controller.resetPassword({
        token: 'token-token-token-token',
        newPassword: 'Password2!',
      }),
    ).resolves.toEqual({ ok: true });
    expect(authService.resetPassword).toHaveBeenCalledWith(
      'token-token-token-token',
      'Password2!',
    );
  });

  it('delegates authenticated password changes', async () => {
    authService.changePassword.mockResolvedValue({ access_token: 'new-jwt' });

    await expect(
      controller.changePassword(
        { user: { id: 'user-1', authSession: { sessionId: 'session-1' } } },
        { currentPassword: 'Password1!', newPassword: 'Password2!' },
      ),
    ).resolves.toEqual({ access_token: 'new-jwt' });
    expect(authService.changePassword).toHaveBeenCalledWith(
      'user-1',
      'Password1!',
      'Password2!',
      { sessionId: 'session-1' },
    );
  });

  it('delegates logout for the current platform session', async () => {
    authService.logout.mockResolvedValue({ ok: true });

    await expect(
      controller.logout({
        user: { id: 'user-1', authSession: { sessionId: 'session-1' } },
      }),
    ).resolves.toEqual({ ok: true });
    expect(authService.logout).toHaveBeenCalledWith({
      id: 'user-1',
      authSession: { sessionId: 'session-1' },
    });
  });

  it('issues a realtime ticket for the authenticated session and requested store', async () => {
    realtimeTicketService.issueTicket.mockResolvedValue({
      ticket: 'one-time-ticket',
      expiresInSeconds: 45,
    });
    const user = {
      id: 'user-1',
      authSession: { sessionId: 'session-1' },
    };

    await expect(
      controller.issueRealtimeTicket({ user }, { storeCode: 'CP01' }),
    ).resolves.toEqual({
      ticket: 'one-time-ticket',
      expiresInSeconds: 45,
    });
    expect(realtimeTicketService.issueTicket).toHaveBeenCalledWith(
      user,
      'CP01',
    );
  });

  it('loads the current JWT user by email', async () => {
    authService.getUserData.mockResolvedValue({ firstName: 'An' });

    await expect(
      controller.getMe({ user: { email: 'staff@phongvu-shop.vn' } }),
    ).resolves.toEqual({
      firstName: 'An',
    });
    expect(authService.getUserData).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
    );
  });

  it('ignores body email and loads the JWT user for get-user', async () => {
    authService.getUserData.mockResolvedValue({ firstName: 'An' });

    await expect(
      controller.getUserData({ user: { email: 'staff@phongvu-shop.vn' } }, {}),
    ).resolves.toEqual({
      firstName: 'An',
    });
    expect(authService.getUserData).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
    );
  });
});
