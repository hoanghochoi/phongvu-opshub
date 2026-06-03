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
import { imageUploadOptions } from '../upload/image-upload.options';
import { UserService } from './user.service';
import {
  AdminResetPasswordDto,
  AdminRoleDto,
  AdminStoreDto,
  AdminUserDto,
  SelectStoreDto,
  UpdateProfileDto,
} from './user.dto';

@Controller()
@UseGuards(AuthGuard('jwt'))
export class UserController {
  constructor(private readonly userService: UserService) {}

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
  @UseInterceptors(FileInterceptor('avatar', imageUploadOptions))
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
  listUsers(@Request() req: any, @Query('q') q?: string) {
    return this.userService.adminListUsers(req.user, q);
  }

  @Post('admin/users')
  createUser(@Request() req: any, @Body() body: AdminUserDto) {
    return this.userService.adminCreateUser(req.user, body);
  }

  @Patch('admin/users/:id')
  updateUser(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: AdminUserDto,
  ) {
    return this.userService.adminUpdateUser(req.user, id, body);
  }
  @Post('admin/users/:id/reset-password')
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

  @Get('admin/roles')
  listRoles(@Request() req: any) {
    return this.userService.adminListRoles(req.user);
  }

  @Get('admin/departments')
  listDepartments(@Request() req: any) {
    return this.userService.adminListDepartments(req.user);
  }

  @Get('admin/job-roles')
  listJobRoles(@Request() req: any) {
    return this.userService.adminListJobRoles(req.user);
  }

  @Post('admin/roles')
  createRole(@Request() req: any, @Body() body: AdminRoleDto) {
    return this.userService.adminCreateRole(req.user, body);
  }

  @Patch('admin/roles/:code')
  updateRole(
    @Request() req: any,
    @Param('code') code: string,
    @Body() body: AdminRoleDto,
  ) {
    return this.userService.adminUpdateRole(req.user, code, body);
  }

  @Delete('admin/roles/:code')
  deleteRole(@Request() req: any, @Param('code') code: string) {
    return this.userService.adminDeleteRole(req.user, code);
  }

  @Get('admin/stores')
  listAdminStores(@Request() req: any, @Query('q') q?: string) {
    return this.userService.adminListStores(req.user, q);
  }

  @Post('admin/stores')
  createStore(@Request() req: any, @Body() body: AdminStoreDto) {
    return this.userService.adminCreateStore(req.user, body);
  }

  @Patch('admin/stores/:storeId')
  updateStore(
    @Request() req: any,
    @Param('storeId') storeId: string,
    @Body() body: AdminStoreDto,
  ) {
    return this.userService.adminUpdateStore(req.user, storeId, body);
  }

  @Delete('admin/stores/:storeId')
  deleteStore(@Request() req: any, @Param('storeId') storeId: string) {
    return this.userService.adminDeleteStore(req.user, storeId);
  }
}
