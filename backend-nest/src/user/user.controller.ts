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
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { avatarUploadOptions } from '../upload/image-upload.options';
import { userImportFileUploadOptions } from './user-import-file-upload.options';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import { UserService } from './user.service';
import { UserImportParserService } from './user-import-parser.service';
import {
  AdminResetPasswordDto,
  AdminAreaDto,
  AdminPersonnelCatalogDto,
  AdminRegionDto,
  AdminRoleDto,
  AdminStoreDto,
  AdminUserQueryDto,
  AdminUserDto,
  OrganizationNodeDto,
  SelectStoreDto,
  UpdateProfileDto,
} from './user.dto';

@Controller()
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class UserController {
  constructor(
    private readonly userService: UserService,
    private readonly userImportParser: UserImportParserService,
  ) {}

  @Get('stores')
  listStores(@Query('q') q?: string) {
    return this.userService.listStores(q);
  }

  @Get('users/me')
  getProfile(@Request() req: any) {
    return this.userService.getProfile(req.user.id);
  }

  @Patch('users/me')
  updateProfile(@Request() req: any, @Body() body: UpdateProfileDto) {
    return this.userService.updateProfile(req.user.id, body);
  }

  @Post('users/me/avatar')
  @Throttle({
    principal: { ttl: 60_000, limit: 10 },
  })
  @UseInterceptors(FileInterceptor('avatar', avatarUploadOptions))
  updateAvatar(
    @Request() req: any,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.userService.updateAvatar(req.user.id, file);
  }

  @Post('users/me/select-store')
  selectStore(@Request() req: any, @Body() body: SelectStoreDto) {
    return this.userService.selectStoreOnce(req.user.id, body.storeId);
  }

  @Get('admin/users')
  @RequireFeature(FEATURE_KEYS.ADMIN_USERS)
  listUsers(@Request() req: any, @Query() query: AdminUserQueryDto) {
    return this.userService.adminListUsers(req.user, query);
  }

  @Get('admin/users/scope-tree')
  @RequireFeature(FEATURE_KEYS.ADMIN_USERS)
  listUserScopeTree(@Request() req: any) {
    return this.userService.adminListUserScopeTree(req.user);
  }

  @Get('admin/policies/scope-tree')
  @RequireFeature(FEATURE_KEYS.ADMIN_POLICIES)
  listPolicyScopeTree(@Request() req: any) {
    return this.userService.adminListPolicyScopeTree(req.user);
  }

  @Post('admin/users')
  @RequireFeature(FEATURE_KEYS.ADMIN_USERS)
  createUser(@Request() req: any, @Body() body: AdminUserDto) {
    return this.userService.adminCreateUser(req.user, body);
  }

  @Post('admin/users/import')
  @RequireFeature(FEATURE_KEYS.ADMIN_USERS)
  @UseInterceptors(FileInterceptor('file', userImportFileUploadOptions))
  importUsers(@Request() req: any, @UploadedFile() file: Express.Multer.File) {
    const parsed = this.userImportParser.parse(file);
    return this.userService.adminImportUsers(req.user, parsed);
  }

  @Patch('admin/users/:id')
  @RequireFeature(FEATURE_KEYS.ADMIN_USERS)
  updateUser(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: AdminUserDto,
  ) {
    return this.userService.adminUpdateUser(req.user, id, body);
  }

  @Delete('admin/users/:id')
  @RequireFeature(FEATURE_KEYS.ADMIN_USERS)
  deleteUser(@Request() req: any, @Param('id') id: string) {
    return this.userService.adminDeleteUser(req.user, id);
  }

  @Post('admin/users/:id/reset-password')
  @RequireFeature(FEATURE_KEYS.ADMIN_USERS)
  resetUserPassword(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: AdminResetPasswordDto,
  ) {
    return this.userService.adminSetUserPassword(
      req.user,
      id,
      body.newPassword,
    );
  }

  @Get('admin/org-tree')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  listOrganizationTree(@Request() req: any) {
    return this.userService.adminListOrganizationTree(req.user);
  }

  @Post('admin/org-tree/nodes')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  createOrganizationNode(
    @Request() req: any,
    @Body() body: OrganizationNodeDto,
  ) {
    return this.userService.adminCreateOrganizationNode(req.user, body);
  }

  @Patch('admin/org-tree/nodes/:id')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  updateOrganizationNode(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: OrganizationNodeDto,
  ) {
    return this.userService.adminUpdateOrganizationNode(req.user, id, body);
  }

  @Delete('admin/org-tree/nodes/:id')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  deleteOrganizationNode(@Request() req: any, @Param('id') id: string) {
    return this.userService.adminDeleteOrganizationNode(req.user, id);
  }

  @Get('admin/roles')
  @RequireFeature(FEATURE_KEYS.ADMIN_ROLES)
  listRoles(@Request() req: any) {
    return this.userService.adminListRoles(req.user);
  }

  @Get('admin/departments')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  listDepartments(@Request() req: any) {
    return this.userService.adminListDepartments(req.user);
  }

  @Post('admin/departments')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  createDepartment(
    @Request() req: any,
    @Body() body: AdminPersonnelCatalogDto,
  ) {
    return this.userService.adminCreateDepartment(req.user, body);
  }

  @Patch('admin/departments/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  updateDepartment(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminPersonnelCatalogDto,
  ) {
    return this.userService.adminUpdateDepartment(req.user, code, body);
  }

  @Delete('admin/departments/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  deleteDepartment(@Request() req: any, @Param('code') code: string) {
    return this.userService.adminDeleteDepartment(req.user, code);
  }

  @Get('admin/job-roles')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  listJobRoles(@Request() req: any) {
    return this.userService.adminListJobRoles(req.user);
  }

  @Post('admin/job-roles')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  createJobRole(@Request() req: any, @Body() body: AdminPersonnelCatalogDto) {
    return this.userService.adminCreateJobRole(req.user, body);
  }

  @Patch('admin/job-roles/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  updateJobRole(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminPersonnelCatalogDto,
  ) {
    return this.userService.adminUpdateJobRole(req.user, code, body);
  }

  @Delete('admin/job-roles/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_PERSONNEL)
  deleteJobRole(@Request() req: any, @Param('code') code: string) {
    return this.userService.adminDeleteJobRole(req.user, code);
  }

  @Get('admin/regions')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  listRegions(@Request() req: any) {
    return this.userService.adminRetiredTreeApi(req.user, 'GET /admin/regions');
  }

  @Post('admin/regions')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  createRegion(@Request() req: any, @Body() body: AdminRegionDto) {
    return this.userService.adminRetiredTreeApi(
      req.user,
      'POST /admin/regions',
    );
  }

  @Patch('admin/regions/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  updateRegion(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminRegionDto,
  ) {
    return this.userService.adminRetiredTreeApi(
      req.user,
      'PATCH /admin/regions/:code',
    );
  }

  @Delete('admin/regions/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  deleteRegion(@Request() req: any, @Param('code') code: string) {
    return this.userService.adminRetiredTreeApi(
      req.user,
      'DELETE /admin/regions/:code',
    );
  }

  @Get('admin/areas')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  listAreas(@Request() req: any, @Query('regionCode') regionCode?: string) {
    return this.userService.adminRetiredTreeApi(req.user, 'GET /admin/areas');
  }

  @Post('admin/areas')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  createArea(@Request() req: any, @Body() body: AdminAreaDto) {
    return this.userService.adminRetiredTreeApi(req.user, 'POST /admin/areas');
  }

  @Patch('admin/areas/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  updateArea(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminAreaDto,
  ) {
    return this.userService.adminRetiredTreeApi(
      req.user,
      'PATCH /admin/areas/:code',
    );
  }

  @Delete('admin/areas/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  deleteArea(@Request() req: any, @Param('code') code: string) {
    return this.userService.adminRetiredTreeApi(
      req.user,
      'DELETE /admin/areas/:code',
    );
  }

  @Post('admin/roles')
  @RequireFeature(FEATURE_KEYS.ADMIN_ROLES)
  createRole(@Request() req: any, @Body() body: AdminRoleDto) {
    return this.userService.adminCreateRole(req.user, body);
  }

  @Patch('admin/roles/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_ROLES)
  updateRole(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminRoleDto,
  ) {
    return this.userService.adminUpdateRole(req.user, code, body);
  }

  @Delete('admin/roles/:code')
  @RequireFeature(FEATURE_KEYS.ADMIN_ROLES)
  deleteRole(@Request() req: any, @Param('code') code: string) {
    return this.userService.adminDeleteRole(req.user, code);
  }

  @Get('admin/stores')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  listAdminStores(@Request() req: any, @Query('q') q?: string) {
    return this.userService.adminRetiredTreeApi(req.user, 'GET /admin/stores');
  }

  @Post('admin/stores')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  createStore(@Request() req: any, @Body() body: AdminStoreDto) {
    return this.userService.adminRetiredTreeApi(req.user, 'POST /admin/stores');
  }

  @Patch('admin/stores/:storeId')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  updateStore(
    @Request() req: any,
    @Param('storeId') storeId: string,
    @Body() body: AdminStoreDto,
  ) {
    return this.userService.adminRetiredTreeApi(
      req.user,
      'PATCH /admin/stores/:storeId',
    );
  }

  @Delete('admin/stores/:storeId')
  @RequireFeature(FEATURE_KEYS.ADMIN_ORG_TREE)
  deleteStore(@Request() req: any, @Param('storeId') storeId: string) {
    return this.userService.adminRetiredTreeApi(
      req.user,
      'DELETE /admin/stores/:storeId',
    );
  }
}
