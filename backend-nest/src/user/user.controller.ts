import {
  Body,
  Controller,
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
  updateProfile(
    @Request() req: any,
    @Body() body: { firstName?: string; lastName?: string },
  ) {
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
  selectStore(@Request() req: any, @Body() body: { storeId?: string }) {
    return this.userService.selectStoreOnce(req.user.id, body.storeId ?? '');
  }

  @Get('admin/users')
  listUsers(@Request() req: any, @Query('q') q?: string) {
    return this.userService.adminListUsers(req.user, q);
  }

  @Post('admin/users')
  createUser(@Request() req: any, @Body() body: any) {
    return this.userService.adminCreateUser(req.user, body);
  }

  @Patch('admin/users/:id')
  updateUser(@Request() req: any, @Param('id') id: string, @Body() body: any) {
    return this.userService.adminUpdateUser(req.user, id, body);
  }
}
