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
  Optional,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import {
  AdminPolicyDto,
  AdminPolicyRuleBatchDto,
  AdminPolicyRuleDto,
  AdminSettingDto,
} from './policy.dto';
import { PolicyService } from './policy.service';
import { AuthContextService } from '../auth/auth-context.service';

@Controller()
@UseGuards(AuthGuard('jwt'))
export class PolicyController {
  constructor(
    private readonly policyService: PolicyService,
    @Optional() private readonly authContextService?: AuthContextService,
  ) {}

  @Get('policies/me')
  getMyPolicies(@Request() req: any) {
    return this.authContextService
      ? this.authContextService
          .getContext(req.user)
          .then((context) => context.policyAccess)
      : this.policyService.resolvePolicyAccessMap(req.user);
  }

  @Get('admin/policies')
  listPolicies(@Request() req: any) {
    return this.policyService.adminListPolicies(req.user);
  }

  @Post('admin/policies')
  createPolicy(@Request() req: any, @Body() body: AdminPolicyDto) {
    return this.policyService.adminCreatePolicy(req.user, body);
  }

  @Patch('admin/policies/:code')
  updatePolicy(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminPolicyDto,
  ) {
    return this.policyService.adminUpdatePolicy(req.user, code, body);
  }

  @Delete('admin/policies/:code')
  deletePolicy(@Request() req: any, @Param('code') code: string) {
    return this.policyService.adminDeletePolicy(req.user, code);
  }

  @Get('admin/policies/rules')
  listPolicyRules(
    @Request() req: any,
    @Query('policyCode') policyCode?: string,
  ) {
    return this.policyService.adminListRules(req.user, policyCode);
  }

  @Post('admin/policies/rules')
  createPolicyRule(@Request() req: any, @Body() body: AdminPolicyRuleDto) {
    return this.policyService.adminCreateRule(req.user, body);
  }

  @Post('admin/policies/rules/batch')
  createPolicyRules(
    @Request() req: any,
    @Body() body: AdminPolicyRuleBatchDto,
  ) {
    return this.policyService.adminCreateRules(req.user, body);
  }

  @Patch('admin/policies/rules/:id')
  updatePolicyRule(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: AdminPolicyRuleDto,
  ) {
    return this.policyService.adminUpdateRule(req.user, id, body);
  }

  @Delete('admin/policies/rules/:id')
  deletePolicyRule(@Request() req: any, @Param('id') id: string) {
    return this.policyService.adminDeleteRule(req.user, id);
  }

  @Get('admin/settings')
  listSettings(@Request() req: any) {
    return this.policyService.adminListSettings(req.user);
  }

  @Post('admin/settings')
  createSetting(@Request() req: any, @Body() body: AdminSettingDto) {
    return this.policyService.adminCreateSetting(req.user, body);
  }

  @Patch('admin/settings/:key')
  updateSetting(
    @Request() req: any,
    @Param('key') key: string,
    @Body() body: AdminSettingDto,
  ) {
    return this.policyService.adminUpdateSetting(req.user, key, body);
  }
}
