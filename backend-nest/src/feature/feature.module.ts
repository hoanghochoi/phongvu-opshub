import { Global, Module } from '@nestjs/common';
import { AccessChangeModule } from '../auth/access-change.module';
import { PolicyModule } from '../policy/policy.module';
import { PrismaModule } from '../prisma/prisma.module';
import { FeatureController } from './feature.controller';
import { FeatureGuard } from './feature.guard';
import { FeatureService } from './feature.service';

@Global()
@Module({
  imports: [PrismaModule, PolicyModule, AccessChangeModule],
  controllers: [FeatureController],
  providers: [FeatureService, FeatureGuard],
  exports: [FeatureService, FeatureGuard],
})
export class FeatureModule {}
