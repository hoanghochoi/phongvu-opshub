import { GUARDS_METADATA } from '@nestjs/common/constants';
import { AuthGuard } from '@nestjs/passport';
import { FeatureGuard } from '../feature/feature.guard';
import { SalesReportFollowUpsController } from './sales-report-follow-ups.controller';

describe('SalesReportFollowUpsController security', () => {
  it('bắt buộc xác thực JWT và kiểm tra quyền tính năng cho toàn bộ route', () => {
    const guards = Reflect.getMetadata(
      GUARDS_METADATA,
      SalesReportFollowUpsController,
    );

    expect(guards).toEqual(
      expect.arrayContaining([AuthGuard('jwt'), FeatureGuard]),
    );
  });

  it('trả workbook với tên file theo khoảng ngày đã chọn', async () => {
    const workbook = Buffer.from([1, 2, 3]);
    const service = {
      exportHistory: jest.fn().mockResolvedValue(workbook),
    };
    const controller = new SalesReportFollowUpsController(service as any);
    const response = { setHeader: jest.fn() };

    const result = await controller.exportHistory(
      { user: { id: 'manager-1' } },
      { startDate: '2026-07-01', endDate: '2026-07-31' },
      response as any,
    );

    expect(service.exportHistory).toHaveBeenCalledWith(
      { id: 'manager-1' },
      { startDate: '2026-07-01', endDate: '2026-07-31' },
    );
    expect(response.setHeader).toHaveBeenCalledWith(
      'Content-Disposition',
      'attachment; filename="opshub-lich-su-cham-soc-2026-07-01-2026-07-31.xlsx"',
    );
    expect(result.getStream()).toBeDefined();
  });
});
