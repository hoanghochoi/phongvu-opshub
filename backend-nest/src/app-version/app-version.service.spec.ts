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
        APP_PACKAGE_SHA256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        APP_PACKAGE_SIZE_BYTES: '123456',
        APP_RELEASE_NOTES: 'Fixes',
        APP_FORCE_UPDATE: 'true',
      }),
    ).toEqual({
      platform: 'android',
      latestVersion: '1.2.3',
      latestBuild: 42,
      minSupportedBuild: 40,
      updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
      packageUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
      packageSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      packageSizeBytes: 123456,
      packageType: 'apk',
      installerArgs: [],
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
      packageUrl: '',
      packageSha256: '',
      packageSizeBytes: 0,
      packageType: 'apk',
      installerArgs: [],
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
          APP_WINDOWS_APP_PACKAGE_SHA256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          APP_WINDOWS_APP_PACKAGE_SIZE_BYTES: '987654',
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
      packageUrl:
        'https://opshub.hoanghochoi.com/downloads/app-windows-setup.exe',
      packageSha256:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      packageSizeBytes: 987654,
      packageType: 'windowsInstaller',
      installerArgs: [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
      ],
      releaseNotes: 'Windows fixes',
      forceUpdate: true,
    });
  });

  it('returns web metadata without app download requirements', () => {
    expect(
      service.getVersion(
        {
          APP_VERSION: '1.2.3',
          APP_BUILD_NUMBER: '42',
          APP_MIN_SUPPORTED_BUILD: '42',
          APP_UPDATE_URL: 'https://opshub.hoanghochoi.com/downloads/app.apk',
          APP_FORCE_UPDATE: 'true',
          APP_RELEASE_NOTES: 'Shared notes',
          APP_WEB_APP_VERSION: '1.2.5',
          APP_WEB_APP_BUILD_NUMBER: '45',
          APP_WEB_APP_RELEASE_NOTES: 'Web bundle refresh',
        },
        'web',
      ),
    ).toEqual({
      platform: 'web',
      latestVersion: '1.2.5',
      latestBuild: 45,
      minSupportedBuild: 1,
      updateUrl: '',
      packageUrl: '',
      packageSha256: '',
      packageSizeBytes: 0,
      packageType: 'web',
      installerArgs: [],
      releaseNotes: 'Web bundle refresh',
      forceUpdate: false,
    });
  });

  it('uses explicit self-update package URL and installer arguments', () => {
    expect(
      service.getVersion(
        {
          APP_WINDOWS_APP_VERSION: '1.2.6',
          APP_WINDOWS_APP_BUILD_NUMBER: '46',
          APP_WINDOWS_APP_UPDATE_URL:
            'https://opshub.hoanghochoi.com/downloads/manual.exe',
          APP_WINDOWS_APP_PACKAGE_URL:
            'https://opshub.hoanghochoi.com/downloads/self-update.exe',
          APP_WINDOWS_APP_PACKAGE_SHA256:
            'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
          APP_WINDOWS_APP_PACKAGE_SIZE_BYTES: '777',
          APP_WINDOWS_APP_INSTALLER_ARGS:
            '/VERYSILENT,/SUPPRESSMSGBOXES,/NORESTART',
        },
        'windows',
      ),
    ).toEqual(
      expect.objectContaining({
        platform: 'windows',
        updateUrl: 'https://opshub.hoanghochoi.com/downloads/manual.exe',
        packageUrl: 'https://opshub.hoanghochoi.com/downloads/self-update.exe',
        packageSha256:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        packageSizeBytes: 777,
        packageType: 'windowsInstaller',
        installerArgs: ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      }),
    );
  });

  it('publishes Android, Windows, and web metadata for realtime clients', async () => {
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
        APP_WEB_APP_BUILD_NUMBER: '44',
        APP_WEB_APP_MIN_SUPPORTED_BUILD: '1',
        APP_WEB_APP_FORCE_UPDATE: 'false',
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
          web: {
            latestVersion: '1.2.3',
            latestBuild: 44,
            minSupportedBuild: 1,
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
