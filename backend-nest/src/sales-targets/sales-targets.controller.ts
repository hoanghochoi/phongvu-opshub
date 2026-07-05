import {
  Body,
  Controller,
  Get,
  Put,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import {
  ListSalesTargetsDto,
  UpdateSalesTargetsDto,
} from './sales-targets.dto';
import { SalesTargetsService } from './sales-targets.service';

@Controller('admin/sales-targets')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
@RequireFeature(FEATURE_KEYS.ADMIN_SALES_TARGETS)
export class SalesTargetsController {
  constructor(private readonly service: SalesTargetsService) {}

  @Get()
  list(@Request() req: any, @Query() query: ListSalesTargetsDto) {
    return this.service.list(req.user, query.month);
  }

  @Put('batch')
  updateBatch(@Request() req: any, @Body() body: UpdateSalesTargetsDto) {
    return this.service.updateBatch(req.user, body);
  }
}
