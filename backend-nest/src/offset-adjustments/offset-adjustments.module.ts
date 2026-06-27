import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { OffsetAdjustmentsController } from './offset-adjustments.controller';
import { OffsetAdjustmentsService } from './offset-adjustments.service';

@Module({
  imports: [PrismaModule, RedisModule, NotificationsModule],
  controllers: [OffsetAdjustmentsController],
  providers: [OffsetAdjustmentsService],
  exports: [OffsetAdjustmentsService],
})
export class OffsetAdjustmentsModule {}
