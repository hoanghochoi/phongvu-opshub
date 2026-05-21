import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { PaymentNotificationsController } from './payment-notifications.controller';
import { PaymentNotificationsService } from './payment-notifications.service';

@Module({
  imports: [PrismaModule, RedisModule],
  controllers: [PaymentNotificationsController],
  providers: [PaymentNotificationsService],
  exports: [PaymentNotificationsService],
})
export class PaymentNotificationsModule {}
