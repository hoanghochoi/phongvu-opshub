import { GUARDS_METADATA } from '@nestjs/common/constants';
import { AuthGuard } from '@nestjs/passport';
import { NotificationFeedController } from './notification-feed.controller';

describe('NotificationFeedController security', () => {
  it('protects the aggregate feed with the JWT guard', () => {
    const guards = Reflect.getMetadata(
      GUARDS_METADATA,
      NotificationFeedController,
    );

    expect(guards).toEqual(expect.arrayContaining([AuthGuard('jwt')]));
  });
});
