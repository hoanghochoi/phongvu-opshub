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
    const tx = { user: { create, update } };
    let committed = false;
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
      $transaction: jest.fn(async (callback) => {
        const result = await callback(tx);
        committed = true;
        return result;
      }),
    };
    const accessChangeService = {
      publishForUserIds: jest.fn(async () => {
        expect(committed).toBe(true);
      }),
    };
    const welcomeEmailService = {
      sendWelcomeEmailsForImport: jest.fn(async () => {
        expect(committed).toBe(true);
        return {
          sentEmails: new Set(['new@phongvu.vn']),
          failedByEmail: new Map(),
          sentRows: 1,
          failedRows: 0,
        };
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
      tx,
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

  it('updates an existing user, synchronizes assignments and publishes access changes', async () => {
    const runtime = createRuntime();
    const currentUser = {
      id: 'user-existing',
      email: 'existing@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'node-1',
      organizationNode: { displayName: 'Root' },
    };
    const savedUser = {
      ...currentUser,
      role: 'ADMIN',
      firstName: 'Updated Name',
      organizationNodeId: 'node-2',
      organizationNode: { displayName: 'Branch 2' },
    };
    (runtime.prepareAdminUserMutation as jest.Mock).mockResolvedValueOnce({
      email: currentUser.email,
      role: 'ADMIN',
      workScopeType: 'BRANCH',
      personnel: { organizationNodeId: 'node-2' },
      organizationNodeIds: ['node-2'],
      createData: undefined,
      updateData: { firstName: 'Updated Name' },
    });
    const update = jest.fn().mockResolvedValue(savedUser);
    const tx = { user: { create: jest.fn(), update } };
    const prisma = {
      user: {
        findMany: jest
          .fn()
          .mockResolvedValueOnce([currentUser])
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
      $transaction: jest.fn(async (callback) => callback(tx)),
    };
    const accessChangeService = {
      publishForUserIds: jest.fn().mockResolvedValue(undefined),
    };
    const welcomeEmailService = {
      sendWelcomeEmailsForImport: jest.fn().mockResolvedValue({
        sentEmails: new Set(),
        failedByEmail: new Map(),
        sentRows: 0,
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
            rowNumber: 7,
            email: currentUser.email,
            fullName: 'Updated Name',
            role: 'ADMIN',
            levelCodes: ['ROOT', '', '', '', '', ''],
            storeIds: [],
          },
        ],
      },
    );

    expect(result).toMatchObject({
      totalRows: 1,
      createdRows: 0,
      updatedRows: 1,
      welcomeEmailSentRows: 0,
      welcomeEmailFailedRows: 0,
      results: [
        expect.objectContaining({
          rowNumber: 7,
          email: currentUser.email,
          action: 'updated',
          role: 'ADMIN',
          personnelCode: 'SA_CP01',
        }),
      ],
    });
    expect(update).toHaveBeenCalledWith({
      data: { firstName: 'Updated Name' },
      where: { id: currentUser.id },
    });
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenCalledWith(
      tx,
      currentUser.id,
      ['node-2'],
      { id: 'admin', role: 'SUPER_ADMIN' },
    );
    expect(accessChangeService.publishForUserIds).toHaveBeenCalledWith(
      [currentUser.id],
      'user-access-import-updated',
    );
    expect(welcomeEmailService.sendWelcomeEmailsForImport).toHaveBeenCalledWith(
      { id: 'admin', role: 'SUPER_ADMIN' },
      expect.arrayContaining([
        expect.objectContaining({ action: 'updated', userId: currentUser.id }),
      ]),
      expect.any(Map),
    );
  });

  it('resolves multiple store assignments and validates each assigned node', async () => {
    const runtime = createRuntime();
    (runtime.normalizeStoreCode as jest.Mock).mockImplementation((value) =>
      String(value).trim().toUpperCase(),
    );
    const createdUser = {
      id: 'user-multi-store',
      email: 'multi@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'node-store-1',
      organizationNode: { displayName: 'Store 1' },
    };
    const storeNodes = [
      {
        id: 'node-store-1',
        parentId: null,
        type: 'LV0_DOMAIN',
        code: 'S01',
        businessCode: null,
        displayName: 'Store 1',
        isActive: true,
      },
      {
        id: 'node-store-2',
        parentId: null,
        type: 'LV0_DOMAIN',
        code: 'S02',
        businessCode: null,
        displayName: 'Store 2',
        isActive: true,
      },
    ];
    (runtime.prepareAdminUserMutation as jest.Mock).mockResolvedValueOnce({
      email: createdUser.email,
      role: 'USER',
      workScopeType: 'STORE',
      personnel: { organizationNodeId: 'node-store-1' },
      organizationNodeIds: ['node-store-1', 'node-store-2'],
      createData: { email: createdUser.email, password: '' },
      updateData: undefined,
    });
    const create = jest.fn().mockResolvedValue(createdUser);
    const tx = { user: { create, update: jest.fn() } };
    const prisma = {
      user: {
        findMany: jest
          .fn()
          .mockResolvedValueOnce([])
          .mockResolvedValueOnce([createdUser]),
      },
      organizationNode: { findMany: jest.fn().mockResolvedValue([]) },
      store: {
        findMany: jest.fn().mockResolvedValue([
          {
            storeId: 'S01',
            organizationNodeId: 'node-store-1',
            organizationNode: storeNodes[0],
          },
          {
            storeId: 'S02',
            organizationNodeId: 'node-store-2',
            organizationNode: storeNodes[1],
          },
        ]),
      },
      $transaction: jest.fn(async (callback) => callback(tx)),
    };
    const service = new UserImportService(
      prisma as any,
      { publishForUserIds: jest.fn().mockResolvedValue(undefined) } as any,
      {
        sendWelcomeEmailsForImport: jest.fn().mockResolvedValue({
          sentEmails: new Set(['multi@phongvu.vn']),
          failedByEmail: new Map(),
          sentRows: 1,
          failedRows: 0,
        }),
      } as any,
      runtime,
    );

    await service.adminImportUsers(
      { id: 'admin', role: 'SUPER_ADMIN' },
      {
        totalRows: 1,
        skippedRows: 0,
        rows: [
          {
            rowNumber: 3,
            email: createdUser.email,
            fullName: 'Multi Store',
            role: 'USER',
            levelCodes: [],
            storeIds: [' s01 ', 'S02'],
          },
        ],
      },
    );

    expect(runtime.normalizeStoreCode).toHaveBeenCalledWith(' s01 ');
    expect(runtime.normalizeStoreCode).toHaveBeenCalledWith('S02');
    expect(
      runtime.assertOrganizationNodeAssignableByAdmin,
    ).toHaveBeenCalledTimes(2);
    expect(runtime.prepareAdminUserMutation).toHaveBeenCalledWith(
      { id: 'admin', role: 'SUPER_ADMIN' },
      expect.objectContaining({
        organizationNodeIds: ['node-store-1', 'node-store-2'],
      }),
      null,
    );
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenCalledWith(
      tx,
      createdUser.id,
      ['node-store-1', 'node-store-2'],
      { id: 'admin', role: 'SUPER_ADMIN' },
    );
  });

  it('keeps every imported user and assignment write in one rollback boundary', async () => {
    const runtime = createRuntime();
    const failure = new Error('second assignment write failed');
    const order: string[] = [];
    (runtime.prepareAdminUserMutation as jest.Mock).mockImplementation(
      async (_admin, body) => ({
        email: body.email,
        role: body.role,
        workScopeType: 'STORE',
        personnel: { organizationNodeId: 'node-1' },
        organizationNodeIds: ['node-1'],
        createData: { email: body.email, password: '' },
        updateData: undefined,
      }),
    );
    const create = jest.fn(async ({ data }) => ({
      id: data.email.startsWith('first') ? 'user-1' : 'user-2',
      email: data.email,
    }));
    const tx = { user: { create, update: jest.fn() } };
    const prisma = {
      user: { findMany: jest.fn().mockResolvedValue([]) },
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
      $transaction: jest.fn(async (callback) => {
        order.push('tx-start');
        const result = await callback(tx);
        order.push('tx-commit');
        return result;
      }),
    };
    (runtime.syncUserOrganizationAssignments as jest.Mock).mockImplementation(
      async (_client, userId) => {
        order.push(`sync:${userId}`);
        if (userId === 'user-2') throw failure;
      },
    );
    const accessChangeService = {
      publishForUserIds: jest.fn().mockResolvedValue(undefined),
    };
    const welcomeEmailService = {
      sendWelcomeEmailsForImport: jest.fn(),
    };
    const service = new UserImportService(
      prisma as any,
      accessChangeService as any,
      welcomeEmailService as any,
      runtime,
    );

    await expect(
      service.adminImportUsers(
        { id: 'admin', role: 'SUPER_ADMIN' },
        {
          totalRows: 2,
          skippedRows: 0,
          rows: [
            {
              rowNumber: 2,
              email: 'first@phongvu.vn',
              fullName: 'First',
              role: 'USER',
              levelCodes: ['ROOT', '', '', '', '', ''],
              storeIds: [],
            },
            {
              rowNumber: 3,
              email: 'second@phongvu.vn',
              fullName: 'Second',
              role: 'USER',
              levelCodes: ['ROOT', '', '', '', '', ''],
              storeIds: [],
            },
          ],
        },
      ),
    ).rejects.toBe(failure);

    expect(runtime.syncUserOrganizationAssignments).toHaveBeenNthCalledWith(
      1,
      tx,
      'user-1',
      ['node-1'],
      { id: 'admin', role: 'SUPER_ADMIN' },
    );
    expect(runtime.syncUserOrganizationAssignments).toHaveBeenNthCalledWith(
      2,
      tx,
      'user-2',
      ['node-1'],
      { id: 'admin', role: 'SUPER_ADMIN' },
    );
    expect(order).toEqual(['tx-start', 'sync:user-1', 'sync:user-2']);
    expect(accessChangeService.publishForUserIds).not.toHaveBeenCalled();
    expect(
      welcomeEmailService.sendWelcomeEmailsForImport,
    ).not.toHaveBeenCalled();
  });

  it('aggregates row validation errors before opening the persistence transaction', async () => {
    const runtime = createRuntime();
    (runtime.assertAccountEmailAllowed as jest.Mock).mockRejectedValueOnce(
      new Error('email domain is not allowed'),
    );
    const prisma = {
      user: { findMany: jest.fn().mockResolvedValue([]) },
      organizationNode: {
        findMany: jest.fn().mockResolvedValue([]),
      },
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
        { id: 'admin', role: 'SUPER_ADMIN' },
        {
          totalRows: 1,
          skippedRows: 0,
          rows: [
            {
              rowNumber: 9,
              email: 'blocked@external.vn',
              fullName: 'Blocked',
              role: 'USER',
              levelCodes: ['ROOT', '', '', '', '', ''],
              storeIds: [],
            },
          ],
        },
      ),
    ).rejects.toThrow(
      'File nhân sự chưa hợp lệ: dòng 9: email domain is not allowed',
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(runtime.prepareAdminUserMutation).not.toHaveBeenCalled();
  });

  it('logs and rethrows persistence failures after import preparation', async () => {
    const runtime = createRuntime();
    const failure = new Error('database unavailable');
    const prisma = {
      user: {
        findMany: jest.fn().mockResolvedValueOnce([]),
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
      $transaction: jest.fn().mockRejectedValue(failure),
    };
    const service = new UserImportService(
      prisma as any,
      { publishForUserIds: jest.fn() } as any,
      { sendWelcomeEmailsForImport: jest.fn() } as any,
      runtime,
    );

    await expect(
      service.adminImportUsers(
        { id: 'admin', role: 'SUPER_ADMIN' },
        {
          totalRows: 1,
          skippedRows: 0,
          rows: [
            {
              rowNumber: 5,
              email: 'failure@phongvu.vn',
              fullName: 'Failure',
              role: 'USER',
              levelCodes: ['ROOT', '', '', '', '', ''],
              storeIds: [],
            },
          ],
        },
      ),
    ).rejects.toBe(failure);
    expect(runtime.logger.error).toHaveBeenCalledWith(
      expect.stringContaining('Admin user import failed'),
      expect.anything(),
    );
  });
});

describe('UserWelcomeEmailService import summary', () => {
  it('separates sent, missing-user and non-created rows', async () => {
    const hooks = {
      normalizeAccountEmail: jest.fn((value) =>
        String(value).trim().toLowerCase(),
      ),
      userLogId: jest.fn(() => 'admin-id'),
      logger: { log: jest.fn(), error: jest.fn() },
    };
    const mailService = { sendMail: jest.fn().mockResolvedValue(undefined) };
    const service = new UserWelcomeEmailService(mailService as any, hooks);
    const prepared = [
      {
        rowNumber: 2,
        email: 'new@phongvu.vn',
        action: 'created' as const,
        role: 'USER',
        organizationNodeIds: [],
        organizationNodeId: null,
        organizationNodeName: null,
      },
      {
        rowNumber: 3,
        email: 'missing@phongvu.vn',
        action: 'created' as const,
        role: 'USER',
        organizationNodeIds: [],
        organizationNodeId: null,
        organizationNodeName: null,
      },
      {
        rowNumber: 4,
        email: 'existing@phongvu.vn',
        action: 'updated' as const,
        role: 'USER',
        organizationNodeIds: [],
        organizationNodeId: null,
        organizationNodeName: null,
      },
    ];

    const result = await service.sendWelcomeEmailsForImport(
      { id: 'admin' },
      prepared,
      new Map([
        ['new@phongvu.vn', { email: 'new@phongvu.vn', firstName: 'New' }],
      ]),
    );

    expect(result.sentEmails).toEqual(new Set(['new@phongvu.vn']));
    expect(result.failedByEmail).toEqual(
      new Map([['missing@phongvu.vn', 'Không tìm thấy người dùng sau import']]),
    );
    expect(result.sentRows).toBe(1);
    expect(result.failedRows).toBe(1);
    expect(mailService.sendMail).toHaveBeenCalledTimes(1);
  });
});
