import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { RedisModule } from '../redis/redis.module';
import { AccessChangeService } from './access-change.service';

@Module({
  imports: [PrismaModule, RedisModule],
  providers: [AccessChangeService],
  exports: [AccessChangeService],
})
export class AccessChangeModule {}
