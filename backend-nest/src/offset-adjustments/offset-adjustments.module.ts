import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { SalesReportsModule } from '../sales-reports/sales-reports.module';
import { OffsetAdjustmentsController } from './offset-adjustments.controller';
import { OffsetAdjustmentsService } from './offset-adjustments.service';

@Module({
  imports: [PrismaModule, RedisModule, NotificationsModule, SalesReportsModule],
  controllers: [OffsetAdjustmentsController],
  providers: [OffsetAdjustmentsService],
  exports: [OffsetAdjustmentsService],
})
export class OffsetAdjustmentsModule {}
