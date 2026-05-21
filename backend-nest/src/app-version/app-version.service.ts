import { Injectable } from '@nestjs/common';

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
export class AppVersionService {
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
