import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import {
  CreateHelpContentPageDto,
  SeedHelpContentDto,
  UpdateHelpContentPageDto,
} from './help-content.dto';
import { HelpContentService } from './help-content.service';

@Controller()
export class HelpContentController {
  constructor(private readonly helpContentService: HelpContentService) {}

  @Get('help-content/public')
  getPublicContent() {
    return this.helpContentService.getPublicContent();
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
}
