import { Controller, Get, Query, UseGuards, Req } from '@nestjs/common';
import { FifoLogService } from './fifo-log.service';
import { AuthGuard } from '@nestjs/passport';
import { FifoLogType } from '@prisma/client';

@Controller('fifo-logs')
@UseGuards(AuthGuard('jwt'))
export class FifoLogController {
    constructor(private readonly fifoLogService: FifoLogService) { }

    // GET /fifo-logs/my?type=FIFO_CHECK&limit=10
    @Get('my')
    async getMyLogs(
        @Req() req: any,
        @Query('type') type?: string,
        @Query('limit') limit?: string,
    ) {
        const userEmail = req.user.email;
        const logType = type as FifoLogType | undefined;
        const logLimit = limit ? parseInt(limit, 10) : 10;

        return this.fifoLogService.getMyLogs(userEmail, logType, logLimit);
    }

    // GET /fifo-logs/admin?type=FIFO_CHECK&page=1&limit=20&user=email&search=serial
    @Get('admin')
    async getAdminLogs(
        @Req() req: any,
        @Query('type') type?: string,
        @Query('page') page?: string,
        @Query('limit') limit?: string,
        @Query('user') filterUser?: string,
        @Query('search') search?: string,
    ) {
        const adminEmail = req.user.email;
        const logType = type as FifoLogType | undefined;
        const logPage = page ? parseInt(page, 10) : 1;
        const logLimit = limit ? parseInt(limit, 10) : 20;

        return this.fifoLogService.getAdminLogs(
            adminEmail,
            logType,
            logPage,
            logLimit,
            filterUser,
            search,
        );
    }
}
