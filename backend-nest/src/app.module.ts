import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import {
  ThrottlerModule,
  type ThrottlerModuleOptions,
} from '@nestjs/throttler';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { WarrantyModule } from './warranty/warranty.module';
import { RedisModule } from './redis/redis.module';
import { InventoryModule } from './inventory/inventory.module';
import { SortModule } from './sort/sort.module';
import { FeedbackModule } from './feedback/feedback.module';
import { UploadModule } from './upload/upload.module';
import { UserModule } from './user/user.module';
import { FifoLogModule } from './fifo-log/fifo-log.module';
import { VietQrModule } from './vietqr/vietqr.module';
import { AppVersionModule } from './app-version/app-version.module';
import { MapVietinModule } from './map-vietin/map-vietin.module';
import { PolicyModule } from './policy/policy.module';
import { PaymentNotificationsModule } from './payment-notifications/payment-notifications.module';
import { FifoModule } from './fifo/fifo.module';
import { FeatureModule } from './feature/feature.module';
import { OffsetAdjustmentsModule } from './offset-adjustments/offset-adjustments.module';
import { NotificationsModule } from './notifications/notifications.module';
import { HomeSummaryModule } from './home-summary/home-summary.module';
import { HelpContentModule } from './help-content/help-content.module';
import { SalesReportsModule } from './sales-reports/sales-reports.module';
import { UserAwareThrottlerGuard } from './common/user-aware-throttler.guard';
import { SalesTargetsModule } from './sales-targets/sales-targets.module';
import { QuickActionsModule } from './quick-actions/quick-actions.module';
import { NotificationFeedModule } from './notification-feed/notification-feed.module';
import { ContractAppendicesModule } from './contract-appendices/contract-appendices.module';

export const GLOBAL_API_THROTTLER_OPTIONS = {
  throttlers: [
    {
      name: 'principal',
      ttl: 60_000,
      limit: 120,
    },
  ],
  errorMessage:
    'Bạn đang thao tác quá nhanh. Vui lòng chờ một chút rồi thử lại.',
} satisfies ThrottlerModuleOptions;

@Module({
  imports: [
    ThrottlerModule.forRoot(GLOBAL_API_THROTTLER_OPTIONS),
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    WarrantyModule,
    RedisModule,
    InventoryModule,
    PolicyModule,
    SortModule,
    FeedbackModule,
    UploadModule,
    UserModule,
    FifoLogModule,
    VietQrModule,
    AppVersionModule,
    FeatureModule,
    PaymentNotificationsModule,
    NotificationsModule,
    NotificationFeedModule,
    HomeSummaryModule,
    HelpContentModule,
    MapVietinModule,
    OffsetAdjustmentsModule,
    SalesReportsModule,
    SalesTargetsModule,
    QuickActionsModule,
    ContractAppendicesModule,
    FifoModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    {
      provide: APP_GUARD,
      useClass: UserAwareThrottlerGuard,
    },
  ],
})
export class AppModule {}
