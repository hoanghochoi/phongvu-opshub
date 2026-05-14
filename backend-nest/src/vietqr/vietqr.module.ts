import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { VietQrController } from './vietqr.controller';
import { VietQrService } from './vietqr.service';

@Module({
  imports: [PrismaModule],
  controllers: [VietQrController],
  providers: [VietQrService],
})
export class VietQrModule {}
