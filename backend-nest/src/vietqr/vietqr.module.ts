import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { MapVietinModule } from '../map-vietin/map-vietin.module';
import { VietQrController } from './vietqr.controller';
import { VietQrService } from './vietqr.service';

@Module({
  imports: [PrismaModule, MapVietinModule],
  controllers: [VietQrController],
  providers: [VietQrService],
})
export class VietQrModule {}
