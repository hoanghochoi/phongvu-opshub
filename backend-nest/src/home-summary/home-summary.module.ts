import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { AuthModule } from '../auth/auth.module';
import { SalesReportsModule } from '../sales-reports/sales-reports.module';
import { HomeSummaryController } from './home-summary.controller';
import { HomeSummaryBackfillService } from './home-summary-backfill.service';
import { HomeSummaryProjectionService } from './home-summary-projection.service';
import { HomeSummaryService } from './home-summary.service';

@Module({
  imports: [PrismaModule, RedisModule, SalesReportsModule, AuthModule],
  controllers: [HomeSummaryController],
  providers: [
    HomeSummaryService,
    HomeSummaryProjectionService,
    HomeSummaryBackfillService,
  ],
})
export class HomeSummaryModule {}
