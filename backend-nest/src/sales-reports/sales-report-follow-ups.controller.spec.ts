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
});
