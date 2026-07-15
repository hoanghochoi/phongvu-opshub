import { Controller, Get, Request, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { NotificationFeedService } from './notification-feed.service';

@Controller('notifications')
@UseGuards(AuthGuard('jwt'))
export class NotificationFeedController {
  constructor(private readonly service: NotificationFeedService) {}

  @Get('feed')
  load(@Request() request: any) {
    return this.service.load(request.user);
  }
}
