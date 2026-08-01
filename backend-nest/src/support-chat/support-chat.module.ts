import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { UploadModule } from '../upload/upload.module';
import { SupportChatController } from './support-chat.controller';
import { SupportChatOutboxWorker } from './support-chat-outbox.worker';
import { SupportChatService } from './support-chat.service';
import { SupportChatRetentionWorker } from './support-chat-retention.worker';
import { SupportChatUploadCleanupInterceptor } from './support-chat-upload-cleanup.interceptor';
import {
  SupportChatAdminUploadGuard,
  SupportChatRequesterUploadGuard,
} from './support-chat-upload.guard';

@Module({
  imports: [PrismaModule, RedisModule, UploadModule],
  controllers: [SupportChatController],
  providers: [
    SupportChatService,
    SupportChatOutboxWorker,
    SupportChatRetentionWorker,
    SupportChatUploadCleanupInterceptor,
    SupportChatRequesterUploadGuard,
    SupportChatAdminUploadGuard,
  ],
  exports: [SupportChatService],
})
export class SupportChatModule {}
