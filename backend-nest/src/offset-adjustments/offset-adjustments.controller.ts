import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Patch,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import {
  CompleteOffsetAdjustmentDto,
  CreateOffsetAdjustmentDto,
  ListOffsetAdjustmentsDto,
  RejectOffsetAdjustmentDto,
  ResubmitOffsetAdjustmentDto,
} from './offset-adjustments.dto';
import { OffsetAdjustmentsService } from './offset-adjustments.service';

@Controller('offset-adjustments')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
@RequireFeature(FEATURE_KEYS.OFFSET_ADJUSTMENTS)
export class OffsetAdjustmentsController {
  constructor(private readonly service: OffsetAdjustmentsService) {}

  @Get()
  list(@Request() req: any, @Query() query: ListOffsetAdjustmentsDto) {
    return this.service.list(req.user, query);
  }

  @Post()
  create(@Request() req: any, @Body() body: CreateOffsetAdjustmentDto) {
    return this.service.create(req.user, body);
  }

  @Get(':id')
  detail(@Request() req: any, @Param('id') id: string) {
    return this.service.detail(req.user, id);
  }

  @Patch(':id/resubmit')
  resubmit(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: ResubmitOffsetAdjustmentDto,
  ) {
    return this.service.resubmit(req.user, id, body);
  }

  @Post(':id/complete')
  complete(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: CompleteOffsetAdjustmentDto,
  ) {
    return this.service.complete(req.user, id, body);
  }

  @Post(':id/reject')
  reject(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: RejectOffsetAdjustmentDto,
  ) {
    return this.service.reject(req.user, id, body);
  }
}
