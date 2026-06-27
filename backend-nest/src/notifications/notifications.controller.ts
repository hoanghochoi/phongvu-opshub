import { Body, Controller, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { MarkAppNotificationsReadDto } from './notifications.dto';
import { NotificationsService } from './notifications.service';

@Controller('notifications')
@UseGuards(AuthGuard('jwt'))
export class NotificationsController {
  constructor(private readonly service: NotificationsService) {}

  @Post('read')
  markRead(@Request() req: any, @Body() body: MarkAppNotificationsReadDto) {
    return this.service.markRead(req.user, body);
  }
}
