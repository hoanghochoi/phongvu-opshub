import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Query,
  Request,
  Res,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Response } from 'express';
import {
  CreateAppLogDto,
  ListPaymentNotificationsQueryDto,
  PaymentNotificationAckDto,
} from './payment-notifications.dto';
import { PaymentNotificationsService } from './payment-notifications.service';

@Controller()
@UseGuards(AuthGuard('jwt'))
export class PaymentNotificationsController {
  constructor(private readonly service: PaymentNotificationsService) {}

  @Get('payment-notifications/ready')
  listReady(
    @Request() req: any,
    @Query() query: ListPaymentNotificationsQueryDto,
  ) {
    return this.service.listReadyForClient(req.user, query);
  }

  @Get('payment-notifications/:id/audio')
  @Header('Cache-Control', 'private, max-age=300')
  async getAudio(
    @Request() req: any,
    @Param('id') id: string,
    @Res({ passthrough: true }) response: Response,
  ) {
    const audio = await this.service.getAudioForUser(req.user, id);
    response.setHeader('Content-Type', audio.mimeType);
    response.setHeader(
      'Content-Disposition',
      `inline; filename="${audio.fileName}"`,
    );
    return audio.stream;
  }

  @Post('payment-notifications/:id/ack')
  acknowledge(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: PaymentNotificationAckDto,
  ) {
    return this.service.acknowledge(req.user, id, body);
  }

  @Post('app-logs')
  createAppLog(@Request() req: any, @Body() body: CreateAppLogDto) {
    return this.service.createAppLog(req.user, body);
  }
}
