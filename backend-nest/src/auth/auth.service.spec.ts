import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  let service: AuthService;
  let prisma: {
    user: {
      findUnique: jest.Mock;
      create: jest.Mock;
    };
  };
  let jwtService: { sign: jest.Mock };

  beforeEach(() => {
    process.env.ALLOWED_DOMAIN = 'phongvu.vn';
    prisma = {
      user: {
        findUnique: jest.fn(),
        create: jest.fn(),
      },
    };
    jwtService = { sign: jest.fn().mockReturnValue('signed-jwt') };
    service = new AuthService(prisma as any, jwtService as any);
    (service as any).googleClient = { verifyIdToken: jest.fn() };
  });

  afterEach(() => {
    delete process.env.ALLOWED_DOMAIN;
  });

  it('issues a JWT for an active Google user in the allowed domain', async () => {
    (service as any).googleClient.verifyIdToken.mockResolvedValue({
      getPayload: () => ({ email: 'staff@phongvu.vn', given_name: 'An' }),
    });
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu.vn',
      firstName: 'An',
      role: 'USER',
      status: 'yes',
      store: { storeId: 'CP01', storeName: 'Chi nhanh 1' },
    });

    await expect(service.googleLogin('google-token')).resolves.toMatchObject({
      login: true,
      access_token: 'signed-jwt',
      email: 'staff@phongvu.vn',
      firstName: 'An',
      storeId: 'CP01',
      role: 'USER',
    });
    expect(jwtService.sign).toHaveBeenCalledWith({
      email: 'staff@phongvu.vn',
      sub: 'user-1',
      role: 'USER',
    });
  });

  it('rejects Google users outside the allowed domain', async () => {
    (service as any).googleClient.verifyIdToken.mockResolvedValue({
      getPayload: () => ({ email: 'staff@example.com' }),
    });

    await expect(service.googleLogin('google-token')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
  });

  it('returns app user profile data by email', async () => {
    prisma.user.findUnique.mockResolvedValue({
      firstName: 'An',
      role: 'ADMIN',
      store: { storeId: 'CP01', storeName: 'Chi nhanh 1' },
    });

    await expect(service.getUserData('staff@phongvu.vn')).resolves.toEqual({
      name: 'An',
      firstName: 'An',
      storeId: 'CP01',
      storeName: 'Chi nhanh 1',
      role: 'ADMIN',
    });
  });

  it('throws when user profile is missing', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.getUserData('missing@phongvu.vn'),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
