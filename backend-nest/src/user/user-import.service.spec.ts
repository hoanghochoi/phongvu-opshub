import {
  UserImportService,
  UserWelcomeEmailService,
  type UserImportLogger,
  type UserImportRuntime,
} from './user-import.service';

describe('UserWelcomeEmailService', () => {
  const runtime = (): {
    logger: UserImportLogger & { log: jest.Mock; error: jest.Mock };
    normalizeAccountEmail: jest.Mock;
    userLogId: jest.Mock;
  } => ({
    normalizeAccountEmail: jest.fn((value) =>
      String(value).trim().toLowerCase(),
    ),
    userLogId: jest.fn(() => 'user-id:admin'),
    logger: {
      log: jest.fn(),
      error: jest.fn(),
    },
  });

  it('sends a normalized welcome email and records the import row context', async () => {
    const mailService = { sendMail: jest.fn().mockResolvedValue(undefined) };
    const hooks = runtime();
    const service = new UserWelcomeEmailService(mailService as any, hooks);

    const result = await service.sendWelcomeEmail(
      { email: '  NEW@PHONGVU.VN ', firstName: 'Nguyễn Văn A' },
      { source: 'admin-import', admin: { id: 'admin' }, rowNumber: 4 },
    );

    expect(result).toEqual({ sent: true, error: null });
    expect(mailService.sendMail).toHaveBeenCalledWith(
      expect.objectContaining({
        to: 'new@phongvu.vn',
        subject: 'Chào mừng bạn đến với PhongVu OpsHub',
      }),
    );
    expect(hooks.logger.log).toHaveBeenCalledWith(
      expect.stringContaining('source=admin-import'),
    );
    expect(hooks.logger.log).toHaveBeenCalledWith(
      expect.stringContaining('row=4'),
    );
  });

  it('reports a missing mail service without throwing', async () => {
    const hooks = runtime();
    const service = new UserWelcomeEmailService(undefined, hooks);

    await expect(
      service.sendWelcomeEmail(
        { email: 'staff@phongvu.vn' },
        { source: 'admin-create', admin: { id: 'admin' } },
      ),
    ).resolves.toEqual({
      sent: false,
      error: 'Chưa cấu hình dịch vụ gửi email PhongVu OpsHub.',
    });
    expect(hooks.logger.error).toHaveBeenCalledWith(
      expect.stringContaining('reason=missing_mail_service'),
    );
  });
});

describe('UserImportService', () => {
  function createRuntime(): UserImportRuntime {
    return {
      assertAdmin: jest.fn().mockResolvedValue(undefined),
      assertSuperAdminCanCreateUsers: jest.fn().mockResolvedValue(undefined),
      seedDefaultOrganizationTree: jest.fn().mockResolvedValue(undefined),
      syncStoreOrganizationNodes: jest.fn().mockResolvedValue(undefined),
      prepareAdminUserMutation: jest.fn().mockResolvedValue({
        email: 'new@phongvu.vn',
        role: 'USER',
        workScopeType: 'STORE',
        personnel: { organizationNodeId: 'node-1' },
        organizationNodeIds: ['node-1'],
        createData: { email: 'new@phongvu.vn', password: '' },
        updateData: {},
      }),
      assertAccountEmailAllowed: jest.fn().mockResolvedValue('new@phongvu.vn'),
      assertAdminCanUpdateUser: jest.fn().mockResolvedValue(undefined),
      assertOrganizationNodeAssignableByAdmin: jest
        .fn()
        .mockResolvedValue(undefined),
      organizationNodeLevel: jest.fn(() => 0),
      normalizeStoreCode: jest.fn((value) => value.toUpperCase()),
      syncUserOrganizationAssignments: jest.fn().mockResolvedValue(undefined),
      userDtoInclude: jest.fn(() => ({})),
      personnelCodeFor: jest.fn(() => 'SA_CP01'),
      userLogId: jest.fn(() => 'user-id:admin'),
      logger: {
        log: jest.fn(),
        error: jest.fn(),
      },
    };
  }

  it('keeps import orchestration behind explicit runtime callbacks', async () => {
    const runtime = createRuntime();
    const savedUser = {
      id: 'user-1',
      email: 'new@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'node-1',
      organizationNode: { displayName: 'Store 1' },
    };
    const create = jest.fn().mockResolvedValue(savedUser);
    const update = jest.fn();
    const prisma = {
      user: {
        findMany: jest
          .fn()
          .mockResolvedValueOnce([])
          .mockResolvedValueOnce([savedUser]),
      },
      organizationNode: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'node-1',
            parentId: null,
            type: 'LV0_DOMAIN',
            code: 'ROOT',
            businessCode: null,
            displayName: 'Root',
            isActive: true,
          },
        ]),
      },
      store: { findMany: jest.fn().mockResolvedValue([]) },
      $transaction: jest.fn(async (callback) =>
        callback({ user: { create, update } }),
      ),
    };
    const accessChangeService = {
      publishForUserIds: jest.fn().mockResolvedValue(undefined),
    };
    const welcomeEmailService = {
      sendWelcomeEmailsForImport: jest.fn().mockResolvedValue({
        sentEmails: new Set(['new@phongvu.vn']),
        failedByEmail: new Map(),
        sentRows: 1,
        failedRows: 0,
      }),
    };

    const service = new UserImportService(
      prisma as any,
      accessChangeService as any,
      welcomeEmailService as any,
      runtime,
    );

    const result = await service.adminImportUsers(
      { id: 'admin', role: 'SUPER_ADMIN' },
      {
        totalRows: 1,
        skippedRows: 0,
        rows: [
          {
            rowNumber: 2,
            email: 'new@phongvu.vn',
            fullName: 'Nguyễn Văn A',
            role: 'USER',
            levelCodes: ['ROOT', '', '', '', '', ''],
            storeIds: [],
          },
        ],
      },
    );

    expect(result).toMatchObject({
      totalRows: 1,
      createdRows: 1,
      updatedRows: 0,
      welcomeEmailSentRows: 1,
      welcomeEmailFailedRows: 0,
    });
    expect(create).toHaveBeenCalledTimes(1);
    expect(update).not.toHaveBeenCalled();
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenCalledWith(
      'user-1',
      ['node-1'],
      { id: 'admin', role: 'SUPER_ADMIN' },
    );
    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      [],
      'user-access-import-updated',
    );
    expect(welcomeEmailService.sendWelcomeEmailsForImport).toHaveBeenCalled();
  });

  it('stops before touching persistence when admin authorization fails', async () => {
    const runtime = createRuntime();
    const authorizationError = new Error('forbidden');
    (runtime.assertAdmin as jest.Mock).mockRejectedValueOnce(
      authorizationError,
    );
    const prisma = {
      user: { findMany: jest.fn() },
      organizationNode: { findMany: jest.fn() },
      store: { findMany: jest.fn() },
      $transaction: jest.fn(),
    };
    const service = new UserImportService(
      prisma as any,
      { publishForUserIds: jest.fn() } as any,
      { sendWelcomeEmailsForImport: jest.fn() } as any,
      runtime,
    );

    await expect(
      service.adminImportUsers(
        { id: 'admin', role: 'ADMIN' },
        { totalRows: 0, skippedRows: 0, rows: [] },
      ),
    ).rejects.toBe(authorizationError);
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.user.findMany).not.toHaveBeenCalled();
  });
});
