import { Module } from '@nestjs/common';
import { RedisModule } from '../redis/redis.module';
import { SalesReportsModule } from '../sales-reports/sales-reports.module';
import { ErpPpmProductService } from './erp-ppm-product.service';

@Module({
  imports: [RedisModule, SalesReportsModule],
  providers: [ErpPpmProductService],
  exports: [ErpPpmProductService, SalesReportsModule],
})
export class ErpModule {}
