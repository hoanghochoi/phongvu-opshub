import { UnauthorizedException } from '@nestjs/common';
import { JwtStrategy } from './jwt.strategy';

describe('JwtStrategy', () => {
  let strategy: JwtStrategy;
  let prisma: any;
  let authSessionService: { validateJwtSession: jest.Mock };

  beforeEach(() => {
    process.env.JWT_SECRET = 'test-secret';
    prisma = {
      user: {
        findUnique: jest.fn(),
      },
    };
    authSessionService = {
      validateJwtSession: jest.fn().mockResolvedValue({
        sessionId: 'session-1',
        platform: 'windows',
        sessionVersion: 1,
      }),
    };
    strategy = new JwtStrategy(prisma, authSessionService as any);
  });

  it('returns the user with validated auth session claims', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      email: 'staff@phongvu.vn',
      role: 'STAFF',
      status: 'yes',
      tokenVersion: 2,
    });

    await expect(
      strategy.validate({
        sub: 'user-1',
        tokenVersion: 2,
        sessionId: 'session-1',
        platform: 'windows',
        sessionVersion: 1,
      }),
    ).resolves.toMatchObject({
      id: 'user-1',
      authSession: {
        sessionId: 'session-1',
        platform: 'windows',
        sessionVersion: 1,
      },
    });
    expect(authSessionService.validateJwtSession).toHaveBeenCalledWith(
      'user-1',
      expect.objectContaining({ sessionId: 'session-1' }),
    );
  });

  it('rejects locked users on every protected API request', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      status: 'no',
      tokenVersion: 0,
    });

    await expect(
      strategy.validate({ sub: 'user-1', tokenVersion: 0 }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(authSessionService.validateJwtSession).not.toHaveBeenCalled();
  });

  it('rejects stale token versions before checking session rows', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      status: 'yes',
      tokenVersion: 3,
    });

    await expect(
      strategy.validate({ sub: 'user-1', tokenVersion: 2 }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(authSessionService.validateJwtSession).not.toHaveBeenCalled();
  });
});
