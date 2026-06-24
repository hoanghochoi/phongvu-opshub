import { AppVersionService } from './app-version.service';

describe('AppVersionService', () => {
  const service = new AppVersionService();

  it('returns configured update metadata', () => {
    expect(
      service.getVersion({
        APP_VERSION: '1.2.3',
        APP_BUILD_NUMBER: '42',
        APP_MIN_SUPPORTED_BUILD: '40',
        APP_UPDATE_URL: 'https://opshub.hoanghochoi.com/downloads/app.apk',
        APP_RELEASE_NOTES: 'Fixes',
        APP_FORCE_UPDATE: 'true',
      }),
    ).toEqual({
      platform: 'android',
      latestVersion: '1.2.3',
      latestBuild: 42,
      minSupportedBuild: 40,
      updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
      releaseNotes: 'Fixes',
      forceUpdate: true,
    });
  });

  it('falls back to safe defaults for missing or invalid values', () => {
    expect(
      service.getVersion({
        APP_BUILD_NUMBER: 'abc',
        APP_MIN_SUPPORTED_BUILD: '-1',
      }),
    ).toEqual({
      platform: 'android',
      latestVersion: '1.0.0',
      latestBuild: 1,
      minSupportedBuild: 1,
      updateUrl: '',
      releaseNotes: '',
      forceUpdate: false,
    });
  });

  it('returns Windows-specific metadata when platform is windows', () => {
    expect(
      service.getVersion(
        {
          APP_VERSION: '1.2.3',
          APP_BUILD_NUMBER: '42',
          APP_UPDATE_URL: 'https://opshub.hoanghochoi.com/downloads/app.apk',
          APP_WINDOWS_APP_VERSION: '1.2.4',
          APP_WINDOWS_APP_BUILD_NUMBER: '43',
          APP_WINDOWS_APP_MIN_SUPPORTED_BUILD: '43',
          APP_WINDOWS_APP_UPDATE_URL:
            'https://opshub.hoanghochoi.com/downloads/app-windows-setup.exe',
          APP_WINDOWS_APP_RELEASE_NOTES: 'Windows fixes',
          APP_WINDOWS_APP_FORCE_UPDATE: 'true',
        },
        'windows',
      ),
    ).toEqual({
      platform: 'windows',
      latestVersion: '1.2.4',
      latestBuild: 43,
      minSupportedBuild: 43,
      updateUrl:
        'https://opshub.hoanghochoi.com/downloads/app-windows-setup.exe',
      releaseNotes: 'Windows fixes',
      forceUpdate: true,
    });
  });

  it('publishes Android and Windows metadata for realtime clients', async () => {
    const redis = {
      publishMessageOrThrow: jest.fn().mockResolvedValue(undefined),
    };
    const publishingService = new AppVersionService(redis as any);

    await expect(
      publishingService.publishCurrentVersionMetadata({
        APP_VERSION: '1.2.3',
        APP_BUILD_NUMBER: '42',
        APP_MIN_SUPPORTED_BUILD: '40',
        APP_FORCE_UPDATE: 'true',
        APP_WINDOWS_APP_VERSION: '1.2.4',
        APP_WINDOWS_APP_BUILD_NUMBER: '43',
        APP_WINDOWS_APP_MIN_SUPPORTED_BUILD: '41',
        APP_WINDOWS_APP_FORCE_UPDATE: 'false',
      }),
    ).resolves.toBe(true);

    expect(redis.publishMessageOrThrow).toHaveBeenCalledWith(
      'APP_VERSION_UPDATED',
      expect.objectContaining({
        schemaVersion: 1,
        publishedAt: expect.any(String),
        platforms: {
          android: {
            latestVersion: '1.2.3',
            latestBuild: 42,
            minSupportedBuild: 40,
            forceUpdate: true,
          },
          windows: {
            latestVersion: '1.2.4',
            latestBuild: 43,
            minSupportedBuild: 41,
            forceUpdate: false,
          },
        },
      }),
    );
  });

  it('reports realtime publish failure without blocking application startup', async () => {
    const redis = {
      publishMessageOrThrow: jest
        .fn()
        .mockRejectedValue(new Error('Redis unavailable')),
    };
    const publishingService = new AppVersionService(redis as any);

    await expect(
      publishingService.publishCurrentVersionMetadata({
        APP_BUILD_NUMBER: '42',
        APP_WINDOWS_APP_BUILD_NUMBER: '43',
      }),
    ).resolves.toBe(false);
  });
});
