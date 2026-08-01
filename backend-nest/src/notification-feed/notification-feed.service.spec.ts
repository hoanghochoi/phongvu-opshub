import { NotificationFeedService } from './notification-feed.service';

describe('NotificationFeedService', () => {
  const user = { id: 'user-1', email: 'staff@phongvu.vn' };
  let featureService: { resolveFeatureAccessMap: jest.Mock };
  let mapVietinService: {
    listStatementOrderTransferRequests: jest.Mock;
  };
  let offsetAdjustmentsService: { list: jest.Mock };
  let supportChatService: { notificationSummary: jest.Mock };
  let service: NotificationFeedService;

  beforeEach(() => {
    featureService = {
      resolveFeatureAccessMap: jest.fn().mockResolvedValue({
        BANK_STATEMENTS: true,
        OFFSET_ADJUSTMENTS: true,
      }),
    };
    mapVietinService = {
      listStatementOrderTransferRequests: jest.fn().mockResolvedValue({
        page: 0,
        limit: 20,
        total: 1,
        canReview: true,
        list: [{ id: 'statement-1' }],
      }),
    };
    offsetAdjustmentsService = {
      list: jest.fn().mockResolvedValue({
        page: 0,
        limit: 20,
        total: 1,
        canReview: false,
        list: [{ id: 'offset-1' }],
      }),
    };
    supportChatService = {
      notificationSummary: jest.fn().mockResolvedValue(null),
    };
    service = new NotificationFeedService(
      featureService as any,
      mapVietinService as any,
      offsetAdjustmentsService as any,
      supportChatService as any,
    );
  });

  it('loads both authorized sources behind one feed contract', async () => {
    const result = await service.load(user);

    expect(featureService.resolveFeatureAccessMap).toHaveBeenCalledWith(user);
    expect(
      mapVietinService.listStatementOrderTransferRequests,
    ).toHaveBeenCalledWith(user, {
      status: 'NOTIFICATION',
      page: 0,
      limit: 20,
    });
    expect(offsetAdjustmentsService.list).toHaveBeenCalledWith(user, {
      type: 'ALL',
      status: 'NOTIFICATION',
      page: 0,
      limit: 20,
    });
    expect(result.schemaVersion).toBe(1);
    expect(result.statementOrderTransfers).toMatchObject({
      enabled: true,
      total: 1,
    });
    expect(result.offsetAdjustments).toMatchObject({
      enabled: true,
      total: 1,
    });
  });

  it('does not query a source that is not granted', async () => {
    featureService.resolveFeatureAccessMap.mockResolvedValue({
      BANK_STATEMENTS: false,
      OFFSET_ADJUSTMENTS: true,
    });

    const result = await service.load(user);

    expect(
      mapVietinService.listStatementOrderTransferRequests,
    ).not.toHaveBeenCalled();
    expect(result.statementOrderTransfers).toMatchObject({
      enabled: false,
      total: 0,
      list: [],
    });
    expect(offsetAdjustmentsService.list).toHaveBeenCalledTimes(1);
  });

  it('fails the aggregate request when an authorized source fails', async () => {
    offsetAdjustmentsService.list.mockRejectedValue(new Error('database down'));

    await expect(service.load(user)).rejects.toThrow('database down');
  });

  it('adds support chat without changing the existing feed sections', async () => {
    supportChatService.notificationSummary.mockResolvedValue({
      enabled: true,
      unreadCount: 2,
      conversationId: 'conversation-1',
      status: 'OPEN',
    });

    const result = await service.load(user);

    expect(result.schemaVersion).toBe(1);
    expect(result.supportChat).toMatchObject({ enabled: true, unreadCount: 2 });
    expect(result.statementOrderTransfers.list).toEqual([
      { id: 'statement-1' },
    ]);
    expect(result.offsetAdjustments.list).toEqual([{ id: 'offset-1' }]);
  });

  it('keeps existing feed sections available when support chat summary fails', async () => {
    supportChatService.notificationSummary.mockRejectedValue(
      new Error('support database unavailable'),
    );

    const result = await service.load(user);

    expect(result).not.toHaveProperty('supportChat');
    expect(result.statementOrderTransfers.list).toEqual([
      { id: 'statement-1' },
    ]);
    expect(result.offsetAdjustments.list).toEqual([{ id: 'offset-1' }]);
  });
});
