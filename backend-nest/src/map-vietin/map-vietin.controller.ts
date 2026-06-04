import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Request,
  Res,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Response } from 'express';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import {
  ExportMapVietinStatementsDto,
  ListStoredMapVietinTransactionsDto,
  ListMapVietinStatementsDto,
  SearchMapVietinTransactionsDto,
  UpdateMapVietinStatementOrdersDto,
} from './map-vietin.dto';
import { MapVietinService } from './map-vietin.service';

@Controller('admin/map-vietin')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class MapVietinController {
  constructor(private readonly mapVietinService: MapVietinService) {}

  @Post('transactions/search')
  @RequireFeature(FEATURE_KEYS.BANK_STATEMENTS)
  searchTransactions(
    @Request() req: any,
    @Body() body: SearchMapVietinTransactionsDto,
  ) {
    return this.mapVietinService.searchTransactions(req.user, body);
  }

  @Get('transactions')
  @RequireFeature(FEATURE_KEYS.PAYMENT_MONITOR)
  listStoredTransactions(
    @Request() req: any,
    @Query() query: ListStoredMapVietinTransactionsDto,
  ) {
    return this.mapVietinService.listStoredTransactions(req.user, query);
  }

  @Get('statements')
  @RequireFeature(FEATURE_KEYS.BANK_STATEMENTS)
  listStatements(
    @Request() req: any,
    @Query() query: ListMapVietinStatementsDto,
  ) {
    return this.mapVietinService.listStatements(req.user, query);
  }

  @Post('statements/export')
  @RequireFeature(FEATURE_KEYS.BANK_STATEMENTS)
  async exportStatements(
    @Request() req: any,
    @Body() body: ExportMapVietinStatementsDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const csv = await this.mapVietinService.exportStatementsCsv(req.user, body);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      'attachment; filename="opshub-bank-statements.csv"',
    );
    return csv;
  }

  @Patch('statements/:id/orders')
  @RequireFeature(FEATURE_KEYS.BANK_STATEMENTS)
  updateStatementOrders(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: UpdateMapVietinStatementOrdersDto,
  ) {
    return this.mapVietinService.updateStatementOrders(req.user, id, body);
  }

  @Get('statements/:id/order-history')
  @RequireFeature(FEATURE_KEYS.BANK_STATEMENTS)
  listStatementOrderHistory(@Request() req: any, @Param('id') id: string) {
    return this.mapVietinService.listStatementOrderHistory(req.user, id);
  }
}
