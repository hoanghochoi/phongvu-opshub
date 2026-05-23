import { Module } from '@nestjs/common';
import { FifoLogModule } from '../fifo-log/fifo-log.module';
import { PrismaModule } from '../prisma/prisma.module';
import { FifoController } from './fifo.controller';
import { FifoService } from './fifo.service';
import { PriceWatchdogInventoryService } from './price-watchdog-inventory.service';

@Module({
  imports: [PrismaModule, FifoLogModule],
  controllers: [FifoController],
  providers: [FifoService, PriceWatchdogInventoryService],
  exports: [FifoService],
})
export class FifoModule {}
