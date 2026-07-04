import { Controller, Get, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { GetHomeSummaryQueryDto } from './home-summary.dto';
import { HomeSummaryService } from './home-summary.service';

@Controller('home')
@UseGuards(AuthGuard('jwt'))
export class HomeSummaryController {
  constructor(private readonly service: HomeSummaryService) {}

  @Get('summary')
  summary(@Request() req: any, @Query() query: GetHomeSummaryQueryDto) {
    return this.service.getSummary(req.user, query);
  }

  @Get('summary/scopes')
  scopeOptions(@Request() req: any) {
    return this.service.listScopeOptions(req.user);
  }
}
