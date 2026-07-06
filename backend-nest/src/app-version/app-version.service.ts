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
  packageUrl: string;
  packageSha256: string;
  packageSizeBytes: number;
  packageType: string;
  installerArgs: string[];
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
    const web = this.getVersion(env, 'web');
    const startedAt = Date.now();
    this.logger.log(
      `App version realtime publish started: androidBuild=${android.latestBuild} windowsBuild=${windows.latestBuild} webBuild=${web.latestBuild}`,
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
            web: realtimeVersionMetadata(web),
          },
        },
      );
      this.logger.log(
        `App version realtime publish completed: androidBuild=${android.latestBuild} windowsBuild=${windows.latestBuild} webBuild=${web.latestBuild} durationMs=${Date.now() - startedAt}`,
      );
      return true;
    } catch (error) {
      this.logger.error(
        `App version realtime publish failed: androidBuild=${android.latestBuild} windowsBuild=${windows.latestBuild} webBuild=${web.latestBuild} durationMs=${Date.now() - startedAt}`,
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
    const fallbackMinSupportedBuild =
      platform === 'web'
        ? 1
        : readPositiveInt(env.APP_MIN_SUPPORTED_BUILD, latestBuild);
    const minSupportedBuild = readPositiveInt(
      env[`${prefix}APP_MIN_SUPPORTED_BUILD`],
      fallbackMinSupportedBuild,
    );
    const updateUrl =
      platform === 'web'
        ? readString(env[`${prefix}APP_UPDATE_URL`], '')
        : readString(
            env[`${prefix}APP_UPDATE_URL`],
            readString(env.APP_UPDATE_URL, ''),
          );
    const packageUrl =
      platform === 'web'
        ? readString(env[`${prefix}APP_PACKAGE_URL`], updateUrl)
        : readString(
            env[`${prefix}APP_PACKAGE_URL`],
            readString(env.APP_PACKAGE_URL, updateUrl),
          );
    const forceUpdate =
      platform === 'web'
        ? readBoolean(env[`${prefix}APP_FORCE_UPDATE`], false)
        : readBoolean(
            env[`${prefix}APP_FORCE_UPDATE`],
            readBoolean(env.APP_FORCE_UPDATE, false),
          );

    return {
      platform,
      latestVersion: readString(
        env[`${prefix}APP_VERSION`],
        readString(env.APP_VERSION, '1.0.0'),
      ),
      latestBuild,
      minSupportedBuild,
      updateUrl,
      packageUrl,
      packageSha256:
        platform === 'web'
          ? readSha256(env[`${prefix}APP_PACKAGE_SHA256`])
          : readSha256(
              env[`${prefix}APP_PACKAGE_SHA256`] ?? env.APP_PACKAGE_SHA256,
            ),
      packageSizeBytes:
        platform === 'web'
          ? readNonNegativeInt(env[`${prefix}APP_PACKAGE_SIZE_BYTES`], 0)
          : readNonNegativeInt(
              env[`${prefix}APP_PACKAGE_SIZE_BYTES`],
              readNonNegativeInt(env.APP_PACKAGE_SIZE_BYTES, 0),
            ),
      packageType: readString(
        env[`${prefix}APP_PACKAGE_TYPE`],
        defaultPackageType(platform),
      ),
      installerArgs: readList(
        env[`${prefix}APP_INSTALLER_ARGS`],
        defaultInstallerArgs(platform),
      ),
      releaseNotes: readString(
        env[`${prefix}APP_RELEASE_NOTES`],
        readString(env.APP_RELEASE_NOTES, ''),
      ),
      forceUpdate,
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
  if (normalized === 'web') return 'web';
  if (normalized === 'android') return 'android';
  return 'android';
}

function platformEnvPrefix(platform: string): string {
  if (platform === 'windows') return 'APP_WINDOWS_';
  if (platform === 'web') return 'APP_WEB_';
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

function readNonNegativeInt(
  value: string | undefined,
  fallback: number,
): number {
  const trimmed = value?.trim();
  if (!trimmed) return fallback;

  const parsed = Number(trimmed);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : fallback;
}

function readBoolean(value: string | undefined, fallback: boolean): boolean {
  const trimmed = value?.trim().toLowerCase();
  if (!trimmed) return fallback;
  return ['1', 'true', 'yes', 'y'].includes(trimmed);
}

function readSha256(value: string | undefined): string {
  const trimmed = value?.trim().toLowerCase() ?? '';
  return /^[0-9a-f]{64}$/.test(trimmed) ? trimmed : '';
}

function readList(value: string | undefined, fallback: string[]): string[] {
  const trimmed = value?.trim();
  if (!trimmed) return fallback;
  return trimmed
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function defaultPackageType(platform: string): string {
  if (platform === 'windows') return 'windowsInstaller';
  if (platform === 'android') return 'apk';
  if (platform === 'web') return 'web';
  return 'unknown';
}

function defaultInstallerArgs(platform: string): string[] {
  if (platform !== 'windows') return [];
  return [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
  ];
}
