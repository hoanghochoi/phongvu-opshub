import {
  Body,
  Controller,
  Get,
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
  CheckSalesReportOrderDto,
  CreateSalesReportDto,
  ExportSalesReportsDto,
  ListSalesReportOrdersDto,
  ListSalesReportsDto,
} from './sales-reports.dto';
import { SalesReportsBigQuerySyncService } from './sales-reports-bigquery-sync.service';
import { SalesReportsService } from './sales-reports.service';

@Controller('sales-reports')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class SalesReportsController {
  constructor(
    private readonly service: SalesReportsService,
    private readonly bigQuerySync: SalesReportsBigQuerySyncService,
  ) {}

  @Get('categories')
  @RequireFeature(FEATURE_KEYS.SALES_REPORT)
  categoriesForReport() {
    return this.service.categoriesForReport();
  }

  @Get('admin/categories')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  categoriesForAdmin() {
    return this.service.categoriesForReport();
  }

  @Get('orders')
  @RequireFeature([FEATURE_KEYS.SALES_REPORT, FEATURE_KEYS.ADMIN_SALES_REPORTS])
  orders(@Request() req: any, @Query() query: ListSalesReportOrdersDto) {
    return this.service.orderCockpit(req.user, query);
  }

  @Post('check-order')
  @RequireFeature(FEATURE_KEYS.SALES_REPORT)
  checkOrder(@Request() req: any, @Body() body: CheckSalesReportOrderDto) {
    return this.service.checkOrder(req.user, body.orderCode);
  }

  @Post()
  @RequireFeature(FEATURE_KEYS.SALES_REPORT)
  create(@Request() req: any, @Body() body: CreateSalesReportDto) {
    return this.service.create(req.user, body);
  }

  @Get()
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  list(@Request() req: any, @Query() query: ListSalesReportsDto) {
    return this.service.list(req.user, query);
  }

  @Get('export')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  async exportCsv(
    @Request() req: any,
    @Query() query: ExportSalesReportsDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const csv = await this.service.exportCsv(req.user, query);
    const filename =
      query.exportType === 'REVENUE'
        ? 'opshub-bao-cao-doanh-so.csv'
        : query.exportType === 'INSTALLMENT'
          ? 'opshub-bao-cao-tra-gop.csv'
          : 'opshub-bao-cao-hvtc.csv';
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    return csv;
  }

  @Post('admin/bigquery-sync')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  syncBigQuery() {
    return this.bigQuerySync.syncAll('manual', { force: true });
  }
}
