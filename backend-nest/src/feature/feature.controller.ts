import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FeatureGuard } from './feature.guard';
import { RequireFeature } from './feature.decorator';
import { FEATURE_KEYS } from './feature.constants';
import { AdminFeatureDto, AdminFeatureRuleDto } from './feature.dto';
import { FeatureService } from './feature.service';

@Controller()
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class FeatureController {
  constructor(private readonly featureService: FeatureService) {}

  @Get('features/me')
  getMyFeatures(@Request() req: any) {
    return this.featureService.resolveFeatureAccessMap(req.user);
  }

  @Get('admin/features')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  listFeatures(@Request() req: any) {
    return this.featureService.adminListFeatures(req.user);
  }

  @Post('admin/features')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  createFeature(@Request() req: any, @Body() body: AdminFeatureDto) {
    return this.featureService.adminCreateFeature(req.user, body);
  }

  @Patch('admin/features/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  updateFeature(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminFeatureDto,
  ) {
    return this.featureService.adminUpdateFeature(req.user, code, body);
  }

  @Delete('admin/features/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  deleteFeature(@Request() req: any, @Param('code') code: string) {
    return this.featureService.adminDeleteFeature(req.user, code);
  }

  @Get('admin/features/rules')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  listRules(@Request() req: any, @Query('featureCode') featureCode?: string) {
    return this.featureService.adminListRules(req.user, featureCode);
  }

  @Post('admin/features/rules')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  createRule(@Request() req: any, @Body() body: AdminFeatureRuleDto) {
    return this.featureService.adminCreateRule(req.user, body);
  }

  @Patch('admin/features/rules/:id')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  updateRule(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: AdminFeatureRuleDto,
  ) {
    return this.featureService.adminUpdateRule(req.user, id, body);
  }

  @Delete('admin/features/rules/:id')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEATURES)
  deleteRule(@Request() req: any, @Param('id') id: string) {
    return this.featureService.adminDeleteRule(req.user, id);
  }
}
