import { FifoLogService } from './fifo-log.service';
import { ADMIN_POLICY_CODES } from '../policy/policy.constants';

describe('FifoLogService', () => {
  let service: FifoLogService;
  let prisma: {
    user: {
      findUnique: jest.Mock;
      findMany: jest.Mock;
    };
    fifoLog: {
      create: jest.Mock;
      findMany: jest.Mock;
      count: jest.Mock;
    };
  };

  let policyService: { canAccessPolicy: jest.Mock };

  beforeEach(() => {
    prisma = {
      user: {
        findUnique: jest.fn(),
        findMany: jest.fn(),
      },
      fifoLog: {
        create: jest.fn(),
        findMany: jest.fn(),
        count: jest.fn(),
      },
    };
    policyService = {
      canAccessPolicy: jest.fn(
        async (admin: any, code: string) =>
          ['SUPER_ADMIN', 'ADMIN_PHONGVU'].includes(
            String(admin?.role || '').toUpperCase(),
          ) &&
          String(code || '').toUpperCase() ===
            ADMIN_POLICY_CODES.FIFO_LOG_ADMIN,
      ),
    };
    service = new FifoLogService(prisma as any, policyService as any);
  });

  it('does not let branch admins filter logs outside their store', async () => {
    prisma.user.findUnique
      .mockResolvedValueOnce({
        id: 'admin-1',
        email: 'admin@phongvu-shop.vn',
        role: 'ADMIN_PHONGVU',
        storeId: 'store-1',
      })
      .mockResolvedValueOnce({
        id: 'outside-user',
        email: 'outside@phongvu-shop.vn',
        role: 'STAFF',
        storeId: 'store-2',
      });
    prisma.user.findMany.mockResolvedValue([{ id: 'branch-user' }]);

    await expect(
      service.getAdminLogs(
        'admin@phongvu-shop.vn',
        undefined,
        1,
        20,
        'outside@phongvu-shop.vn',
      ),
    ).resolves.toEqual({ data: [], total: 0, page: 1, limit: 20 });
    expect(prisma.fifoLog.findMany).not.toHaveBeenCalled();
    expect(prisma.fifoLog.count).not.toHaveBeenCalled();
  });
});
