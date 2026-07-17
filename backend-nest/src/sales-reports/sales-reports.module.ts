import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { SalesReportCategoriesService } from './sales-report-categories.service';
import { SalesReportErpService } from './sales-report-erp.service';
import { SalesReportsBigQuerySyncService } from './sales-reports-bigquery-sync.service';
import { SalesReportsController } from './sales-reports.controller';
import { SalesReportsService } from './sales-reports.service';
import { SalesReportFollowUpsController } from './sales-report-follow-ups.controller';
import { SalesReportFollowUpsService } from './sales-report-follow-ups.service';

@Module({
  imports: [PrismaModule, RedisModule],
  controllers: [SalesReportsController, SalesReportFollowUpsController],
  providers: [
    SalesReportCategoriesService,
    SalesReportErpService,
    SalesReportsBigQuerySyncService,
    SalesReportsService,
    SalesReportFollowUpsService,
  ],
  exports: [
    SalesReportErpService,
    SalesReportsService,
    SalesReportsBigQuerySyncService,
  ],
})
export class SalesReportsModule {}
