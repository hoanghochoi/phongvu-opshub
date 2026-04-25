import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { WarrantyModule } from './warranty/warranty.module';
import { RedisModule } from './redis/redis.module';
import { InventoryModule } from './inventory/inventory.module';
import { SortModule } from './sort/sort.module';
import { FeedbackModule } from './feedback/feedback.module';
import { UploadModule } from './upload/upload.module';
import { UserModule } from './user/user.module';
import { FifoLogModule } from './fifo-log/fifo-log.module';

@Module({
  imports: [PrismaModule, AuthModule, WarrantyModule, RedisModule, InventoryModule, SortModule, FeedbackModule, UploadModule, UserModule, FifoLogModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
