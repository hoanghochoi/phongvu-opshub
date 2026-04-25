import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { UserService } from './user.service';
import { PrismaModule } from '../prisma/prisma.module';

@Module({
  imports: [PrismaModule, ScheduleModule.forRoot()],
  providers: [UserService],
  exports: [UserService],
})
export class UserModule {}
