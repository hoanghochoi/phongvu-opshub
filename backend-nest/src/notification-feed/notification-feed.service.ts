import { Injectable, Logger } from '@nestjs/common';
import { safeLogError } from '../common/log-sanitizer';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { FeatureService } from '../feature/feature.service';
import { MapVietinService } from '../map-vietin/map-vietin.service';
import { OffsetAdjustmentsService } from '../offset-adjustments/offset-adjustments.service';

@Injectable()
export class NotificationFeedService {
  private readonly logger = new Logger(NotificationFeedService.name);

  constructor(
    private readonly featureService: FeatureService,
    private readonly mapVietinService: MapVietinService,
    private readonly offsetAdjustmentsService: OffsetAdjustmentsService,
  ) {}

  async load(user: any) {
    const startedAt = Date.now();
    const userId = String(user?.id || '').trim();
    this.logger.log(
      `Notification feed load started: userId=${this.safeUserId(userId)}`,
    );
    try {
      const access = await this.featureService.resolveFeatureAccessMap(user);
      const statementsEnabled = access[FEATURE_KEYS.BANK_STATEMENTS] === true;
      const offsetsEnabled = access[FEATURE_KEYS.OFFSET_ADJUSTMENTS] === true;
      const [statementOrderTransfers, offsetAdjustments] = await Promise.all([
        statementsEnabled
          ? this.mapVietinService.listStatementOrderTransferRequests(user, {
              status: 'NOTIFICATION',
              page: 0,
              limit: 20,
            })
          : Promise.resolve(this.emptyStatementFeed()),
        offsetsEnabled
          ? this.offsetAdjustmentsService.list(user, {
              type: 'ALL',
              status: 'NOTIFICATION',
              page: 0,
              limit: 20,
            })
          : Promise.resolve(this.emptyOffsetFeed()),
      ]);
      const result = {
        schemaVersion: 1,
        generatedAt: new Date().toISOString(),
        statementOrderTransfers: {
          enabled: statementsEnabled,
          ...statementOrderTransfers,
        },
        offsetAdjustments: {
          enabled: offsetsEnabled,
          ...offsetAdjustments,
        },
      };
      this.logger.log(
        `Notification feed load succeeded: userId=${this.safeUserId(userId)} statementEnabled=${statementsEnabled} statementCount=${statementOrderTransfers.list.length} offsetEnabled=${offsetsEnabled} offsetCount=${offsetAdjustments.list.length} durationMs=${Date.now() - startedAt}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `Notification feed load failed: userId=${this.safeUserId(userId)} durationMs=${Date.now() - startedAt} error=${safeLogError(error)}`,
      );
      throw error;
    }
  }

  private emptyStatementFeed() {
    return { page: 0, limit: 20, total: 0, canReview: false, list: [] };
  }

  private emptyOffsetFeed() {
    return { page: 0, limit: 20, total: 0, canReview: false, list: [] };
  }

  private safeUserId(userId: string) {
    return userId || 'missing';
  }
}
