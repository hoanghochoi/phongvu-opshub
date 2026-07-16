import { Injectable, Logger } from '@nestjs/common';
import { buildRealtimeRedisEnvelope } from '../common/realtime-event';
import { safeLogError } from '../common/log-sanitizer';
import {
  clearOrganizationTreeCache,
  getOrganizationTree,
} from '../common/organization-tree-cache';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

const ACCESS_CHANGED_CHANNEL = 'ACCESS_CHANGED';
const ACCESS_CHANGED_EVENT_TYPE = 'ACCESS_CHANGED';
const MAX_RECIPIENTS_PER_EVENT = 500;

@Injectable()
export class AccessChangeService {
  private readonly logger = new Logger(AccessChangeService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async publishForUserIds(userIds: unknown[], reason: string) {
    return this.publishRecipients(this.normalizeIds(userIds), reason);
  }

  async publishForOrganizationNodeIds(
    organizationNodeIds: unknown[],
    reason: string,
  ) {
    const anchorIds = this.normalizeIds(organizationNodeIds);
    if (anchorIds.length === 0) {
      this.logger.debug(
        `Access change publish skipped: reason=${this.normalizeReason(reason)} source=organization_nodes recipientCount=0`,
      );
      return { recipientCount: 0, eventCount: 0 };
    }

    try {
      // The source mutation has already committed when this method is called.
      // The access-version increment is performed by the database trigger in
      // that same source transaction; this step only resolves post-commit
      // realtime recipients. Reuse the short-lived tree cache so an admin
      // change does not scan the whole organization table on every event.
      const nodes = await getOrganizationTree(this.prisma);
      const impactedNodeIds = this.descendantNodeIds(nodes, anchorIds);
      const users = await this.prisma.user.findMany({
        where: {
          OR: [
            { organizationNodeId: { in: impactedNodeIds } },
            {
              organizationAssignments: {
                some: {
                  isActive: true,
                  organizationNodeId: { in: impactedNodeIds },
                },
              },
            },
          ],
        },
        select: { id: true },
      });
      return this.publishRecipients(
        users.map((user) => user.id),
        reason,
      );
    } catch (error) {
      return this.recipientLookupFailed(reason, 'organization_nodes', error);
    }
  }

  async publishForAllUsers(reason: string) {
    try {
      // Organization topology consumers keep a process-local tree cache. The
      // invalidation is deliberately after the source transaction has
      // returned, so a failed mutation cannot evict a still-valid snapshot.
      clearOrganizationTreeCache(this.prisma);
      const users = await this.prisma.user.findMany({
        where: { status: { not: 'no' } },
        select: { id: true },
      });
      return this.publishRecipients(
        users.map((user) => user.id),
        reason,
      );
    } catch (error) {
      return this.recipientLookupFailed(reason, 'all_users', error);
    }
  }

  private async publishRecipients(userIds: string[], reasonInput: string) {
    const recipientUserIds = this.normalizeIds(userIds);
    const reason = this.normalizeReason(reasonInput);
    if (recipientUserIds.length === 0) {
      this.logger.debug(
        `Access change publish skipped: reason=${reason} recipientCount=0`,
      );
      return { recipientCount: 0, eventCount: 0 };
    }

    const startedAt = Date.now();
    const chunks = this.chunk(recipientUserIds, MAX_RECIPIENTS_PER_EVENT);
    this.logger.log(
      `Access change publish started: reason=${reason} recipientCount=${recipientUserIds.length} eventCount=${chunks.length}`,
    );
    let failedEventCount = 0;
    for (const recipientChunk of chunks) {
      try {
        await this.redis.publishMessageOrThrow(
          ACCESS_CHANGED_CHANNEL,
          buildRealtimeRedisEnvelope({
            type: ACCESS_CHANGED_EVENT_TYPE,
            audience: { recipientUserIds: recipientChunk },
            payload: { reason },
          }),
        );
      } catch (error) {
        failedEventCount += 1;
        this.logger.error(
          `Access change publish failed: reason=${reason} recipientCount=${recipientChunk.length} error=${safeLogError(error)}`,
        );
      }
    }
    if (failedEventCount === 0) {
      this.logger.log(
        `Access change publish succeeded: reason=${reason} recipientCount=${recipientUserIds.length} eventCount=${chunks.length} durationMs=${Date.now() - startedAt}`,
      );
    } else {
      this.logger.warn(
        `Access change publish completed with gaps: reason=${reason} recipientCount=${recipientUserIds.length} eventCount=${chunks.length} failedEventCount=${failedEventCount} durationMs=${Date.now() - startedAt}`,
      );
    }
    return {
      recipientCount: recipientUserIds.length,
      eventCount: chunks.length,
      failedEventCount,
    };
  }

  private descendantNodeIds(
    nodes: Array<{ id: string; parentId: string | null }>,
    anchorIds: string[],
  ) {
    const impacted = new Set(anchorIds);
    let changed = true;
    while (changed) {
      changed = false;
      for (const node of nodes) {
        if (
          node.parentId &&
          impacted.has(node.parentId) &&
          !impacted.has(node.id)
        ) {
          impacted.add(node.id);
          changed = true;
        }
      }
    }
    return Array.from(impacted);
  }

  private normalizeIds(values: unknown[]) {
    const result: string[] = [];
    const seen = new Set<string>();
    for (const value of values) {
      const id = String(value ?? '').trim();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      result.push(id);
    }
    return result;
  }

  private normalizeReason(value: unknown) {
    const reason = String(value ?? '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 80);
    if (!reason) throw new Error('Access change reason is required');
    return reason;
  }

  private recipientLookupFailed(
    reasonInput: string,
    source: string,
    error: unknown,
  ) {
    const reason = this.normalizeReason(reasonInput);
    this.logger.error(
      `Access change recipient lookup failed: reason=${reason} source=${source} error=${safeLogError(error)}`,
    );
    return {
      recipientCount: 0,
      eventCount: 0,
      failedLookupCount: 1,
    };
  }

  private chunk<T>(items: T[], size: number) {
    const chunks: T[][] = [];
    for (let index = 0; index < items.length; index += size) {
      chunks.push(items.slice(index, index + size));
    }
    return chunks;
  }
}
