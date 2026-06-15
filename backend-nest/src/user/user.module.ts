import { Module } from '@nestjs/common';
import { UserService } from './user.service';
import { UserController } from './user.controller';
import { PrismaModule } from '../prisma/prisma.module';
import { UploadModule } from '../upload/upload.module';
import { AuthModule } from '../auth/auth.module';
import { UserImportParserService } from './user-import-parser.service';

@Module({
  imports: [PrismaModule, UploadModule, AuthModule],
  controllers: [UserController],
  providers: [UserService, UserImportParserService],
  exports: [UserService],
})
export class UserModule {}
