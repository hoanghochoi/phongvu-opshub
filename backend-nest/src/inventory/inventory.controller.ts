import {
  Controller,

  Get,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { AuthGuard } from '@nestjs/passport';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';

@Controller('inventory')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
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
  @RequireFeature(FEATURE_KEYS.FIFO_IMPORT)
  async manualSync() {
    await this.inventoryService.syncFromBigQuery();
    return { message: 'BigQuery sync triggered' };
  }
}
