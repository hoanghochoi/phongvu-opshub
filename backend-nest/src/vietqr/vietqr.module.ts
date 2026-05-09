import { Module } from '@nestjs/common';
import { VietQrController } from './vietqr.controller';
import { VietQrService } from './vietqr.service';

@Module({
  controllers: [VietQrController],
  providers: [VietQrService],
})
export class VietQrModule {}
