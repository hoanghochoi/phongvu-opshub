import { Module } from '@nestjs/common';
import { UploadController } from './upload.controller';
import { UploadService } from './upload.service';
import { PrismaModule } from '../prisma/prisma.module';
import { PrivateMediaController } from './private-media.controller';
import { PrivateMediaService } from './private-media.service';

@Module({
  imports: [PrismaModule],
  controllers: [UploadController, PrivateMediaController],
  providers: [UploadService, PrivateMediaService],
  exports: [UploadService, PrivateMediaService],
})
export class UploadModule {}
