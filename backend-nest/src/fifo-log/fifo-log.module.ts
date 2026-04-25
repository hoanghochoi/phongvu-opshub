import { Module } from '@nestjs/common';
import { FifoLogController } from './fifo-log.controller';
import { FifoLogService } from './fifo-log.service';
import { PrismaModule } from '../prisma/prisma.module';

@Module({
    imports: [PrismaModule],
    controllers: [FifoLogController],
    providers: [FifoLogService],
    exports: [FifoLogService],
})
export class FifoLogModule { }
