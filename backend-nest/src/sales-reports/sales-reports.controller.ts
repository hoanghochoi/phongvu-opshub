import {
  Body,
  Controller,
  Get,
  Param,
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
import { SalesHistoryImportService } from './sales-history-import.service';
import { salesHistoryImportChunkUploadOptions } from './sales-history-import-upload.options';
import { SalesReportsService } from './sales-reports.service';

@Controller('sales-reports')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class SalesReportsController {
  constructor(
    private readonly service: SalesReportsService,
    private readonly bigQuerySync: SalesReportsBigQuerySyncService,
    private readonly importService: SalesReportImportService,
    private readonly historyImportService: SalesHistoryImportService,
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

  @Post('history-import/jobs')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  createHistoryImportUpload(
    @Request() req: any,
    @Body() body: { fileName?: string; fileSize?: number },
  ) {
    return this.historyImportService.createUpload(
      req.user,
      body?.fileName,
      body?.fileSize,
    );
  }

  @Post('history-import/jobs/:id/chunks')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  @UseInterceptors(
    FileInterceptor('chunk', salesHistoryImportChunkUploadOptions),
  )
  appendHistoryImportChunk(
    @Request() req: any,
    @Param('id') id: string,
    @Body('offset') offset: string,
    @UploadedFile() chunk: Express.Multer.File,
  ) {
    return this.historyImportService.appendUploadChunk(
      req.user,
      id,
      Number(offset),
      chunk,
    );
  }

  @Post('history-import/jobs/:id/complete')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  completeHistoryImportUpload(@Request() req: any, @Param('id') id: string) {
    return this.historyImportService.completeUpload(req.user, id);
  }

  @Get('history-import/jobs/:id')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  historyImportJob(@Request() req: any, @Param('id') id: string) {
    return this.historyImportService.getJob(req.user, id);
  }

  @Post('history-import/jobs/:id/cancel')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  cancelHistoryImport(@Request() req: any, @Param('id') id: string) {
    return this.historyImportService.cancelJob(req.user, id);
  }

  @Get('history-import/jobs/:id/quarantine')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  async historyImportQuarantine(
    @Request() req: any,
    @Param('id') id: string,
    @Res({ passthrough: true }) res: Response,
  ) {
    const report = await this.historyImportService.quarantineReport(
      req.user,
      id,
    );
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      'attachment; filename="opshub-du-lieu-cach-ly.csv"',
    );
    return new StreamableFile(report);
  }

  @Get('history-import/versions')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  historyImportVersions(@Request() req: any, @Query('limit') limit?: string) {
    return this.historyImportService.listVersions(req.user, Number(limit));
  }

  @Post('history-import/versions/:id/activate')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  activateHistoryVersion(@Request() req: any, @Param('id') id: string) {
    return this.historyImportService.activate(req.user, id);
  }

  @Post('history-import/versions/:id/rollback')
  @RequireFeature(FEATURE_KEYS.ADMIN_SALES_REPORTS)
  rollbackHistoryVersion(@Request() req: any, @Param('id') id: string) {
    return this.historyImportService.rollback(req.user, id);
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
