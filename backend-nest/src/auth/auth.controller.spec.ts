import { AuthController } from './auth.controller';

describe('AuthController', () => {
  let controller: AuthController;
  let authService: {
    passwordLogin: jest.Mock;
    register: jest.Mock;
    sendRegistrationVerificationCode: jest.Mock;
    getUserData: jest.Mock;
  };

  beforeEach(() => {
    authService = {
      passwordLogin: jest.fn(),
      register: jest.fn(),
      sendRegistrationVerificationCode: jest.fn(),
      getUserData: jest.fn(),
    };
    controller = new AuthController(authService as any);
  });

  it('delegates password login with submitted credentials', async () => {
    authService.passwordLogin.mockResolvedValue({ access_token: 'jwt' });

    await expect(
      controller.login({
        email: 'staff@phongvu-shop.vn',
        password: 'Password1!',
      }),
    ).resolves.toEqual({
      access_token: 'jwt',
    });
    expect(authService.passwordLogin).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
      'Password1!',
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
    });
  });

  it('delegates registration verification code sending', async () => {
    authService.sendRegistrationVerificationCode.mockResolvedValue({
      ok: true,
    });

    await expect(
      controller.sendVerificationCode({ email: 'staff@phongvu-shop.vn' }),
    ).resolves.toEqual({
      ok: true,
    });
    expect(authService.sendRegistrationVerificationCode).toHaveBeenCalledWith(
      'staff@phongvu-shop.vn',
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
