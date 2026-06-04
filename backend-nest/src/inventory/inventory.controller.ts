import {
  Controller,
  ForbiddenException,
  Get,
  Post,
  Query,
  Req,
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
  async manualSync(@Req() req: any) {
    const role = req.user?.role;
    if (role !== 'ADMIN' && role !== 'SUPER_ADMIN') {
      throw new ForbiddenException('Không có quyền đồng bộ tồn kho');
    }

    await this.inventoryService.syncFromBigQuery();
    return { message: 'BigQuery sync triggered' };
  }
}
