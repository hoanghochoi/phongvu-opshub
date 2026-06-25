import { Global, Module } from '@nestjs/common';
import { PolicyModule } from '../policy/policy.module';
import { PrismaModule } from '../prisma/prisma.module';
import { FeatureController } from './feature.controller';
import { FeatureGuard } from './feature.guard';
import { FeatureService } from './feature.service';

@Global()
@Module({
  imports: [PrismaModule, PolicyModule],
  controllers: [FeatureController],
  providers: [FeatureService, FeatureGuard],
  exports: [FeatureService, FeatureGuard],
})
export class FeatureModule {}
