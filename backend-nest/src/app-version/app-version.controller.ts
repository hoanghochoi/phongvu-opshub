import { Controller, Get } from '@nestjs/common';
import { AppVersionService } from './app-version.service';

@Controller('app-version')
export class AppVersionController {
  constructor(private readonly appVersionService: AppVersionService) {}

  @Get()
  getVersion() {
    return this.appVersionService.getVersion();
  }
}
