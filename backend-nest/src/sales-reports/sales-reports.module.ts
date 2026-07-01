import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { SalesReportCategoriesService } from './sales-report-categories.service';
import { SalesReportErpService } from './sales-report-erp.service';
import { SalesReportsController } from './sales-reports.controller';
import { SalesReportsService } from './sales-reports.service';

@Module({
  imports: [PrismaModule, RedisModule],
  controllers: [SalesReportsController],
  providers: [
    SalesReportCategoriesService,
    SalesReportErpService,
    SalesReportsService,
  ],
})
export class SalesReportsModule {}
