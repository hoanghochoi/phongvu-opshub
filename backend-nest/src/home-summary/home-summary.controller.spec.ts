import { HomeSummaryController } from './home-summary.controller';

describe('HomeSummaryController', () => {
  it('forwards the authenticated user and query to the service', async () => {
    const service = {
      getSummary: jest.fn().mockResolvedValue({ ok: true }),
      getBehaviorDetails: jest.fn(),
    };
    const controller = new HomeSummaryController(service as any);
    const req = { user: { id: 'user-1' } };
    const query = { date: '2026-07-04' };

    await expect(controller.summary(req, query)).resolves.toEqual({ ok: true });
    expect(service.getSummary).toHaveBeenCalledWith(req.user, query);
  });

  it('forwards behavior detail requests to the service', async () => {
    const service = {
      getSummary: jest.fn(),
      getBehaviorDetails: jest.fn().mockResolvedValue({ ok: true }),
    };
    const controller = new HomeSummaryController(service as any);
    const req = { user: { id: 'user-1' } };
    const query = { startDate: '2026-07-04', endDate: '2026-07-04' };

    await expect(controller.details(req, query)).resolves.toEqual({ ok: true });
    expect(service.getBehaviorDetails).toHaveBeenCalledWith(req.user, query);
  });

  it('forwards cursor detail v2 requests to the service', async () => {
    const service = {
      getSummary: jest.fn(),
      getBehaviorDetails: jest.fn(),
      getBehaviorDetailsV2: jest.fn().mockResolvedValue({ items: [] }),
    };
    const controller = new HomeSummaryController(service as any);
    const req = { user: { id: 'user-1' } };
    const query = { kind: 'UNREPORTED_ORDER' as const, limit: 50 };

    await expect(controller.detailsV2(req, query)).resolves.toEqual({
      items: [],
    });
    expect(service.getBehaviorDetailsV2).toHaveBeenCalledWith(req.user, query);
  });
});
