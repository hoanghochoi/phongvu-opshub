import { Module } from '@nestjs/common';
import { FifoLogModule } from '../fifo-log/fifo-log.module';
import { PrismaModule } from '../prisma/prisma.module';
import { FifoController } from './fifo.controller';
import { FifoService } from './fifo.service';
import { ManualInventoryParserService } from './manual-inventory-parser.service';
import { OpshubFifoInventoryService } from './opshub-fifo-inventory.service';

@Module({
  imports: [PrismaModule, FifoLogModule],
  controllers: [FifoController],
  providers: [
    FifoService,
    ManualInventoryParserService,
    OpshubFifoInventoryService,
  ],
  exports: [FifoService],
})
export class FifoModule {}
