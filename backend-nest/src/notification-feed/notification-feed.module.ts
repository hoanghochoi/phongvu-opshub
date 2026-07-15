import { Module } from '@nestjs/common';
import { FeatureModule } from '../feature/feature.module';
import { MapVietinModule } from '../map-vietin/map-vietin.module';
import { OffsetAdjustmentsModule } from '../offset-adjustments/offset-adjustments.module';
import { NotificationFeedController } from './notification-feed.controller';
import { NotificationFeedService } from './notification-feed.service';

@Module({
  imports: [FeatureModule, MapVietinModule, OffsetAdjustmentsModule],
  controllers: [NotificationFeedController],
  providers: [NotificationFeedService],
})
export class NotificationFeedModule {}
