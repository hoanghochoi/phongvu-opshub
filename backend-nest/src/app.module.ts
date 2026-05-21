import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
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

@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 120,
      },
    ]),
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    WarrantyModule,
    RedisModule,
    InventoryModule,
    SortModule,
    FeedbackModule,
    UploadModule,
    UserModule,
    FifoLogModule,
    VietQrModule,
    AppVersionModule,
    MapVietinModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
