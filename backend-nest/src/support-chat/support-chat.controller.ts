import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Request,
  UploadedFiles,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FilesInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { supportChatImageUploadOptions } from '../upload/image-upload.options';
import {
  ListSupportConversationsQueryDto,
  ResolveSupportConversationDto,
  SendSupportImageMessageDto,
  SendSupportTextMessageDto,
  SupportMessagePageQueryDto,
} from './support-chat.dto';
import { SupportChatService } from './support-chat.service';
import { SupportChatUploadCleanupInterceptor } from './support-chat-upload-cleanup.interceptor';
import {
  SupportChatAdminUploadGuard,
  SupportChatRequesterUploadGuard,
} from './support-chat-upload.guard';

@Controller('support-chat')
@UseGuards(AuthGuard('jwt'))
export class SupportChatController {
  constructor(private readonly service: SupportChatService) {}

  @Get('me')
  getMine(@Request() request: any, @Query() query: SupportMessagePageQueryDto) {
    return this.service.getRequesterConversation(request.user, query);
  }

  @Post('me/messages')
  @Throttle({ principal: { ttl: 60_000, limit: 30 } })
  sendMine(@Request() request: any, @Body() body: SendSupportTextMessageDto) {
    return this.service.sendRequesterText(request.user, body);
  }

  @Post('me/image-messages')
  @Throttle({ principal: { ttl: 60_000, limit: 6 } })
  @UseGuards(SupportChatRequesterUploadGuard)
  @UseInterceptors(
    SupportChatUploadCleanupInterceptor,
    FilesInterceptor('images', 4, supportChatImageUploadOptions),
  )
  sendMineImages(
    @Request() request: any,
    @Body() body: SendSupportImageMessageDto,
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    return this.service.sendRequesterImages(request.user, body, files || []);
  }

  @Post('me/read')
  markMineRead(@Request() request: any) {
    return this.service.markRequesterRead(request.user);
  }

  @Get('admin/conversations')
  listAdmin(
    @Request() request: any,
    @Query() query: ListSupportConversationsQueryDto,
  ) {
    return this.service.listAdminConversations(request.user, query);
  }

  @Get('admin/conversations/:id')
  getAdmin(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Query() query: SupportMessagePageQueryDto,
  ) {
    return this.service.getAdminConversation(request.user, id, query);
  }

  @Post('admin/conversations/:id/claim')
  claim(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.claim(request.user, id);
  }

  @Post('admin/conversations/:id/release')
  release(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.release(request.user, id);
  }

  @Post('admin/conversations/:id/takeover')
  takeover(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.takeover(request.user, id);
  }

  @Post('admin/conversations/:id/resolve')
  resolve(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body() body: ResolveSupportConversationDto,
  ) {
    return this.service.resolve(request.user, id, body);
  }

  @Post('admin/conversations/:id/read')
  markAdminRead(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.markAdminRead(request.user, id);
  }

  @Post('admin/conversations/:id/messages')
  @Throttle({ principal: { ttl: 60_000, limit: 30 } })
  sendAdmin(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body() body: SendSupportTextMessageDto,
  ) {
    return this.service.sendAdminText(request.user, id, body);
  }

  @Post('admin/conversations/:id/image-messages')
  @Throttle({ principal: { ttl: 60_000, limit: 6 } })
  @UseGuards(SupportChatAdminUploadGuard)
  @UseInterceptors(
    SupportChatUploadCleanupInterceptor,
    FilesInterceptor('images', 4, supportChatImageUploadOptions),
  )
  sendAdminImages(
    @Request() request: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body() body: SendSupportImageMessageDto,
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    return this.service.sendAdminImages(request.user, id, body, files || []);
  }
}
