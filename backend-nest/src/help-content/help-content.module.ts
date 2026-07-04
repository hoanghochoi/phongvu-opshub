import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { UploadModule } from '../upload/upload.module';
import { HelpContentController } from './help-content.controller';
import { HelpContentDocsLoader } from './help-content.docs-loader';
import { HelpContentService } from './help-content.service';
import { OptionalJwtAuthGuard } from './optional-jwt-auth.guard';

@Module({
  imports: [PrismaModule, UploadModule],
  controllers: [HelpContentController],
  providers: [HelpContentDocsLoader, HelpContentService, OptionalJwtAuthGuard],
})
export class HelpContentModule {}
