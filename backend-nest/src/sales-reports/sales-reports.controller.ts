import {
  Body,
  Controller,
  Get,
  Post,
  Query,
  Request,
  Res,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
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
import { salesReportImportFileUploadOptions } from './sales-report-import-file-upload.options';
import { SalesReportImportService } from './sales-report-import.service';
import { SalesReportsService } from './sales-reports.service';

@Controller('sales-reports')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class SalesReportsController {
  constructor(
    private readonly service: SalesReportsService,
    private readonly bigQuerySync: SalesReportsBigQuerySyncService,
    private readonly importService: SalesReportImportService,
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

  @Post('import/preview')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  @UseInterceptors(FileInterceptor('file', salesReportImportFileUploadOptions))
  previewImport(
    @Request() req: any,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.importService.preview(req.user, file);
  }

  @Post('import/commit')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  @UseInterceptors(FileInterceptor('file', salesReportImportFileUploadOptions))
  commitImport(
    @Request() req: any,
    @UploadedFile() file: Express.Multer.File,
    @Body('expectedFileHash') expectedFileHash: string,
  ) {
    return this.importService.commit(req.user, file, expectedFileHash);
  }

  @Get()
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  list(@Request() req: any, @Query() query: ListSalesReportsDto) {
    return this.service.list(req.user, query);
  }

  @Get('export')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  async exportWorkbook(
    @Request() req: any,
    @Query() query: ExportSalesReportsDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const workbook = await this.service.exportWorkbook(req.user, query);
    const filename =
      query.exportType === 'REVENUE'
        ? 'opshub-bao-cao-doanh-so.xlsx'
        : query.exportType === 'INSTALLMENT'
          ? 'opshub-bao-cao-tra-gop.xlsx'
          : 'opshub-bao-cao-hvtc.xlsx';
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    return new StreamableFile(workbook);
  }

  @Post('admin/bigquery-sync')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  syncBigQuery() {
    return this.bigQuerySync.syncAll('manual', { force: true });
  }
}
