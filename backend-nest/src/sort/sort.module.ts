import { Module } from '@nestjs/common';
import { SortController } from './sort.controller';
import { SortService } from './sort.service';
import { InventoryModule } from '../inventory/inventory.module';
import { FifoLogModule } from '../fifo-log/fifo-log.module';

@Module({
  imports: [InventoryModule, FifoLogModule],
  controllers: [SortController],
  providers: [SortService],
})
export class SortModule { }
