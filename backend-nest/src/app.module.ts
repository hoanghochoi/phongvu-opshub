import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerModule } from '@nestjs/throttler';
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
import { SalesReportsModule } from './sales-reports/sales-reports.module';
import { UserAwareThrottlerGuard } from './common/user-aware-throttler.guard';

@Module({
  imports: [
    ThrottlerModule.forRoot({
      throttlers: [
        {
          ttl: 60_000,
          limit: 120,
        },
      ],
      errorMessage:
        'Bạn đang thao tác quá nhanh. Vui lòng chờ một chút rồi thử lại.',
    }),
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
    MapVietinModule,
    OffsetAdjustmentsModule,
    SalesReportsModule,
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
