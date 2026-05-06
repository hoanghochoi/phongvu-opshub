import { AuthController } from './auth.controller';

describe('AuthController', () => {
  let controller: AuthController;
  let authService: {
    googleLogin: jest.Mock;
    getUserData: jest.Mock;
  };

  beforeEach(() => {
    authService = {
      googleLogin: jest.fn(),
      getUserData: jest.fn(),
    };
    controller = new AuthController(authService as any);
  });

  it('delegates Google login with the submitted ID token', async () => {
    authService.googleLogin.mockResolvedValue({ access_token: 'jwt' });

    await expect(
      controller.googleLogin({ idToken: 'google-token' }),
    ).resolves.toEqual({
      access_token: 'jwt',
    });
    expect(authService.googleLogin).toHaveBeenCalledWith('google-token');
  });

  it('loads the current JWT user by email', async () => {
    authService.getUserData.mockResolvedValue({ firstName: 'An' });

    await expect(
      controller.getMe({ user: { email: 'staff@phongvu.vn' } }),
    ).resolves.toEqual({
      firstName: 'An',
    });
    expect(authService.getUserData).toHaveBeenCalledWith('staff@phongvu.vn');
  });

  it('ignores body email and loads the JWT user for get-user', async () => {
    authService.getUserData.mockResolvedValue({ firstName: 'An' });

    await expect(
      controller.getUserData({ user: { email: 'staff@phongvu.vn' } }),
    ).resolves.toEqual({
      firstName: 'An',
    });
    expect(authService.getUserData).toHaveBeenCalledWith('staff@phongvu.vn');
  });
});
