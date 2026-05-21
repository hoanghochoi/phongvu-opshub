import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { PaymentNotificationsModule } from '../payment-notifications/payment-notifications.module';
import { MapVietinController } from './map-vietin.controller';
import { MapVietinService } from './map-vietin.service';

@Module({
  imports: [PrismaModule, PaymentNotificationsModule],
  controllers: [MapVietinController],
  providers: [MapVietinService],
  exports: [MapVietinService],
})
export class MapVietinModule {}
