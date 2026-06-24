import {
  Injectable,
  Logger,
  OnApplicationBootstrap,
  Optional,
} from '@nestjs/common';
import { RedisService } from '../redis/redis.service';

const APP_VERSION_UPDATED_CHANNEL = 'APP_VERSION_UPDATED';

type EnvMap = Record<string, string | undefined>;

export interface AppVersionResponse {
  platform: string;
  latestVersion: string;
  latestBuild: number;
  minSupportedBuild: number;
  updateUrl: string;
  releaseNotes: string;
  forceUpdate: boolean;
}

@Injectable()
export class AppVersionService implements OnApplicationBootstrap {
  private readonly logger = new Logger(AppVersionService.name);

  constructor(@Optional() private readonly redisService?: RedisService) {}

  onApplicationBootstrap() {
    void this.publishCurrentVersionMetadata();
  }

  async publishCurrentVersionMetadata(env: EnvMap = process.env) {
    if (!this.redisService) {
      this.logger.warn(
        'App version realtime publish skipped: RedisService is unavailable',
      );
      return false;
    }

    const android = this.getVersion(env, 'android');
    const windows = this.getVersion(env, 'windows');
    const startedAt = Date.now();
    this.logger.log(
      `App version realtime publish started: androidBuild=${android.latestBuild} windowsBuild=${windows.latestBuild}`,
    );
    try {
      await this.redisService.publishMessageOrThrow(
        APP_VERSION_UPDATED_CHANNEL,
        {
          schemaVersion: 1,
          publishedAt: new Date().toISOString(),
          platforms: {
            android: realtimeVersionMetadata(android),
            windows: realtimeVersionMetadata(windows),
          },
        },
      );
      this.logger.log(
        `App version realtime publish completed: androidBuild=${android.latestBuild} windowsBuild=${windows.latestBuild} durationMs=${Date.now() - startedAt}`,
      );
      return true;
    } catch (error) {
      this.logger.error(
        `App version realtime publish failed: androidBuild=${android.latestBuild} windowsBuild=${windows.latestBuild} durationMs=${Date.now() - startedAt}`,
        error instanceof Error ? error.stack : String(error),
      );
      return false;
    }
  }

  getVersion(
    env: EnvMap = process.env,
    platformInput?: string,
  ): AppVersionResponse {
    const platform = normalizePlatform(platformInput);
    const prefix = platformEnvPrefix(platform);
    const latestBuild = readPositiveInt(
      env[`${prefix}APP_BUILD_NUMBER`],
      readPositiveInt(env.APP_BUILD_NUMBER, 1),
    );
    const minSupportedBuild = readPositiveInt(
      env[`${prefix}APP_MIN_SUPPORTED_BUILD`],
      readPositiveInt(env.APP_MIN_SUPPORTED_BUILD, latestBuild),
    );

    return {
      platform,
      latestVersion: readString(
        env[`${prefix}APP_VERSION`],
        readString(env.APP_VERSION, '1.0.0'),
      ),
      latestBuild,
      minSupportedBuild,
      updateUrl: readString(
        env[`${prefix}APP_UPDATE_URL`],
        readString(env.APP_UPDATE_URL, ''),
      ),
      releaseNotes: readString(
        env[`${prefix}APP_RELEASE_NOTES`],
        readString(env.APP_RELEASE_NOTES, ''),
      ),
      forceUpdate: readBoolean(
        env[`${prefix}APP_FORCE_UPDATE`],
        readBoolean(env.APP_FORCE_UPDATE, false),
      ),
    };
  }
}

function realtimeVersionMetadata(info: AppVersionResponse) {
  return {
    latestVersion: info.latestVersion,
    latestBuild: info.latestBuild,
    minSupportedBuild: info.minSupportedBuild,
    forceUpdate: info.forceUpdate,
  };
}

function normalizePlatform(value: string | undefined): string {
  const normalized = value?.trim().toLowerCase();
  if (normalized === 'windows') return 'windows';
  if (normalized === 'android') return 'android';
  return 'android';
}

function platformEnvPrefix(platform: string): string {
  if (platform === 'windows') return 'APP_WINDOWS_';
  if (platform === 'android') return 'APP_ANDROID_';
  return '';
}

function readString(value: string | undefined, fallback: string): string {
  const trimmed = value?.trim();
  return trimmed ? trimmed : fallback;
}

function readPositiveInt(value: string | undefined, fallback: number): number {
  const trimmed = value?.trim();
  if (!trimmed) return fallback;

  const parsed = Number(trimmed);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function readBoolean(value: string | undefined, fallback: boolean): boolean {
  const trimmed = value?.trim().toLowerCase();
  if (!trimmed) return fallback;
  return ['1', 'true', 'yes', 'y'].includes(trimmed);
}
