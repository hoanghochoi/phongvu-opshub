import { Global, Module } from '@nestjs/common';
import { AccessChangeModule } from '../auth/access-change.module';
import { PrismaModule } from '../prisma/prisma.module';
import { PolicyController } from './policy.controller';
import { PolicyService } from './policy.service';

@Global()
@Module({
  imports: [PrismaModule, AccessChangeModule],
  controllers: [PolicyController],
  providers: [PolicyService],
  exports: [PolicyService],
})
export class PolicyModule {}
