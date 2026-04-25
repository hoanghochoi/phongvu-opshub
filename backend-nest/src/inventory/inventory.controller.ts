import { Controller, Get, Query, UseGuards, Post } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { AuthGuard } from '@nestjs/passport';

@Controller('inventory')
@UseGuards(AuthGuard('jwt'))
export class InventoryController {
    constructor(private readonly inventoryService: InventoryService) { }

    // POST /inventory/lookup - main lookup (matches n8n pva-chat and pva-sort behaviour)
    // Body: { text: "SKU_OR_BIN", user: "email" }
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
