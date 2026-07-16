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
    registrationCodeResponse: jest.Mock;
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
  let policyService: { getAllowedEmailDomains: jest.Mock };
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
      registrationCodeResponse: jest.fn().mockReturnValue({
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
    policyService = {
      getAllowedEmailDomains: jest.fn(async (fallback: string[]) => [
        ...fallback,
        'phongvu-shop.vn',
      ]),
    };
    service = new AuthService(
      prisma as any,
      jwtService as any,
      emailVerificationService as any,
      passwordResetService as any,
      authSessionService as any,
      policyService as any,
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
      role: 'USER',
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
      role: 'USER',
      organizationNodeId: null,
      assignmentPending: true,
      mustSelectStore: false,
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
      organizationNodeId: null,
      assignmentPending: true,
      mustSelectStore: false,
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

  it('accepts the ACareTek staff email domain', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.sendRegistrationVerificationCode(' Staff@acare.vn '),
    ).resolves.toEqual({
      ok: true,
      expiresInMinutes: 10,
    });
    expect(emailVerificationService.sendRegistrationCode).toHaveBeenCalledWith(
      'staff@acare.vn',
    );
  });

  it('does not bypass the organization domain policy for a special email', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.sendRegistrationVerificationCode(' admin@outside.example '),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(policyService.getAllowedEmailDomains).toHaveBeenCalled();
    expect(
      emailVerificationService.sendRegistrationCode,
    ).not.toHaveBeenCalled();
  });

  it('returns the same public response without sending a code for a registered account', async () => {
    prisma.user.findUnique.mockResolvedValue({ password: 'existing-hash' });

    await expect(
      service.sendRegistrationVerificationCode('staff@phongvu-shop.vn'),
    ).resolves.toEqual({ ok: true, expiresInMinutes: 10 });
    expect(
      emailVerificationService.registrationCodeResponse,
    ).toHaveBeenCalled();
    expect(
      emailVerificationService.sendRegistrationCode,
    ).not.toHaveBeenCalled();
  });

  it('rejects login when the account is not registered yet', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.passwordLogin('staff@phongvu-shop.vn', 'Password1!', loginDevice),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        message: 'Email hoặc mật khẩu không đúng',
      }),
    });
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
      assignedStores: [
        expect.objectContaining({ storeId: 'CP01', storeName: 'Chi nhanh 1' }),
      ],
      role: 'ADMIN',
    });
    expect(jwtService.sign).toHaveBeenCalledWith({
      email: 'staff@phongvu-shop.vn',
      sub: 'user-1',
      role: 'ADMIN',
      storeUuid: 'store-1',
      storeCode: 'CP01',
      departmentCode: null,
      organizationNodeId: null,
      organizationAccessCodes: [],
      tokenVersion: 0,
      accessVersion: 0,
      sessionId: 'session-1',
      platform: 'windows',
      sessionVersion: 1,
    });
    expect(authSessionService.replacePlatformSession).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'user-1' }),
      loginDevice,
    );
  });

  it('allows password login for AUTH_ALLOWED_EMAIL_DOMAINS entries', async () => {
    (policyService.getAllowedEmailDomains as jest.Mock).mockResolvedValueOnce([
      'allowed.example.test',
    ]);
    const testLoginSecret = 'unit-test-login-secret';
    const password = await bcrypt.hash(testLoginSecret, 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-mna',
      email: 'staff.member@allowed.example.test',
      firstName: 'Hoang',
      password,
      role: 'USER',
      status: 'yes',
      storeId: null,
      store: null,
      organizationNodeId: null,
      organizationNode: null,
    });

    await expect(
      service.passwordLogin(
        'staff.member@allowed.example.test',
        testLoginSecret,
        loginDevice,
      ),
    ).resolves.toMatchObject({
      login: true,
      email: 'staff.member@allowed.example.test',
      assignmentPending: true,
    });
  });

  it('normalizes legacy ADMIN role to ADMIN in login response and token', async () => {
    const password = await bcrypt.hash('Password1!', 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-legacy-admin',
      email: 'legacy@phongvu-shop.vn',
      firstName: 'Legacy',
      password,
      role: 'ADMIN',
      status: 'yes',
      storeId: null,
      store: null,
    });

    await expect(
      service.passwordLogin(
        'legacy@phongvu-shop.vn',
        'Password1!',
        loginDevice,
      ),
    ).resolves.toMatchObject({
      role: 'ADMIN',
      workScopeType: 'NATIONAL',
    });
    expect(jwtService.sign).toHaveBeenCalledWith(
      expect.objectContaining({ role: 'ADMIN' }),
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
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        message: 'Email hoặc mật khẩu không đúng',
      }),
    });
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

  it('returns every active assigned store from org-tree assignments', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-12',
      email: 'staging.user0012@phongvu.vn',
      storeId: 'store-75',
      firstName: 'Staging',
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'MANAGEMENT',
      jobRoleCode: 'STORE_MANAGER',
      workScopeType: 'STORE',
      organizationNodeId: 'node-cp75',
      organizationNode: { id: 'node-cp75', displayName: 'Quản lý CP75' },
      store: { id: 'store-75', storeId: 'CP75', storeName: 'CP75' },
      organizationAssignments: [
        {
          id: 'assignment-75',
          organizationNodeId: 'node-cp75',
          isPrimary: true,
          isActive: true,
          organizationNode: {
            id: 'node-cp75',
            displayName: 'Quản lý CP75',
            type: 'POSITION',
            stores: [{ id: 'store-75', storeId: 'CP75', storeName: 'CP75' }],
          },
        },
        {
          id: 'assignment-62',
          organizationNodeId: 'node-cp62',
          isPrimary: false,
          isActive: true,
          organizationNode: {
            id: 'node-cp62',
            displayName: 'Quản lý CP62',
            type: 'POSITION',
            stores: [{ id: 'store-62', storeId: 'CP62', storeName: 'CP62' }],
          },
        },
      ],
    });

    const profile = await service.getUserData('staging.user0012@phongvu.vn');

    expect(profile.storeId).toBe('CP75');
    expect(profile.organizationNodeIds).toEqual(['node-cp75', 'node-cp62']);
    expect(profile.assignedStores.map((store: any) => store.storeId)).toEqual([
      'CP75',
      'CP62',
    ]);
    expect(profile.organizationAssignments).toEqual([
      expect.objectContaining({
        organizationNodeId: 'node-cp75',
        storeId: 'CP75',
        isPrimary: true,
      }),
      expect.objectContaining({
        organizationNodeId: 'node-cp62',
        storeId: 'CP62',
        isPrimary: false,
      }),
    ]);
  });

  it('returns descendant showroom stores for a region org-tree assignment', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-region',
      email: 'region.manager@phongvu.vn',
      storeId: null,
      firstName: 'Region',
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'MANAGEMENT',
      jobRoleCode: 'REGION_MANAGER',
      workScopeType: 'REGION',
      organizationNodeId: 'node-region-hcm',
      organizationNode: { id: 'node-region-hcm', displayName: 'Miền Nam' },
      store: null,
      organizationAssignments: [
        {
          id: 'assignment-region',
          organizationNodeId: 'node-region-hcm',
          isPrimary: true,
          isActive: true,
          organizationNode: {
            id: 'node-region-hcm',
            displayName: 'Miền Nam',
            type: 'REGION',
            stores: [],
            children: [
              {
                id: 'node-cp75',
                displayName: 'CP75',
                type: 'STORE',
                stores: [
                  { id: 'store-75', storeId: 'CP75', storeName: 'CP75' },
                ],
                children: [],
              },
              {
                id: 'node-cp62',
                displayName: 'CP62',
                type: 'STORE',
                stores: [
                  { id: 'store-62', storeId: 'CP62', storeName: 'CP62' },
                ],
                children: [],
              },
            ],
          },
        },
      ],
    });

    const profile = await service.getUserData('region.manager@phongvu.vn');

    expect(profile.assignedStores.map((store: any) => store.storeId)).toEqual([
      'CP75',
      'CP62',
    ]);
    expect(profile.storeId).toBe('CP75');
    expect(profile.organizationAssignments).toEqual([
      expect.objectContaining({
        organizationNodeId: 'node-region-hcm',
        organizationNodeType: 'REGION',
        storeId: 'CP75',
        isPrimary: true,
      }),
    ]);
  });

  it('returns organization access codes from the assigned org-tree ancestors', async () => {
    (prisma as any).organizationNode = {
      findMany: jest.fn().mockResolvedValue([
        {
          id: 'root-finance',
          parentId: null,
          code: 'ORG_FIN',
          businessCode: 'FIN_ACC',
        },
        {
          id: 'lv5-acc',
          parentId: 'root-finance',
          code: 'POS_ACC',
          businessCode: 'ACC',
        },
      ]),
    };
    prisma.user.findUnique.mockResolvedValue({
      storeId: null,
      firstName: 'Accountant',
      role: 'STAFF',
      status: 'yes',
      departmentCode: null,
      organizationNodeId: 'lv5-acc',
      organizationNode: { displayName: 'ACC' },
      store: null,
    });

    await expect(
      service.getUserData('acc@phongvu-shop.vn'),
    ).resolves.toMatchObject({
      organizationNodeId: 'lv5-acc',
      organizationAccessCodes: ['POS_ACC', 'ACC', 'ORG_FIN', 'FIN_ACC'],
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

  it('uses region scope when deciding branch selection and personnel code', async () => {
    prisma.user.findUnique.mockResolvedValue({
      storeId: null,
      firstName: 'Sale',
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'SALES',
      jobRoleCode: 'CHATSALE',
      workScopeType: 'REGION',
      regionCode: 'CHATSALE',
      region: {
        code: 'CHATSALE',
        displayName: 'Chatsale',
        abbreviation: 'CHATSALE',
      },
      store: null,
    });

    await expect(
      service.getUserData('online@phongvu-shop.vn'),
    ).resolves.toMatchObject({
      jobRoleCode: 'CHATSALE',
      workScopeType: 'REGION',
      regionCode: 'CHATSALE',
      personnelCode: 'CHATSALE_CHATSALE_CHATSALE_CHATSALE',
      assignmentPending: true,
      mustSelectStore: false,
    });
  });

  it('derives STORE-scope profile area and region from the assigned SR', async () => {
    prisma.user.findUnique.mockResolvedValue({
      storeId: 'store-62',
      firstName: 'Sale',
      role: 'STAFF',
      status: 'yes',
      departmentCode: 'SALES',
      jobRoleCode: 'SALE',
      workScopeType: 'STORE',
      areaCode: 'VUNG_CU',
      regionCode: 'MIEN_CU',
      area: {
        code: 'VUNG_CU',
        displayName: 'Vung cu',
        abbreviation: 'VC',
        region: { code: 'MIEN_CU', displayName: 'Mien cu', abbreviation: 'MC' },
      },
      region: { code: 'MIEN_CU', displayName: 'Mien cu', abbreviation: 'MC' },
      store: {
        storeId: 'CP62',
        storeName: 'CP62',
        area: {
          code: 'HCM',
          displayName: 'Ho Chi Minh',
          abbreviation: 'HCM',
          region: {
            code: 'MIEN_NAM',
            displayName: 'Mien Nam',
            abbreviation: 'MN',
          },
        },
      },
    });

    await expect(service.getUserData('sale@phongvu.vn')).resolves.toMatchObject(
      {
        workScopeType: 'STORE',
        areaCode: 'HCM',
        regionCode: 'MIEN_NAM',
        personnelCode: 'SALE_CP62_HCM_MN',
      },
    );
  });

  it('throws when user profile is missing', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(
      service.getUserData('missing@phongvu-shop.vn'),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
