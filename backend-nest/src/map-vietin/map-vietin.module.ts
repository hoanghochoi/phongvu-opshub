import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { MapVietinController } from './map-vietin.controller';
import { MapVietinService } from './map-vietin.service';

@Module({
  imports: [PrismaModule],
  controllers: [MapVietinController],
  providers: [MapVietinService],
})
export class MapVietinModule {}
