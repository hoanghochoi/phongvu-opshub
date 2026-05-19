import { Injectable } from '@nestjs/common';

type EnvMap = Record<string, string | undefined>;

export interface AppVersionResponse {
  latestVersion: string;
  latestBuild: number;
  minSupportedBuild: number;
  updateUrl: string;
  releaseNotes: string;
  forceUpdate: boolean;
}

@Injectable()
export class AppVersionService {
  getVersion(env: EnvMap = process.env): AppVersionResponse {
    const latestBuild = readPositiveInt(env.APP_BUILD_NUMBER, 1);
    const minSupportedBuild = readPositiveInt(
      env.APP_MIN_SUPPORTED_BUILD,
      latestBuild,
    );

    return {
      latestVersion: readString(env.APP_VERSION, '1.0.0'),
      latestBuild,
      minSupportedBuild,
      updateUrl: readString(env.APP_UPDATE_URL, ''),
      releaseNotes: readString(env.APP_RELEASE_NOTES, ''),
      forceUpdate: readBoolean(env.APP_FORCE_UPDATE, false),
    };
  }
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
