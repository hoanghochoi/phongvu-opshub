import { Module } from '@nestjs/common';
import { ErpModule } from '../erp';
import { FeatureModule } from '../feature/feature.module';
import { PrismaModule } from '../prisma/prisma.module';
import { ContractAppendicesController } from './contract-appendices.controller';
import { ContractAppendicesService } from './contract-appendices.service';

@Module({
  imports: [PrismaModule, FeatureModule, ErpModule],
  controllers: [ContractAppendicesController],
  providers: [ContractAppendicesService],
  exports: [ContractAppendicesService],
})
export class ContractAppendicesModule {}
