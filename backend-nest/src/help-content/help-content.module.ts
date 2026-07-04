import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { HelpContentController } from './help-content.controller';
import { HelpContentDocsLoader } from './help-content.docs-loader';
import { HelpContentService } from './help-content.service';

@Module({
  imports: [PrismaModule],
  controllers: [HelpContentController],
  providers: [HelpContentDocsLoader, HelpContentService],
})
export class HelpContentModule {}
