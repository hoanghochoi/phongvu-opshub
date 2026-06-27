import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  AppNotificationSource,
  MarkAppNotificationsReadDto,
} from './notifications.dto';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async markRead(user: any, input: MarkAppNotificationsReadDto) {
    const startedAt = Date.now();
    const userId = String(user?.id || '').trim();
    const source = input.source;
    const ids = this.cleanIds(input.ids);
    this.logger.log(
      `App notification mark-read started: userId=${this.safeUserId(userId)} source=${source} count=${ids.length}`,
    );
    if (!userId || ids.length === 0) {
      this.logger.warn(
        `App notification mark-read skipped: userId=${this.safeUserId(userId)} source=${source} count=${ids.length}`,
      );
      return { source, count: 0 };
    }

    const readAt = new Date();
    try {
      await this.prisma.$transaction(
        ids.map((notificationId) =>
          this.prisma.appNotificationReadReceipt.upsert({
            where: {
              userId_source_notificationId: {
                userId,
                source,
                notificationId,
              },
            },
            create: {
              userId,
              source,
              notificationId,
              readAt,
            },
            update: { readAt },
          }),
        ),
      );
      this.logger.log(
        `App notification mark-read succeeded: userId=${this.safeUserId(userId)} source=${source} count=${ids.length} durationMs=${Date.now() - startedAt}`,
      );
      return { source, count: ids.length, readAt: readAt.toISOString() };
    } catch (error) {
      this.logger.error(
        `App notification mark-read failed: userId=${this.safeUserId(userId)} source=${source} count=${ids.length} durationMs=${Date.now() - startedAt} error=${this.safeError(error)}`,
      );
      throw error;
    }
  }

  async readAtByNotificationId(
    user: any,
    source: AppNotificationSource,
    ids: string[],
  ) {
    const userId = String(user?.id || '').trim();
    const cleanIds = this.cleanIds(ids);
    if (!userId || cleanIds.length === 0) return new Map<string, Date>();
    const rows = await this.prisma.appNotificationReadReceipt.findMany({
      where: {
        userId,
        source,
        notificationId: { in: cleanIds },
      },
      select: { notificationId: true, readAt: true },
    });
    return new Map(rows.map((row) => [row.notificationId, row.readAt]));
  }

  private cleanIds(ids: string[] = []) {
    const seen = new Set<string>();
    const clean: string[] = [];
    for (const raw of ids) {
      const id = String(raw || '').trim();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      clean.push(id);
    }
    return clean;
  }

  private safeUserId(userId: string) {
    return userId || 'missing';
  }

  private safeError(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}
