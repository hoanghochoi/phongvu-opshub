import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { PaymentNotificationsModule } from '../payment-notifications/payment-notifications.module';
import { RedisModule } from '../redis/redis.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { MapVietinBigQueryModule } from '../map-vietin-bigquery/map-vietin-bigquery.module';
import { SalesReportsModule } from '../sales-reports/sales-reports.module';
import { MapVietinController } from './map-vietin.controller';
import { MapVietinService } from './map-vietin.service';

@Module({
  imports: [
    PrismaModule,
    PaymentNotificationsModule,
    RedisModule,
    NotificationsModule,
    MapVietinBigQueryModule,
    SalesReportsModule,
  ],
  controllers: [MapVietinController],
  providers: [MapVietinService],
  exports: [MapVietinService],
})
export class MapVietinModule {}
