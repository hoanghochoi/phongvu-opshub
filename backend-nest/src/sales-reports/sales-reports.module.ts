import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { SalesReportCategoriesService } from './sales-report-categories.service';
import { SalesReportErpService } from './sales-report-erp.service';
import { SalesReportsBigQuerySyncService } from './sales-reports-bigquery-sync.service';
import { SalesReportsController } from './sales-reports.controller';
import { SalesReportsService } from './sales-reports.service';

@Module({
  imports: [PrismaModule, RedisModule],
  controllers: [SalesReportsController],
  providers: [
    SalesReportCategoriesService,
    SalesReportErpService,
    SalesReportsBigQuerySyncService,
    SalesReportsService,
  ],
  exports: [SalesReportsService, SalesReportsBigQuerySyncService],
})
export class SalesReportsModule {}
