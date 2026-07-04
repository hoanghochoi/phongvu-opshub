import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { SalesReportsModule } from '../sales-reports/sales-reports.module';
import { HomeSummaryController } from './home-summary.controller';
import { HomeSummaryService } from './home-summary.service';

@Module({
  imports: [PrismaModule, SalesReportsModule],
  controllers: [HomeSummaryController],
  providers: [HomeSummaryService],
})
export class HomeSummaryModule {}
