import { Injectable, Logger, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FifoLogType } from '@prisma/client';

@Injectable()
export class FifoLogService {
    private readonly logger = new Logger(FifoLogService.name);

    constructor(private prisma: PrismaService) { }

    // -------------------------------------------------------
    // Create a FIFO log entry
    // -------------------------------------------------------
    async createLog(
        type: FifoLogType,
        query: string,
        result: string | null,
        resultJson: any,
        userEmail: string,
    ) {
        try {
            const user = await this.prisma.user.findUnique({
                where: { email: userEmail },
            });

            if (!user) {
                this.logger.warn(`User not found for logging: ${userEmail}`);
                return null;
            }

            const log = await this.prisma.fifoLog.create({
                data: {
                    type,
                    query,
                    result,
                    resultJson: resultJson ?? undefined,
                    userId: user.id,
                },
            });

            this.logger.log(`FIFO log created: ${type} by ${userEmail} — "${query}"`);
            return log;
        } catch (error) {
            this.logger.error(`Failed to create FIFO log: ${error}`);
            return null; // Don't break the main flow
        }
    }

    // -------------------------------------------------------
    // Get user's own logs
    // -------------------------------------------------------
    async getMyLogs(userEmail: string, type?: FifoLogType, limit = 10) {
        const user = await this.prisma.user.findUnique({
            where: { email: userEmail },
        });

        if (!user) return [];

        return this.prisma.fifoLog.findMany({
            where: {
                userId: user.id,
                ...(type ? { type } : {}),
            },
            orderBy: { createdAt: 'desc' },
            take: limit,
        });
    }

    // -------------------------------------------------------
    // Admin: get logs with role-based filtering
    // SUPER_ADMIN: sees all users
    // ADMIN: sees only users in the same store (branch)
    // -------------------------------------------------------
    async getAdminLogs(
        adminEmail: string,
        type?: FifoLogType,
        page = 1,
        limit = 20,
        filterUserEmail?: string,
        search?: string,
    ) {
        const admin = await this.prisma.user.findUnique({
            where: { email: adminEmail },
            include: { store: true },
        });

        if (!admin) throw new ForbiddenException('User not found');

        if (admin.role !== 'SUPER_ADMIN' && admin.role !== 'ADMIN') {
            throw new ForbiddenException('Không có quyền xem lịch sử');
        }

        // Build where clause
        const where: any = {};
        if (type) where.type = type;

        // Search by query (serial/SKU/BIN) — search in both query field and resultJson
        if (search) {
            where.OR = [
                { query: { contains: search, mode: 'insensitive' } },
                { result: { contains: search, mode: 'insensitive' } },
                { resultJson: { string_contains: search } },
            ];
        }

        // ADMIN: only see users in same store
        if (admin.role === 'ADMIN') {
            if (!admin.storeId) {
                return { data: [], total: 0, page, limit };
            }
            const storeUsers = await this.prisma.user.findMany({
                where: { storeId: admin.storeId },
                select: { id: true },
            });
            where.userId = { in: storeUsers.map(u => u.id) };
        }

        // Filter by specific user email
        if (filterUserEmail) {
            const targetUser = await this.prisma.user.findUnique({
                where: { email: filterUserEmail },
            });
            if (targetUser) {
                where.userId = targetUser.id;
            }
        }

        const skip = (page - 1) * limit;

        const [data, total] = await Promise.all([
            this.prisma.fifoLog.findMany({
                where,
                include: {
                    user: {
                        select: {
                            email: true,
                            firstName: true,
                            lastName: true,
                            store: { select: { storeId: true, storeName: true } },
                        },
                    },
                },
                orderBy: { createdAt: 'desc' },
                skip,
                take: limit,
            }),
            this.prisma.fifoLog.count({ where }),
        ]);

        return { data, total, page, limit };
    }
}
