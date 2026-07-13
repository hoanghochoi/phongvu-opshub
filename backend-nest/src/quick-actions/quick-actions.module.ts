import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { QuickActionsController } from './quick-actions.controller';
import { QuickActionsService } from './quick-actions.service';

@Module({
  imports: [PrismaModule],
  controllers: [QuickActionsController],
  providers: [QuickActionsService],
})
export class QuickActionsModule {}
