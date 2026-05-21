import { Controller, Get, Query } from '@nestjs/common';
import { AppVersionService } from './app-version.service';

@Controller('app-version')
export class AppVersionController {
  constructor(private readonly appVersionService: AppVersionService) {}

  @Get()
  getVersion(@Query('platform') platform?: string) {
    return this.appVersionService.getVersion(process.env, platform);
  }
}
