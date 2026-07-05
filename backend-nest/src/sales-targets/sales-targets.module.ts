import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { SalesTargetsController } from './sales-targets.controller';
import { SalesTargetsService } from './sales-targets.service';

@Module({
  imports: [PrismaModule],
  controllers: [SalesTargetsController],
  providers: [SalesTargetsService],
  exports: [SalesTargetsService],
})
export class SalesTargetsModule {}
