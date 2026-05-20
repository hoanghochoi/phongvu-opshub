import { Body, Controller, Param, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { VietQrService } from './vietqr.service';

@Controller('vietqr')
@UseGuards(AuthGuard('jwt'))
export class VietQrController {
  constructor(private readonly vietQrService: VietQrService) {}

  @Post()
  async create(
    @Request() req: any,
    @Body()
    body: {
      amount?: number | string | null;
      orderCode?: string;
      storeCode?: string;
    },
  ) {
    const rawAmount = body.amount;
    const amount =
      rawAmount === undefined || rawAmount === null || rawAmount === ''
        ? null
        : Number(rawAmount);

    return this.vietQrService.create({
      amount,
      orderCode: body.orderCode ?? '',
      storeCode: body.storeCode ?? '',
      createdById: req.user?.id,
    });
  }

  @Post(':id/confirm')
  async confirm(@Request() req: any, @Param('id') id: string) {
    return this.vietQrService.confirmPayment(req.user, id);
  }
}
