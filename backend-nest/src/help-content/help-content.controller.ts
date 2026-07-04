import {
  Body,
  Controller,
  Get,
  Post,
  Param,
  Patch,
  Request,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
import { imageUploadOptions } from '../upload/image-upload.options';
import {
  CreateHelpContentPageDto,
  SeedHelpContentDto,
  UploadHelpContentAssetDto,
  UpdateHelpContentPageDto,
} from './help-content.dto';
import { HelpContentService } from './help-content.service';
import { OptionalJwtAuthGuard } from './optional-jwt-auth.guard';

@Controller()
export class HelpContentController {
  constructor(private readonly helpContentService: HelpContentService) {}

  @Get('help-content/public')
  @UseGuards(OptionalJwtAuthGuard)
  getPublicContent(@Request() req: any) {
    return this.helpContentService.getPublicContent(req.user);
  }

  @Get('admin/help-content/pages')
  @UseGuards(AuthGuard('jwt'))
  getAdminPages(@Request() req: any) {
    return this.helpContentService.getAdminPages(req.user);
  }

  @Post('admin/help-content/pages')
  @UseGuards(AuthGuard('jwt'))
  createPage(@Request() req: any, @Body() body: CreateHelpContentPageDto) {
    return this.helpContentService.createPage(req.user, body);
  }

  @Patch('admin/help-content/pages/:key')
  @UseGuards(AuthGuard('jwt'))
  updatePage(
    @Request() req: any,
    @Param('key') key: string,
    @Body() body: UpdateHelpContentPageDto,
  ) {
    return this.helpContentService.updatePage(req.user, key, body);
  }

  @Post('admin/help-content/seed-from-docs')
  @UseGuards(AuthGuard('jwt'))
  seedFromDocs(@Request() req: any, @Body() body: SeedHelpContentDto) {
    return this.helpContentService.seedFromDocs(req.user, body);
  }

  @Post('admin/help-content/assets')
  @UseGuards(AuthGuard('jwt'))
  @UseInterceptors(
    FileInterceptor('image', {
      ...imageUploadOptions,
      limits: {
        ...imageUploadOptions.limits,
        files: 1,
      },
    }),
  )
  uploadAsset(
    @Request() req: any,
    @Body() body: UploadHelpContentAssetDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.helpContentService.uploadAsset(req.user, body, file);
  }
}
