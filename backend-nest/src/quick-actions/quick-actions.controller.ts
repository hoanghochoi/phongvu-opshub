import {
  Body,
  Controller,
  Get,
  Param,
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
  QuickActionsQueryDto,
  UpdateQuickActionLinksDto,
} from './quick-actions.dto';
import { QuickActionsService } from './quick-actions.service';

@Controller()
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class QuickActionsController {
  constructor(private readonly service: QuickActionsService) {}

  @Get('quick-actions')
  @RequireFeature(FEATURE_KEYS.QUICK_ACTIONS)
  getQuickActions(@Request() req: any, @Query() query: QuickActionsQueryDto) {
    return this.service.getQuickActions(req.user, query.storeCode);
  }

  @Get('admin/quick-action-links/stores')
  @RequireFeature(FEATURE_KEYS.ADMIN_QUICK_ACTION_CODES)
  getManagedStores(@Request() req: any) {
    return this.service.getManagedStores(req.user);
  }

  @Get('admin/quick-action-links')
  @RequireFeature(FEATURE_KEYS.ADMIN_QUICK_ACTION_CODES)
  getAdminLinks(@Request() req: any, @Query() query: QuickActionsQueryDto) {
    return this.service.getAdminLinks(req.user, query.storeCode);
  }

  @Put('admin/quick-action-links/:storeCode')
  @RequireFeature(FEATURE_KEYS.ADMIN_QUICK_ACTION_CODES)
  updateAdminLinks(
    @Request() req: any,
    @Param('storeCode') storeCode: string,
    @Body() body: UpdateQuickActionLinksDto,
  ) {
    return this.service.updateAdminLinks(req.user, storeCode, body);
  }
}
