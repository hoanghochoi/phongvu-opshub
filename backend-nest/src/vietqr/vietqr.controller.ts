import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { VietQrService } from './vietqr.service';

@Controller('vietqr')
@UseGuards(AuthGuard('jwt'))
export class VietQrController {
  constructor(private readonly vietQrService: VietQrService) {}

  @Post()
  async create(
    @Body()
    body: {
      amount?: number;
      orderCode?: string;
      storeCode?: string;
    },
  ) {
    return this.vietQrService.create({
      amount: Number(body.amount),
      orderCode: body.orderCode ?? '',
      storeCode: body.storeCode ?? '',
    });
  }
}
