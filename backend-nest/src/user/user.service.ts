import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { BigQuery } from '@google-cloud/bigquery';
import { PrismaService } from '../prisma/prisma.service';
import { Cron, CronExpression } from '@nestjs/schedule';

@Injectable()
export class UserService implements OnModuleInit {
    private readonly logger = new Logger(UserService.name);
    private bigquery: BigQuery;

    constructor(private prisma: PrismaService) {
        const projectId = process.env.BIGQUERY_PROJECT_ID;
        const keyFilename = process.env.BIGQUERY_KEY_FILE;

        this.bigquery = new BigQuery({
            projectId,
            ...(keyFilename ? { keyFilename } : {}),
        });
    }

    onModuleInit() {
        this.syncUsersFromBigQuery();
    }

    // -------------------------------------------------------
    // Sync every hour from BigQuery → Postgres
    // -------------------------------------------------------
    @Cron(CronExpression.EVERY_HOUR)
    async syncUsersFromBigQuery() {
        this.logger.log('Starting User sync from BigQuery...');
        try {
            const projectId = process.env.BIGQUERY_PROJECT_ID;
            const datasetId = process.env.BIGQUERY_USER_DATASET_ID;
            const tableId = process.env.BIGQUERY_USER_TABLE_ID;

            if (!projectId || !datasetId || !tableId) {
                this.logger.warn(
                    'BIGQUERY_USER_DATASET_ID / BIGQUERY_USER_TABLE_ID not set, skipping user sync',
                );
                return;
            }

            const query = `SELECT * FROM \`${projectId}.${datasetId}.${tableId}\``;
            const [rows] = await this.bigquery.query({ query });

            this.logger.log(`Fetched ${rows.length} user rows from BigQuery`);

            if (rows.length === 0) {
                this.logger.warn('No user rows found in BigQuery table');
                return;
            }

            let syncedCount = 0;
            let storeCreatedCount = 0;

            for (const row of rows) {
                const email = String(row.email || '').trim().toLowerCase();
                if (!email) continue;

                const firstName = String(row.first_name || '').trim();
                const lastName = String(row.last_name || '').trim();
                const role = this.parseRole(String(row.role || 'STAFF').trim().toUpperCase());
                const branchId = String(row.branch_id || '').trim();
                const branchName = String(row.branch_name || '').trim();
                const status = String(row.status || 'yes').trim().toLowerCase();

                // Resolve Store: find or create by branchId
                let storeUuid: string | null = null;
                if (branchId) {
                    let store = await this.prisma.store.findUnique({
                        where: { storeId: branchId },
                    });

                    if (!store) {
                        // Auto-create Store
                        store = await this.prisma.store.create({
                            data: {
                                storeId: branchId,
                                storeName: branchName || branchId,
                            },
                        });
                        storeCreatedCount++;
                        this.logger.log(`Created new Store: ${branchId} - ${branchName}`);
                    } else if (branchName && store.storeName !== branchName) {
                        // Update store name if changed
                        await this.prisma.store.update({
                            where: { storeId: branchId },
                            data: { storeName: branchName },
                        });
                    }

                    storeUuid = store.id;
                }

                // Upsert User
                await this.prisma.user.upsert({
                    where: { email },
                    update: {
                        firstName: firstName || undefined,
                        lastName: lastName || undefined,
                        role,
                        status,
                        storeId: storeUuid,
                    },
                    create: {
                        email,
                        password: '', // Not used for Google login
                        firstName: firstName || email.split('@')[0],
                        lastName: lastName || null,
                        role,
                        status,
                        storeId: storeUuid,
                    },
                });

                syncedCount++;
            }

            this.logger.log(
                `User sync complete: ${syncedCount} users synced, ${storeCreatedCount} new stores created`,
            );
        } catch (error) {
            this.logger.error('User sync from BigQuery failed:', error);
        }
    }

    // -------------------------------------------------------
    // Parse role string to valid Prisma Role enum
    // -------------------------------------------------------
    private parseRole(roleStr: string): 'SUPER_ADMIN' | 'ADMIN' | 'MANAGER' | 'STAFF' {
        const validRoles = ['SUPER_ADMIN', 'ADMIN', 'MANAGER', 'STAFF'] as const;
        if (validRoles.includes(roleStr as any)) {
            return roleStr as typeof validRoles[number];
        }
        return 'STAFF'; // Default
    }
}
