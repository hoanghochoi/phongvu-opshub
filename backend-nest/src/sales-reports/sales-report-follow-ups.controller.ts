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
  StreamableFile,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Response } from 'express';
import { RequireFeature } from '../feature/feature.decorator';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureGuard } from '../feature/feature.guard';
import {
  AssignSalesReportFollowUpCaseDto,
  CheckSalesReportOrderDto,
  CreateSalesReportFollowUpEntryDto,
  ExportSalesReportFollowUpHistoryDto,
  ListSalesReportFollowUpCasesDto,
} from './sales-reports.dto';
import { SalesReportFollowUpsService } from './sales-report-follow-ups.service';

@Controller('sales-reports/follow-up-cases')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
@RequireFeature([FEATURE_KEYS.SALES_REPORT, FEATURE_KEYS.ADMIN_SALES_REPORTS])
export class SalesReportFollowUpsController {
  constructor(private readonly service: SalesReportFollowUpsService) {}

  @Get()
  list(@Request() req: any, @Query() query: ListSalesReportFollowUpCasesDto) {
    return this.service.list(req.user, query);
  }

  @Get('export')
  async exportHistory(
    @Request() req: any,
    @Query() query: ExportSalesReportFollowUpHistoryDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const workbook = await this.service.exportHistory(req.user, query);
    const range = [query.startDate, query.endDate].filter(Boolean).join('-');
    const suffix = range ? `-${range}` : '';
    res.setHeader(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="opshub-lich-su-cham-soc${suffix}.xlsx"`,
    );
    return new StreamableFile(workbook);
  }

  @Get(':id')
  detail(@Request() req: any, @Param('id') id: string) {
    return this.service.detail(req.user, id);
  }

  @Post(':id/check-order')
  checkOrder(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: CheckSalesReportOrderDto,
  ) {
    return this.service.checkOrder(req.user, id, body.orderCode);
  }

  @Post(':id/entries')
  createEntry(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: CreateSalesReportFollowUpEntryDto,
  ) {
    return this.service.createEntry(req.user, id, body);
  }

  @Patch(':id/assignee')
  assign(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: AssignSalesReportFollowUpCaseDto,
  ) {
    return this.service.assign(req.user, id, body);
  }

  @Post(':id/reopen')
  reopen(@Request() req: any, @Param('id') id: string) {
    return this.service.reopen(req.user, id);
  }
}
