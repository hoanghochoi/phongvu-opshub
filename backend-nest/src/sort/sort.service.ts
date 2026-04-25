import { Injectable } from '@nestjs/common';
import { InventoryService } from '../inventory/inventory.service';
import { FifoLogService } from '../fifo-log/fifo-log.service';
import { FifoLogType } from '@prisma/client';

@Injectable()
export class SortService {
  constructor(
    private inventoryService: InventoryService,
    private fifoLogService: FifoLogService,
  ) {}

  // First tries SKU lookup, falls back to BIN lookup.
  async sort(text: string, userEmail?: string) {
    // Try by SKU first
    let items = await this.inventoryService.lookupBySku(text);

    // If no results, try by BIN code
    if (items.length === 0) {
      items = await this.inventoryService.lookupByBin(text);
    }

    // Log the sort operation
    if (userEmail) {
      const resultSummary =
        items.length > 0 ? `${items.length} item(s) found` : 'Không tìm thấy';
      this.fifoLogService.createLog(
        FifoLogType.FIFO_SORT,
        text,
        resultSummary,
        items,
        userEmail,
      );
    }

    return items;
  }

  // -------------------------------------------------------
  // FIFO Check: SKU (with qty) or Serial lookup
  // - SKU only → returns oldest 2 items (qty default=1, take qty+1)
  // - SKU + qty=n → returns oldest n+1 items
  // - Serial only → checks if it's the oldest for its SKU
  // -------------------------------------------------------
  async fifoCheck(text: string, qty?: number, userEmail?: string) {
    // 1. Try by SKU first
    const skuItems = await this.inventoryService.fifoCheckBySku(text, qty ?? 1);

    if (skuItems.length > 0) {
      // Log FIFO check
      if (userEmail) {
        this.fifoLogService.createLog(
          FifoLogType.FIFO_CHECK,
          text,
          `SKU check: ${skuItems.length} item(s)`,
          skuItems,
          userEmail,
        );
      }
      return skuItems; // Returns array of items
    }

    // 2. If no SKU match, try serial lookup
    const serialResult = await this.inventoryService.fifoCheckBySerial(text);

    // Log FIFO check
    if (userEmail) {
      const summary = serialResult?.message || 'Serial lookup';
      this.fifoLogService.createLog(
        FifoLogType.FIFO_CHECK,
        text,
        summary,
        serialResult,
        userEmail,
      );
    }

    return serialResult; // Returns { found, is_oldest, message, item }
  }

  async completionReport(
    sortedSKUs: any[],
    userEmail?: string,
    timestamp?: string,
  ) {
    if (userEmail) {
      await this.fifoLogService.createLog(
        FifoLogType.FIFO_SORT,
        'COMPLETION_REPORT',
        `Completed sorting ${sortedSKUs.length} SKU group(s)`,
        {
          sortedSKUs,
          timestamp: timestamp ?? new Date().toISOString(),
        },
        userEmail,
      );
    }

    return {
      status: 'success',
      sortedCount: sortedSKUs.length,
    };
  }
}
