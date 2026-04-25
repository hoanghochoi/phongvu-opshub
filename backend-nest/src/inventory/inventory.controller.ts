import { Controller, Get, Query, UseGuards, Post } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { AuthGuard } from '@nestjs/passport';

@Controller('inventory')
@UseGuards(AuthGuard('jwt'))
export class InventoryController {
  constructor(private readonly inventoryService: InventoryService) {}

  // GET /inventory/lookup?q=SKU_OR_BIN&type=sku|bin
  @Get('lookup')
  async lookup(@Query('q') q: string, @Query('type') type: string) {
    if (type === 'bin') {
      return this.inventoryService.lookupByBin(q || '');
    }
    return this.inventoryService.lookupBySku(q || '');
  }

  // POST /inventory/sync - manually trigger sync (admin only)
  @Post('sync')
  async manualSync() {
    await this.inventoryService.syncFromBigQuery();
    return { message: 'BigQuery sync triggered' };
  }
}
